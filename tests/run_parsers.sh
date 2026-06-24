#!/bin/sh
# CarModem — юнит-тесты парсеров AT-ответов на реальных фикстурах.
# Запуск:  sh tests/run_parsers.sh
# Зависимости: только POSIX sh + awk (как на устройстве). jq НЕ требуется.
#
# Каждый кейс: фикстура -> parse.awk -> сравнение с golden (tests/expected/).

set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
AWK_LIB="$ROOT/luci-app-carmodem/root/usr/share/carmodem/parse.awk"
FIX="$HERE/fixtures"
EXP="$HERE/expected"

pass=0
fail=0

# case <name> <fn> <fixture-basename>
case_run() {
    name=$1; fn=$2; fx=$3
    got=$(awk -v fn="$fn" -f "$AWK_LIB" < "$FIX/$fx.txt")
    want=$(cat "$EXP/$name.json")
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
        printf '  ok   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n' "$name"
        printf '    want: %s\n' "$want"
        printf '    got:  %s\n' "$got"
    fi
}

# assert <name> <fn> <fixture> grep substring (точечная проверка отдельных полей)
case_has() {
    name=$1; fn=$2; fx=$3; needle=$4
    got=$(awk -v fn="$fn" -f "$AWK_LIB" < "$FIX/$fx.txt")
    if printf '%s' "$got" | grep -qF "$needle"; then
        pass=$((pass + 1)); printf '  ok   %s\n' "$name"
    else
        fail=$((fail + 1)); printf '  FAIL %s (нет "%s")\n    got: %s\n' "$name" "$needle" "$got"
    fi
}

echo "CarModem parser tests"
echo "AWK lib: $AWK_LIB"
echo

echo "[golden]"
case_run servingcell servingcell servingcell_lte
case_run qrsrp       qrsrp       qrsrp
case_run qrsrq       qrsrq       qrsrq
case_run qsinr       qsinr       qsinr
case_run qnwinfo     qnwinfo     qnwinfo
case_run qcainfo     qcainfo     qcainfo_pcc
case_run qtemp       qtemp       qtemp

echo
echo "[поведенческие правила]"
# hex Cell ID -> eNB/сектор (раздел Приложение Г ТЗ)
case_has enb_decode    servingcell servingcell_lte '"enb":108753'
case_has sector_decode servingcell servingcell_lte '"sector":171'
case_has tac_decode    servingcell servingcell_lte '"tac":9060'
case_has bw_decode     servingcell servingcell_lte '"bw_mhz":"20"'
# -32768 -> null (нет тракта) для Rx2/Rx3
case_has ant_na_rx2    qrsrp       qrsrp '"rx2":null'
case_has ant_na_rx3    qsinr       qsinr '"rx3":null'

echo
echo "[синтетические по документации: 5G/CA (нет 5G-покрытия для захвата)]"
# NR5G-SA servingcell: ветвление по RAT, без раскладки NR по LTE-позициям
case_has nr_rat        servingcell synthetic/servingcell_nr '"rat":"NR5G-SA"'
case_has nr_band       servingcell synthetic/servingcell_nr '"band":"n78"'
case_has nr_enb_na     servingcell synthetic/servingcell_nr '"enb":null,"sector":null'
case_has nr_tac        servingcell synthetic/servingcell_nr '"tac":6699'
# Активная CA: PCC + SCC -> массив из двух компонент
case_has ca_pcc        qcainfo synthetic/qcainfo_ca '{"type":"PCC"'
case_has ca_scc        qcainfo synthetic/qcainfo_ca '{"type":"SCC","earfcn":1300'

echo
echo "[граничные: пустой/мусорный вход -> null, без падения]"
empty_sc=$(printf '' | awk -v fn=servingcell -f "$AWK_LIB")
if [ "$empty_sc" = "null" ]; then pass=$((pass+1)); echo "  ok   empty_servingcell_null"; else fail=$((fail+1)); echo "  FAIL empty_servingcell_null -> $empty_sc"; fi
empty_ca=$(printf 'OK\n' | awk -v fn=qcainfo -f "$AWK_LIB")
if [ "$empty_ca" = "[]" ]; then pass=$((pass+1)); echo "  ok   empty_qcainfo_array"; else fail=$((fail+1)); echo "  FAIL empty_qcainfo_array -> $empty_ca"; fi

echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
