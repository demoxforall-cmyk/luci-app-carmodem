#!/bin/sh
# CarModem — прогон всех юнит/интеграционных тестов (без железа).
# Запуск: sh tests/run_all.sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
rc=0
echo "============================================"
echo " CarModem test suite"
echo "============================================"
echo
sh "$HERE/run_parsers.sh" || rc=1
echo
sh "$HERE/run_backend.sh" || rc=1
echo
sh "$HERE/run_control.sh" || rc=1
echo
sh "$HERE/run_watchdog.sh" || rc=1
echo
sh "$HERE/check_package.sh" || rc=1
echo
echo "============================================"
if [ "$rc" -eq 0 ]; then echo " ВСЕ ТЕСТЫ ПРОЙДЕНЫ"; else echo " ЕСТЬ ПАДЕНИЯ"; fi
echo "============================================"
exit "$rc"
