# CarModem — watchdog авто-восстановления связи модема
# SPDX-License-Identifier: GPL-2.0
#
# Один цикл: проверить интернет (ping) + состояние/сигнал модема (через MM) и,
# если при ЖИВОЙ регистрации в сети интернета нет N циклов подряд, эскалировать
# СВЕРХУ ВНИЗ (одно действие за цикл):
#   L3  reboot роутера (opt-in, 1 раз за эпизод, флаг на flash)
#   L2  mmcli --reset (cm_reset_modem, cooldown) — координированно с MM
#   L1  ifdown/ifup WAN (cm_dial)
# Нет сигнала/регистрации (крытая парковка) -> ничего не трогаем.
# Всё изменчивое состояние — на tmpfs; на flash только крошечный флаг эпизода.
# НЕ используем `set -u` — файл сорсится в rpcd (не ломаем родительский шелл).
#
# Тест-оверрайды: CM_WD_DIR (пути), CM_WD_EPISODE (флаг), CM_WD_FORCE_INET=up|down,
# CM_WD_NO_ACT=1 (не выполнять reboot/reset/dial), CM_MM_RAW (мок mmcli).

CM_SHARE="${CM_SHARE:-/usr/share/carmodem}"
command -v cm_mm_conn >/dev/null 2>&1 || . "$CM_SHARE/mm.sh"
command -v cm_dial    >/dev/null 2>&1 || . "$CM_SHARE/control.sh"

WD_DIR="${CM_WD_DIR:-/tmp}"
WD_STRIKE_FILE="$WD_DIR/carmodem-wd.strike"
WD_RESET_TS_FILE="$WD_DIR/carmodem-wd.reset.ts"
WD_STATUS_FILE="$WD_DIR/carmodem-wd.status"
WD_LOG_FILE="$WD_DIR/carmodem-wd.log"
WD_INET_FILE="$WD_DIR/carmodem-wd.inet"
WD_EPISODE="${CM_WD_EPISODE:-/etc/carmodem/wd.rebooted}"   # на flash — переживает reboot
WD_LOG_MAX=200

# --- конфиг из UCI (с дефолтами) --------------------------------------------
cm_wd_cfg() {
    WD_ENABLED=$(uci -q get carmodem.watchdog.enabled 2>/dev/null);           WD_ENABLED=${WD_ENABLED:-0}
    WD_INTERVAL=$(uci -q get carmodem.watchdog.interval 2>/dev/null);         WD_INTERVAL=${WD_INTERVAL:-60}
    WD_PING=$(uci -q get carmodem.watchdog.ping_hosts 2>/dev/null);           WD_PING=${WD_PING:-1.1.1.1 8.8.8.8 77.88.8.8}
    WD_L1=$(uci -q get carmodem.watchdog.l1_reconnect 2>/dev/null);           WD_L1=${WD_L1:-2}
    WD_L2=$(uci -q get carmodem.watchdog.l2_reset 2>/dev/null);               WD_L2=${WD_L2:-5}
    WD_L3=$(uci -q get carmodem.watchdog.l3_reboot 2>/dev/null);              WD_L3=${WD_L3:-8}
    WD_CD_RESET=$(uci -q get carmodem.watchdog.cooldown_reset 2>/dev/null);   WD_CD_RESET=${WD_CD_RESET:-300}
    WD_ALLOW_REBOOT=$(uci -q get carmodem.watchdog.allow_reboot 2>/dev/null); WD_ALLOW_REBOOT=${WD_ALLOW_REBOOT:-1}
    WD_RECOVERY=$(uci -q get carmodem.watchdog.recovery_service 2>/dev/null); WD_RECOVERY=${WD_RECOVERY:-}
    WD_WANDEV_OVR=$(uci -q get carmodem.watchdog.wan_netdev 2>/dev/null);     WD_WANDEV_OVR=${WD_WANDEV_OVR:-}
    WD_IFACE=$(uci -q get carmodem.watchdog.wan_iface 2>/dev/null);           WD_IFACE=${WD_IFACE:-wwan}
    # интервал не меньше 5 c — иначе петля вырождается в busy-loop, штурмующий модем
    case "$WD_INTERVAL" in ''|*[!0-9]*) WD_INTERVAL=60 ;; esac
    [ "$WD_INTERVAL" -lt 5 ] 2>/dev/null && WD_INTERVAL=60
}

# WAN-netdev: override -> активный bearer MM (как в cm_mm_status).
cm_wd_netdev() {
    [ -n "$WD_WANDEV_OVR" ] && { printf '%s' "$WD_WANDEV_OVR"; return; }
    _m=$(cm_mm_raw -m "$CM_MM_INDEX" 2>/dev/null)
    _b=$(printf '%s\n' "$_m" | sed -n 's#.*bearers\.value\[1\].*Bearer/\([0-9]\{1,\}\).*#\1#p' | head -1)
    [ -n "$_b" ] && cm_mm_raw -b "$_b" 2>/dev/null | sed -n 's/.*bearer\.status\.interface *: *//p' | head -1
}

# Интернет наружу: заполняет WD_INET (up/down) и WD_RTT (мс).
cm_wd_internet() {
    WD_INET="down"; WD_RTT=""
    [ -n "${CM_WD_FORCE_INET:-}" ] && { WD_INET="$CM_WD_FORCE_INET"; return; }
    # Если netdev модема известен — мерим инет ТОЛЬКО через него (ping -I). Иначе
    # (нет bearer'а) допускаем ping без привязки. Безусловного фолбэка НЕТ: иначе
    # мёртвый модемный инет маскировался бы живым Wi-Fi/eth-аплинком (ложный up).
    _nd=$(cm_wd_netdev)
    for _h in $WD_PING; do
        if [ -n "$_nd" ]; then _o=$(ping -c1 -W2 -I "$_nd" "$_h" 2>/dev/null)
        else                   _o=$(ping -c1 -W2 "$_h" 2>/dev/null); fi
        [ $? -eq 0 ] && { WD_INET="up"; WD_RTT=$(printf '%s' "$_o" | grep -o 'time=[0-9.]*' | head -1 | sed 's/time=//'); return; }
    done
}

# Категория состояния модема (WD_CAT) из MM:
#   connected  — bearer поднят (данные должны идти) -> полная эскалация вкл. L3
#   registered — на сети, но без активного bearer  -> только L1/L2 (модем/netifd
#                сами поднимают сессию; ребут роутера тут неуместен)
#   wait       — connecting (переходное, модем работает) / searching / idle / нет
#                регистрации -> НЕ эскалируем, strike сбрасываем
# rc 0 = на сети (connected|registered), rc 1 = wait.
cm_wd_modem() {
    _c=$(cm_mm_conn 2>/dev/null)
    WD_STATE=$(printf '%s' "$_c" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
    WD_TECH=$(printf '%s' "$_c" | sed -n 's/.*"access_tech":"\([^"]*\)".*/\1/p')
    case "$WD_STATE" in
        connected)  WD_CAT="connected";  return 0 ;;
        registered) WD_CAT="registered"; return 0 ;;
        *)          WD_CAT="wait";       return 1 ;;
    esac
}
cm_wd_signal() {
    _s=$(cm_mm_signal 2>/dev/null)
    WD_RSRP=$(printf '%s' "$_s" | sed -n 's/.*"rsrp":\(-\{0,1\}[0-9]*\).*/\1/p')
    WD_SINR=$(printf '%s' "$_s" | sed -n 's/.*"sinr":\(-\{0,1\}[0-9.]*\).*/\1/p')
}

cm_wd_read_strike() { [ -f "$WD_STRIKE_FILE" ] && cat "$WD_STRIKE_FILE" 2>/dev/null || echo 0; }

cm_wd_log() {  # <action> <detail>
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    logger -t carmodem-wd "$1: $2 (inet=${WD_INET} state=${WD_STATE} strike=${WD_STRIKE})" 2>/dev/null
    printf '%s|%s|rtt=%s|%s|%s|rsrp=%s|sinr=%s|strike=%s|%s|%s\n' \
        "$_ts" "${WD_INET}" "${WD_RTT}" "${WD_STATE}" "${WD_TECH}" "${WD_RSRP}" "${WD_SINR}" "${WD_STRIKE}" "$1" "$2" \
        >> "$WD_LOG_FILE" 2>/dev/null
    _ln=$(wc -l < "$WD_LOG_FILE" 2>/dev/null || echo 0)
    [ "${_ln:-0}" -gt "$WD_LOG_MAX" ] && { tail -n "$WD_LOG_MAX" "$WD_LOG_FILE" > "$WD_LOG_FILE.t" 2>/dev/null && mv "$WD_LOG_FILE.t" "$WD_LOG_FILE"; }
}

cm_wd_status_write() {  # <phase> <action> <next>
    _reb=0; [ -f "$WD_EPISODE" ] && _reb=1
    printf '{"enabled":%s,"internet":"%s","rtt":"%s","state":"%s","tech":"%s","rsrp":"%s","sinr":"%s","strike":%s,"phase":"%s","last_action":"%s","next":"%s","episode_rebooted":%s,"ts":"%s"}\n' \
        "${WD_ENABLED:-0}" "${WD_INET}" "${WD_RTT}" "${WD_STATE}" "${WD_TECH}" "${WD_RSRP}" "${WD_SINR}" \
        "${WD_STRIKE:-0}" "$1" "$2" "$3" "$_reb" "$(date '+%Y-%m-%d %H:%M:%S')" > "$WD_STATUS_FILE.t" 2>/dev/null
    mv "$WD_STATUS_FILE.t" "$WD_STATUS_FILE" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ОДИН ЦИКЛ
# ---------------------------------------------------------------------------
cm_wd_cycle() {
    cm_wd_cfg
    CM_MM_INDEX=$(cm_mm_resolve_idx 2>/dev/null); CM_MM_INDEX=${CM_MM_INDEX:-0}
    export CM_WWAN_IFACE="${WD_IFACE:-wwan}"   # логический интерфейс для L1 (cm_dial)
    WD_STRIKE=$(cm_wd_read_strike)
    cm_wd_internet
    cm_wd_modem; _hasnet=$?
    cm_wd_signal
    _prev=$([ -f "$WD_INET_FILE" ] && cat "$WD_INET_FILE" 2>/dev/null || echo "")
    printf '%s' "$WD_INET" > "$WD_INET_FILE" 2>/dev/null

    # --- A. интернет ЕСТЬ -> сброс strike, снять эпизод, хук восстановления ---
    if [ "$WD_INET" = "up" ]; then
        echo 0 > "$WD_STRIKE_FILE" 2>/dev/null; WD_STRIKE=0
        rm -f "$WD_EPISODE" 2>/dev/null
        if [ "$_prev" = "down" ] && [ -n "$WD_RECOVERY" ]; then
            [ "${CM_WD_NO_ACT:-0}" = "1" ] || /etc/init.d/"$WD_RECOVERY" restart >/dev/null 2>&1
            cm_wd_log "recovery_hook" "internet restored -> restart $WD_RECOVERY"
            cm_wd_status_write "ok" "recovery_hook" ""
            return 0
        fi
        cm_wd_log "ok" "internet up"
        cm_wd_status_write "ok" "ok" ""
        return 0
    fi

    # --- B. интернета НЕТ ---
    if [ "$_hasnet" != "0" ]; then                       # нет сигнала/регистрации
        echo 0 > "$WD_STRIKE_FILE" 2>/dev/null; WD_STRIKE=0
        cm_wd_log "wait_no_signal" "no internet, modem not registered (state=$WD_STATE)"
        cm_wd_status_write "no-signal" "wait_no_signal" ""
        return 0
    fi

    # сеть есть, интернета нет -> счётчик растёт непрерывно (сброс только в ветке A)
    WD_STRIKE=$(( WD_STRIKE + 1 )); echo "$WD_STRIKE" > "$WD_STRIKE_FILE" 2>/dev/null

    # L3 — reboot роутера. ТОЛЬКО при WD_CAT=connected (bearer поднят, но данных
    # нет = реальный «залип»). registered/connecting модем поднимает сам -> не
    # ребутим, иначе сбиваем идущее самовосстановление (critical-фикс ревью).
    if [ "$WD_CAT" = "connected" ] && [ "$WD_STRIKE" -ge "$WD_L3" ] && [ "$WD_ALLOW_REBOOT" = "1" ]; then
        if [ -f "$WD_EPISODE" ]; then
            cm_wd_log "skip_reboot_once" "strike=$WD_STRIKE, already rebooted this episode"
            cm_wd_status_write "escalating" "skip_reboot_once" ""
            return 0
        fi
        mkdir -p "$(dirname "$WD_EPISODE")" 2>/dev/null
        echo "$(date '+%Y-%m-%d %H:%M:%S') strike=$WD_STRIKE" > "$WD_EPISODE" 2>/dev/null; sync 2>/dev/null
        # НЕ ребутим, если флаг не лёг на flash (ro/битый overlay): иначе после
        # ребута strike (tmpfs) обнулён, флага нет -> бесконечный boot-loop.
        if [ ! -f "$WD_EPISODE" ]; then
            cm_wd_log "reboot_flag_failed" "cannot persist episode flag (ro overlay?) -> NOT rebooting"
            cm_wd_status_write "escalating" "reboot_flag_failed" ""
            return 0
        fi
        cm_wd_log "router_reboot" "strike=$WD_STRIKE, connected but no data -> reboot router"
        cm_wd_status_write "escalating" "router_reboot" ""
        [ "${CM_WD_NO_ACT:-0}" = "1" ] || { sync; reboot; }
        return 0
    fi

    # L2 — mmcli --reset (cooldown)
    if [ "$WD_STRIKE" -ge "$WD_L2" ]; then
        _now=$(date +%s); _last=$([ -f "$WD_RESET_TS_FILE" ] && cat "$WD_RESET_TS_FILE" 2>/dev/null || echo 0)
        if [ $(( _now - _last )) -ge "$WD_CD_RESET" ]; then
            echo "$_now" > "$WD_RESET_TS_FILE" 2>/dev/null
            cm_wd_log "modem_reset" "strike=$WD_STRIKE -> mmcli --reset"
            cm_wd_status_write "escalating" "modem_reset" ""
            [ "${CM_WD_NO_ACT:-0}" = "1" ] || cm_reset_modem >/dev/null 2>&1
            return 0
        fi
        cm_wd_log "skip_reset_cooldown" "strike=$WD_STRIKE, reset in cooldown"
        cm_wd_status_write "escalating" "skip_reset_cooldown" ""
        return 0
    fi

    # L1 — реконнект интерфейса
    if [ "$WD_STRIKE" -ge "$WD_L1" ]; then
        cm_wd_log "iface_reconnect" "strike=$WD_STRIKE -> ifdown/ifup WAN"
        cm_wd_status_write "escalating" "iface_reconnect" ""
        [ "${CM_WD_NO_ACT:-0}" = "1" ] || { cm_dial false >/dev/null 2>&1; sleep 3; cm_dial true >/dev/null 2>&1; }
        return 0
    fi

    cm_wd_log "wait_strike" "signal ok, no internet, strike=$WD_STRIKE (<L1)"
    cm_wd_status_write "escalating" "wait_strike" ""
    return 0
}

# Безопасный снимок для кнопки «Проверить сейчас»: измеряет интернет/модем/сигнал
# и обновляет статус, НО не меняет strike и НЕ выполняет действий (иначе клик мог
# бы перезагрузить роутер при высоком strike). Реальная эскалация — только в петле.
cm_wd_probe() {
    cm_wd_cfg
    CM_MM_INDEX=$(cm_mm_resolve_idx 2>/dev/null); CM_MM_INDEX=${CM_MM_INDEX:-0}
    WD_STRIKE=$(cm_wd_read_strike)
    cm_wd_internet
    cm_wd_modem; _hn=$?
    cm_wd_signal
    if [ "$WD_INET" = "up" ]; then _ph="ok"
    elif [ "$_hn" != "0" ]; then _ph="no-signal"
    else _ph="escalating"; fi
    cm_wd_log "probe" "manual check (no action)"
    cm_wd_status_write "$_ph" "probe" ""
}

# ---------------------------------------------------------------------------
# Обвязка: петля procd, RPC-статус, применение конфига, сброс
# ---------------------------------------------------------------------------
cm_wd_loop() {
    while :; do
        cm_wd_cfg
        [ "$WD_ENABLED" = "1" ] || { sleep 30; continue; }
        cm_wd_cycle
        sleep "${WD_INTERVAL:-60}"
    done
}

# JSON для RPC: конфиг + последний снимок (live) + хвост лога массивом строк.
cm_wd_status_json() {
    cm_wd_cfg
    _live="{}"; [ -f "$WD_STATUS_FILE" ] && _live=$(cat "$WD_STATUS_FILE" 2>/dev/null)
    [ -n "$_live" ] || _live="{}"
    _cfg=$(printf '{"enabled":%s,"interval":%s,"ping_hosts":"%s","l1_reconnect":%s,"l2_reset":%s,"l3_reboot":%s,"cooldown_reset":%s,"allow_reboot":%s,"recovery_service":"%s","wan_netdev":"%s","wan_iface":"%s"}' \
        "${WD_ENABLED:-0}" "${WD_INTERVAL:-60}" "$WD_PING" "$WD_L1" "$WD_L2" "$WD_L3" "$WD_CD_RESET" "$WD_ALLOW_REBOOT" "$WD_RECOVERY" "$WD_WANDEV_OVR" "$WD_IFACE")
    _log="[]"
    if [ -f "$WD_LOG_FILE" ]; then
        _log=$(tail -n 60 "$WD_LOG_FILE" 2>/dev/null | awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\");gsub(/"/,"\\\"");printf "%s\"%s\"",(NR>1?",":""),$0} END{print "]"}')
        [ -n "$_log" ] || _log="[]"
    fi
    printf '{"config":%s,"live":%s,"log":%s}\n' "$_cfg" "$_live" "$_log"
}

# Включить/выключить сервис по текущему UCI.
cm_wd_service_sync() {
    cm_wd_cfg
    if [ "$WD_ENABLED" = "1" ]; then
        /etc/init.d/carmodem-watchdog enable  >/dev/null 2>&1
        /etc/init.d/carmodem-watchdog restart >/dev/null 2>&1
    else
        /etc/init.d/carmodem-watchdog stop    >/dev/null 2>&1
        /etc/init.d/carmodem-watchdog disable >/dev/null 2>&1
    fi
}

# Валидация + запись UCI из WDS_* (rpcd заполняет их из JSON). Печатает {ok}.
cm_wd_set() {
    for _p in "enabled=${WDS_ENABLED:-}" "interval=${WDS_INTERVAL:-}" "l1_reconnect=${WDS_L1:-}" \
              "l2_reset=${WDS_L2:-}" "l3_reboot=${WDS_L3:-}" "cooldown_reset=${WDS_CDR:-}" "allow_reboot=${WDS_ALLOWREB:-}"; do
        _k=${_p%%=*}; _v=${_p#*=}
        case "$_v" in ''|*[!0-9]*) continue ;; esac
        uci -q set "carmodem.watchdog.$_k=$_v"
    done
    case "${WDS_PING:-}"    in ''|*[!0-9.\ ]*) : ;; *) uci -q set "carmodem.watchdog.ping_hosts=$WDS_PING" ;; esac
    case "${WDS_RECSVC:-}"  in *[!a-zA-Z0-9_-]*) : ;; *) uci -q set "carmodem.watchdog.recovery_service=$WDS_RECSVC" ;; esac
    case "${WDS_WANDEV:-}"  in *[!a-zA-Z0-9._-]*) : ;; *) uci -q set "carmodem.watchdog.wan_netdev=$WDS_WANDEV" ;; esac
    case "${WDS_IFACE:-}"   in ''|*[!a-zA-Z0-9._-]*) : ;; *) uci -q set "carmodem.watchdog.wan_iface=$WDS_IFACE" ;; esac
    # интервал: жёсткий клэмп на минимум 5 c (защита от busy-loop даже мимо UI)
    _iv=$(uci -q get carmodem.watchdog.interval 2>/dev/null)
    case "$_iv" in ''|*[!0-9]*) : ;; *) [ "$_iv" -lt 5 ] && uci -q set carmodem.watchdog.interval=5 ;; esac
    uci -q commit carmodem
    cm_wd_service_sync
    json_init; json_add_boolean ok 1; json_dump
}

cm_wd_clear() {
    echo 0 > "$WD_STRIKE_FILE" 2>/dev/null
    rm -f "$WD_EPISODE" 2>/dev/null
    json_init; json_add_boolean ok 1; json_dump
}

# Точка входа при ПРЯМОМ запуске (procd loop / тесты). При сорсинге в rpcd
# $1 = list|call -> ветка *) ничего не делает.
case "${1:-}" in
    loop)  cm_wd_loop ;;
    once)  cm_wd_cycle ;;
    status) cm_wd_status_json ;;
    sync)  cm_wd_service_sync ;;
    *) : ;;
esac
