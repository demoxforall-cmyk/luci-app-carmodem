#!/bin/sh
# Mock AT-транспорт для тестов: команда -> фикстура(ы) (+ OK).
# Понимает конкатенацию Quectel через `;` (как реальный модем): на одну
# AT-строку из нескольких подкоманд отдаёт все соответствующие ответы.
FIX="${MOCK_FIX:-$(CDPATH= cd -- "$(dirname -- "$0")/../fixtures" && pwd)}"

emit_one() {
    case "$1" in
        *QENG*servingcell*) cat "$FIX/servingcell_lte.txt" ;;
        *QRSRP*)            cat "$FIX/qrsrp.txt" ;;
        *QRSRQ*)            cat "$FIX/qrsrq.txt" ;;
        *QSINR*)            cat "$FIX/qsinr.txt" ;;
        *QCAINFO*)          cat "$FIX/qcainfo_pcc.txt" ;;
        *QNWINFO*)          cat "$FIX/qnwinfo.txt" ;;
        *QTEMP*)            cat "$FIX/qtemp.txt" ;;
    esac
}

# разбить строку по ';' и отдать ответ на каждую подкоманду, затем один OK
old=$IFS
IFS=';'
for part in $1; do emit_one "$part"; done
IFS=$old
echo "OK"
