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
has() { if printf '%s' "$2" | grep -qF "$3"; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); printf '  FAIL %s (нет "%s")\n    got: %s\n' "$1" "$3" "$2"; fi; }
hasnot() { if printf '%s' "$2" | grep -qF "$3"; then fail=$((fail+1)); printf '  FAIL %s (лишнее "%s")\n' "$1" "$3"; else pass=$((pass+1)); echo "  ok   $1"; fi; }

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
echo "[конвертация band-lock: UI-токены -> имена MM с разделителем '|']"
eq bands2mm      "$(cm_bands_to_mm 'B1,B3,n78')" 'eutran-1|eutran-3|ngran-78'
eq bands2mm_nr   "$(cm_bands_to_mm 'n78')"       'ngran-78'
eq bands2mm_any  "$(cm_bands_to_mm '')"          'any'

echo
echo "[RAT: строгий whitelist (раньше case *g пропускал любую строку на g)]"
out=$(cm_set_rat 'hackg'); rc rat_bad_rc $? 1; eq rat_bad_val "$out" '{"error":"bad_mode"}'

echo
echo "[SMS: номер строго +цифры, апостроф в тексте -> U+2019]"
cm_sanitize_phone '+79161234567'; rc phone_ok $? 0
cm_sanitize_phone "o'brien";      rc phone_quote_bad $? 1
cm_sanitize_phone '+7916 1234';   rc phone_space_bad $? 1
# перевод строки в номере: grep построчный пропустил бы по 1-й валидной строке
printf '+79\n0' | { cm_sanitize_phone "$(cat)"; }; rc phone_lf_bad $? 1
eq sms_text_clean "$(cm_sms_text_clean "don't panic")" "don’t panic"

echo
echo "[SIM-слот: валидация]"
out=$(cm_set_sim 5); rc sim_bad_rc $? 1; eq sim_bad_val "$out" '{"error":"bad_slot"}'

echo
echo "[TTL: генерация nftables-правил и валидация]"
R=$(cm_ttl_ruleset 65 64 wwan0)
has   ttl_out_rule "$R" 'oifname "wwan0" ip ttl set 64'
has   ttl_in_rule  "$R" 'iifname "wwan0" ip ttl set 65'
has   ttl_hoplimit "$R" 'ip6 hoplimit set 64'
R0=$(cm_ttl_ruleset 0 64 wwan0)
hasnot ttl_no_in_chain "$R0" 'iifname'
out=$(cm_set_ttl 64 999); rc ttl_range_bad $? 1
out=$(cm_set_ttl abc 64); rc ttl_nan_bad $? 1
# успешный путь: файл пишется (fw4 на dev-машине нет — reload пропускается)
export CM_TTL_NFT="${TMPDIR:-/tmp}/cm_test_ttl.nft"
rm -f "$CM_TTL_NFT"
out=$(cm_set_ttl 0 64); rc ttl_set_rc $? 0; has ttl_set_ok "$out" '"ok":true'
if grep -q 'ip ttl set 64' "$CM_TTL_NFT" 2>/dev/null; then pass=$((pass+1)); echo "  ok   ttl_file_written"; else fail=$((fail+1)); echo "  FAIL ttl_file_written"; fi
out=$(cm_set_ttl 0 0); has ttl_off_ok "$out" '"ok":true'
if [ ! -f "$CM_TTL_NFT" ]; then pass=$((pass+1)); echo "  ok   ttl_file_removed"; else fail=$((fail+1)); echo "  FAIL ttl_file_removed"; fi

echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
