#!/bin/sh
# CarModem — тесты control-слоя: парсеры скана/спидтеста + санитизация ввода.
# Запуск: sh tests/run_control.sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
SHARE="$ROOT/luci-app-carmodem/root/usr/share/carmodem"
export CM_SHARE="$SHARE"
export CM_CTRL_AWK="$SHARE/control.awk"
. "$SHARE/control.sh"

pass=0; fail=0
eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); printf '  FAIL %s\n    want: %s\n    got:  %s\n' "$1" "$3" "$2"; fi; }
rc() { if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (rc=$2, want $3)"; fi; }

echo "CarModem control tests"
echo
echo "[парсеры]"
SCAN=$(awk -v fn=scan -f "$CM_CTRL_AWK" < "$HERE/fixtures/mm/scan.kv")
eq scan_golden "$SCAN" '[{"plmn":"25001","name":"MTS RUS","tech":"lte","status":"available"},{"plmn":"25002","name":"MegaFon","tech":"lte","status":"current"},{"plmn":"25099","name":"Beeline","tech":"umts","status":"forbidden"}]'
# AT+CPMS? -> хранилище SMS (CR из реального ответа должен срезаться)
CPMS=$(printf '+CPMS: "ME",2,255,"ME",2,255,"ME",2,255\r\nOK\r\n' | awk -v fn=cpms -f "$CM_CTRL_AWK")
eq cpms_golden "$CPMS" '{"storage":"me","used":2,"total":255}'

echo
echo "[санитизация AT (защита от инъекции, NFR-6)]"
out=$(cm_sanitize_at 'AT+QRSRP'); rc at_clean_rc $? 0; eq at_clean_val "$out" 'AT+QRSRP'
# попытка вставить вторую команду через CRLF -> код 1 и склейка без перевода строки
out=$(printf 'AT+X\r\nAT+CFUN=0' | { cm_sanitize_at "$(cat)"; }); injrc=$?
rc at_inject_rc "$injrc" 1
eq at_inject_stripped "$out" 'AT+XAT+CFUN=0'

echo
echo "[санитизация USSD]"
out=$(cm_sanitize_ussd '*100#'); rc ussd_ok_rc $? 0; eq ussd_ok_val "$out" '*100#'
cm_sanitize_ussd '*100#; rm -rf /' >/dev/null 2>&1; rc ussd_bad_rc $? 1

echo
echo "[валидация band-списка]"
cm_validate_bands 'B1,B7,n78'; rc bands_ok $? 0
cm_validate_bands 'B1,XSS,n78'; rc bands_bad $? 1
cm_validate_bands ''; rc bands_empty_ok $? 0

echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
