#!/bin/sh
# CarModem — сборщик фикстур с РЕАЛЬНОГО устройства (RM520N-GL на ImmortalWRT).
# Запустить на роутере: sh capture_fixtures.sh [<mmcli-index>] [<AT-порт>]
# По умолчанию: индекс 0, порт /dev/ttyUSB2.
#
# Собирает всё, что нужно для финализации MM-парсеров и SMS-листинга
# (см. docs/STATUS.md), в /tmp/carmodem-fixtures и пакует в tar.gz.
# Готовый архив пришлите — я разложу в tests/fixtures/ и допилю парсеры.
#
# ВАЖНО: снимите дважды — при LTE-регистрации И при 5G-регистрации
# (и, если возможно, при активной carrier aggregation), это разблокирует
# NR/CA тест-кейсы. Маскируйте IMEI/IMSI/номер, если не хотите их светить.

set -u
M="${1:-0}"
PORT="${2:-/dev/ttyUSB2}"
OUT=/tmp/carmodem-fixtures
mkdir -p "$OUT/mm" "$OUT/at"

echo "[*] ModemManager (-K, машинный формат)…"
mmcli -K -m "$M"                       > "$OUT/mm/status.kv"      2>&1
mmcli -K -m "$M" --signal-get          > "$OUT/mm/signal.kv"     2>&1
mmcli -K -m "$M" --get-cell-info       > "$OUT/mm/cellinfo.kv"   2>&1
mmcli -K -m "$M" --location-get        > "$OUT/mm/location.kv"   2>&1
mmcli -K -m "$M" --messaging-list-sms  > "$OUT/mm/sms_list.kv"   2>&1
# скан операторов кратко влияет на связь — снимать по желанию:
# mmcli -K -m "$M" --3gpp-scan         > "$OUT/mm/scan.kv"       2>&1
echo "    (scan закомментирован — раскомментируйте, если можно прервать связь)"

echo "[*] librespeed-cli --json (по желанию, нагрузит канал)…"
command -v librespeed-cli >/dev/null 2>&1 \
  && librespeed-cli --json > "$OUT/speedtest.json" 2>&1 \
  || echo "    librespeed-cli не установлен — пропуск"

# --- AT-захваты через порт ---------------------------------------------
# Простой синхронный AT: пишем команду, читаем ответ ~1.5 с.
at() {
    cmd=$1; name=$2
    [ -c "$PORT" ] || { echo "    нет порта $PORT — пропуск AT"; return; }
    stty -F "$PORT" 115200 raw -echo 2>/dev/null
    ( cat "$PORT" > "$OUT/at/$name.txt" & catpid=$!
      printf '%s\r\n' "$cmd" > "$PORT"
      sleep 2
      kill "$catpid" 2>/dev/null ) 2>/dev/null
    echo "    $name <- $cmd"
}

echo "[*] AT-команды через $PORT…"
at 'AT+QENG="servingcell"' servingcell
at 'AT+QRSRP'   qrsrp
at 'AT+QRSRQ'   qrsrq
at 'AT+QSINR'   qsinr
at 'AT+QCAINFO' qcainfo
at 'AT+QNWINFO' qnwinfo
at 'AT+QTEMP'   qtemp
at 'AT+QNWPREFCFG="nr5g_band"' qnwprefcfg_nr

echo
echo "[*] Упаковка…"
( cd /tmp && tar -czf carmodem-fixtures.tar.gz carmodem-fixtures )
echo "[OK] Готово: /tmp/carmodem-fixtures.tar.gz"
echo "     Снимите отдельно при LTE и при 5G-регистрации (переименуйте архивы),"
echo "     затем пришлите оба."
