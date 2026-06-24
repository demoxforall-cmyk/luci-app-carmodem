#!/bin/sh
# CarModem — интеграционные тесты бэкенда (без железа).
# Прогоняют сборку телеметрии и MM-слой через mock-транспорты,
# проверяя собранный JSON. Запуск: sh tests/run_backend.sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SHARE="$ROOT/luci-app-carmodem/root/usr/share/carmodem"

# подключаем библиотеки бэкенда с подменённым окружением
export CM_SHARE="$SHARE"
export CM_PARSE="$SHARE/parse.awk"
export CM_MM_AWK="$SHARE/mm.awk"
export CM_AT_TRANSPORT="$HERE/mocks/mock_at.sh"
export CM_MM_RAW="$HERE/mocks/mock_mmcli.sh"

. "$SHARE/at.sh"
. "$SHARE/telemetry.sh"
. "$SHARE/mm.sh"

pass=0; fail=0
check() { # <name> <actual> <needle>
    if printf '%s' "$2" | grep -qF "$3"; then
        pass=$((pass+1)); printf '  ok   %s\n' "$1"
    else
        fail=$((fail+1)); printf '  FAIL %s (нет "%s")\n    got: %s\n' "$1" "$3" "$2"
    fi
}

echo "CarModem backend integration tests"
echo

echo "[AT-телеметрия (cm_telemetry_at через mock-модем)]"
TEL=$(cm_telemetry_at)
check tel_servingcell "$TEL" '"servingcell":{"state":"NOCONN"'
check tel_enb         "$TEL" '"enb":108753'
check tel_antenna_na  "$TEL" '"rx2":null'
check tel_ca_array    "$TEL" '"ca":[{"type":"PCC"'
check tel_temp        "$TEL" '"temp":{"modem-lte-sub6-pa1":36'
check tel_nwinfo      "$TEL" '"nwinfo":{"act":"FDD LTE"'
# валидность: ровно один верхний объект и сбалансированные скобки
check tel_wrap_open   "$TEL" '{"servingcell"'

echo
echo "[MM-слой (mock mmcli -K)]"
SIG=$(cm_mm_signal)
check mm_signal_rsrp "$SIG" '"rsrp":-87'
check mm_signal_sinr "$SIG" '"sinr":24.6'
check mm_signal_nr_na "$SIG" '"nr_rsrp":null'
ST=$(cm_mm_status)
check mm_status_model "$ST" '"model":"RM520N-GL"'
check mm_status_plmn  "$ST" '"plmn":"25002"'
check mm_status_reg   "$ST" '"registration":"home"'
check mm_status_phone "$ST" '"phone":"+79362162407"'
check mm_status_imsi  "$ST" '"imsi":"250026017420148"'
check mm_status_simop "$ST" '"sim_operator":"MegaFon"'
check mm_status_ipv4  "$ST" '"ipv4":"100.66.132.153"'
check mm_status_rx    "$ST" '"bytes_rx":3485573'
check mm_status_dur   "$ST" '"duration":19049'

# живой трафик: при наличии sysfs-счётчиков интерфейса они перекрывают bearer.stats
mkdir -p "$HERE/.fakenet/wwan0/statistics"
echo 555000111 > "$HERE/.fakenet/wwan0/statistics/rx_bytes"
echo 222000333 > "$HERE/.fakenet/wwan0/statistics/tx_bytes"
LIVE=$(CM_NET_DIR="$HERE/.fakenet" cm_mm_status)
check live_traffic_rx "$LIVE" '"bytes_rx":555000111'
check live_traffic_tx "$LIVE" '"bytes_tx":222000333'
rm -rf "$HERE/.fakenet"
LOC=$(cm_mm_location)
check mm_loc_cid      "$LOC" '"cid_hex":"01A8D1AB"'
check mm_loc_tac      "$LOC" '"tac_hex":"002364"'
NB=$(cm_mm_neighbours)
check mm_nb_serving   "$NB" '"serving":"yes","type":"lte","pci":"102"'
check mm_nb_neighbor  "$NB" '"pci":"F3"'
check mm_nb_count2    "$NB" '"earfcn":1602'
check mm_nb_serving_ci "$NB" '"ci":"1A8D1AB","tac":"2364"'

echo
echo "[SMS-треды: вход (deliver=in) и исход (submit=out), с id/number/storage/dir]"
SMS=$(cm_mm_sms_list)
check sms_in  "$SMS" '{"id":0,"number":"+79162070281","timestamp":"2026-06-21T19:43:17+03","text":"Test 19:43","storage":"me","dir":"in"}'
check sms_out "$SMS" '"id":1,"number":"+79162070281","timestamp":null,"text":"test","storage":null,"dir":"out"'
# кириллица: mmcli -K отдаёт октал (\NNN) — должна раскодироваться в UTF-8
check sms_cyrillic "$SMS" '"text":"Люблб"'
# валидность JSON всего массива (главный баг: октал-кириллица ломала JSON -> ubus)
printf '%s' "$SMS" > "$ROOT/build/_sms.json"
if deno eval 'JSON.parse(Deno.readTextFileSync(Deno.args[0]))' "$ROOT/build/_sms.json" >/dev/null 2>&1; then
    pass=$((pass+1)); echo "  ok   sms_valid_json"
else
    fail=$((fail+1)); echo "  FAIL sms_valid_json — невалидный JSON: $SMS"
fi
rm -f "$ROOT/build/_sms.json"

echo
echo "[синтетический NR-сигнал (по документации; нет 5G-покрытия)]"
NRSIG=$(awk -v fn=signal -f "$SHARE/mm.awk" < "$HERE/fixtures/synthetic/signal_nr.kv")
check nr_signal_rsrp "$NRSIG" '"nr_rsrp":-85'
check nr_signal_sinr "$NRSIG" '"nr_sinr":25'
check nr_signal_lte  "$NRSIG" '"rsrp":-90'

echo
echo "[отказоустойчивость: пустой ответ модема -> пустые контейнеры]"
( CM_AT_TRANSPORT="$HERE/mocks/mock_empty.sh"
  EMPTY=$(cm_telemetry_at)
  printf '%s' "$EMPTY" | grep -qF '"servingcell":{}' && echo "  ok   empty_servingcell_obj" || { echo "  FAIL empty_servingcell_obj: $EMPTY"; exit 1; }
  printf '%s' "$EMPTY" | grep -qF '"ca":[]' && echo "  ok   empty_ca_array" || { echo "  FAIL empty_ca_array: $EMPTY"; exit 1; }
) && pass=$((pass+2)) || fail=$((fail+1))

echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
