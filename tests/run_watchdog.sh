#!/bin/sh
# CarModem — тесты логики watchdog (без железа): все ветки эскалации на моках.
# Запуск: sh tests/run_watchdog.sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SHARE="$ROOT/luci-app-carmodem/root/usr/share/carmodem"
export CM_SHARE="$SHARE"
export CM_MM_AWK="$SHARE/mm.awk"
export CM_MM_RAW="$HERE/mocks/mock_mmcli.sh"   # для cm_wd_netdev (не критично: инет форсим)

TMP="${TMPDIR:-/tmp}/cm_wd_test.$$"
mkdir -p "$TMP"
export CM_WD_DIR="$TMP"
export CM_WD_EPISODE="$TMP/wd.rebooted"
export CM_WD_NO_ACT=1                          # не выполнять reboot/reset/dial реально
UCI_STATE="$TMP/uci.txt"; : > "$UCI_STATE"

. "$SHARE/mm.sh"
. "$SHARE/control.sh"
. "$SHARE/watchdog.sh"

# --- мок uci: читает/пишет плоский файл key=value ---------------------------
uci() {
    case "${1:-} ${2:-}" in
        "-q get")    grep "^$3=" "$UCI_STATE" 2>/dev/null | head -1 | cut -d= -f2- ;;
        "-q set")    _k=${3%%=*}; _v=${3#*=}; grep -v "^$_k=" "$UCI_STATE" > "$UCI_STATE.t" 2>/dev/null; echo "$_k=$_v" >> "$UCI_STATE.t"; mv "$UCI_STATE.t" "$UCI_STATE" ;;
        "-q commit") : ;;
    esac
}
# --- тест-двойники состояния модема/сигнала/индекса -------------------------
FAKE_STATE=connected
cm_mm_conn()        { printf '{"state":"%s","access_tech":"lte"}' "$FAKE_STATE"; }
cm_mm_signal()      { printf '{"rsrp":-90,"sinr":15}'; }
cm_mm_resolve_idx() { echo 0; }
# сервис-синхронизация не нужна в тестах
cm_wd_service_sync() { :; }

pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); printf '  FAIL %s\n    want: %s\n    got:  %s\n' "$1" "$3" "$2"; fi; }
has_file()   { if [ -f "$2" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (нет файла $2)"; fi; }
no_file()    { if [ ! -f "$2" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (файл есть $2)"; fi; }
act()    { sed -n 's/.*"last_action":"\([^"]*\)".*/\1/p' "$TMP/carmodem-wd.status" 2>/dev/null; }
strike() { cat "$TMP/carmodem-wd.strike" 2>/dev/null || echo -1; }

echo "CarModem watchdog tests"
echo
echo "carmodem.watchdog.enabled=1" > "$UCI_STATE"   # пороги — дефолтные (l1=2,l2=5,l3=8)

echo "[нет сигнала: интернета нет + не зарегистрирован -> бездействие]"
export CM_WD_FORCE_INET=down; FAKE_STATE=searching
cm_wd_cycle
eq wd_nosignal_action "$(act)" 'wait_no_signal'
eq wd_nosignal_strike "$(strike)" '0'

echo
echo "[эскалация при живой сети без интернета: L1->L2->L3 сверху вниз]"
FAKE_STATE=connected
cm_wd_cycle; eq wd_s1 "$(strike)" '1'; eq wd_a1 "$(act)" 'wait_strike'
cm_wd_cycle; eq wd_a2 "$(act)" 'iface_reconnect'   # strike 2 >= L1
cm_wd_cycle; eq wd_a3 "$(act)" 'iface_reconnect'   # strike 3
cm_wd_cycle                                        # strike 4
cm_wd_cycle; eq wd_a5 "$(act)" 'modem_reset'       # strike 5 >= L2 (cooldown стартует)
cm_wd_cycle; eq wd_a6 "$(act)" 'skip_reset_cooldown'
cm_wd_cycle                                        # strike 7
cm_wd_cycle; eq wd_a8 "$(act)" 'router_reboot'     # strike 8 >= L3
has_file wd_episode_flag "$CM_WD_EPISODE"
cm_wd_cycle; eq wd_a9 "$(act)" 'skip_reboot_once'  # флаг эпизода -> не ребутим повторно

echo
echo "[возврат интернета: сброс strike + снятие флага эпизода]"
export CM_WD_FORCE_INET=up
cm_wd_cycle; eq wd_ok "$(act)" 'ok'; eq wd_ok_strike "$(strike)" '0'
no_file wd_episode_cleared "$CM_WD_EPISODE"

echo
echo "[хук восстановления: сервис перезапускается при переходе down->up]"
uci -q set carmodem.watchdog.recovery_service=podkop
export CM_WD_FORCE_INET=down; FAKE_STATE=connected; cm_wd_cycle   # inet-файл = down
export CM_WD_FORCE_INET=up; cm_wd_cycle
eq wd_recovery "$(act)" 'recovery_hook'

echo
echo "[L3 выключен: при allow_reboot=0 ребут не срабатывает]"
uci -q set carmodem.watchdog.allow_reboot=0
rm -f "$CM_WD_EPISODE" "$TMP/carmodem-wd.reset.ts"
export CM_WD_FORCE_INET=down; FAKE_STATE=connected
i=0; while [ "$i" -lt 9 ]; do cm_wd_cycle; i=$((i+1)); done   # strike 9 (было 0 после up)
eq wd_no_reboot "$(act)" 'skip_reset_cooldown'                # застревает на L2, не L3
no_file wd_no_episode "$CM_WD_EPISODE"

echo
echo "[registered без bearer: L1/L2, но БЕЗ ребута роутера даже при высоком strike]"
uci -q set carmodem.watchdog.allow_reboot=1
export CM_WD_FORCE_INET=up; FAKE_STATE=connected; cm_wd_cycle       # сброс strike=0
rm -f "$CM_WD_EPISODE" "$TMP/carmodem-wd.reset.ts"
export CM_WD_FORCE_INET=down; FAKE_STATE=registered
i=0; while [ "$i" -lt 10 ]; do cm_wd_cycle; i=$((i+1)); done        # strike 10 >> L3(8)
eq wd_reg_no_reboot "$(act)" 'skip_reset_cooldown'                 # застряли на L2, не L3
no_file wd_reg_no_episode "$CM_WD_EPISODE"

echo
echo "[connecting: переходное -> бездействие, strike не растёт (не сбить дозвон)]"
export CM_WD_FORCE_INET=up; FAKE_STATE=connected; cm_wd_cycle       # сброс
export CM_WD_FORCE_INET=down; FAKE_STATE=connecting
cm_wd_cycle; cm_wd_cycle
eq wd_connecting_action "$(act)" 'wait_no_signal'
eq wd_connecting_strike "$(strike)" '0'

echo
echo "[сброс счётчика]"
cm_wd_clear >/dev/null 2>&1
eq wd_clear "$(strike)" '0'

rm -rf "$TMP"
echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
