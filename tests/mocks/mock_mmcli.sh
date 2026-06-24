#!/bin/sh
# Mock mmcli-транспорт для тестов: аргументы -> -K фикстура.
# Задаётся как CM_MM_RAW. Имитирует `mmcli -K ...`.
FIX="${MOCK_MM_FIX:-$(CDPATH= cd -- "$(dirname -- "$0")/../fixtures/mm" && pwd)}"
# Выбор фикстуры по наличию подкоманды в аргументах
prev=""
for a in "$@"; do
  case "$a" in
    --signal-get)         cat "$FIX/signal.kv";   exit 0 ;;
    --get-cell-info)      cat "$FIX/cellinfo.kv"; exit 0 ;;
    --location-get)       cat "$FIX/location.kv"; exit 0 ;;
    --messaging-list-sms) cat "$FIX/sms_list.kv"; exit 0 ;;
    -i)                   cat "$FIX/sim.kv";      exit 0 ;;
    -b)                   cat "$FIX/bearer.kv";   exit 0 ;;
  esac
  # `-s N` -> деталь конкретного SMS (sms<N>.kv)
  case "$prev" in
    -s) cat "$FIX/sms$a.kv" 2>/dev/null; exit 0 ;;
  esac
  prev="$a"
done
# по умолчанию — статус модема (mmcli -m 0)
cat "$FIX/status.kv"
