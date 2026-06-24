#!/bin/sh
# CarModem — диагностика AT v2: версия at.sh, read -t на tty, cat-паттерн, cm_at.
# Запуск: sh /tmp/diag-at2.sh
PORT=/dev/ttyUSB2

echo "=== 1. Версия at.sh на устройстве ==="
if grep -q 'фоновый читатель' /usr/share/carmodem/at.sh 2>/dev/null; then
    echo "  NEW (скопирован новый)"
else
    echo "  OLD — новый at.sh НЕ скопирован! (это и есть причина)"
fi

echo "=== 2. read -t именно на tty (а не pipe) ==="
# фоновый читатель read -t из порта в файл + пишем команду
: > /tmp/rt
(
    exec 7<"$PORT" || exit 0
    n=0
    while [ "$n" -lt 3 ]; do
        if IFS= read -r -t 1 ln <&7; then
            printf '%s\n' "$ln" >> /tmp/rt
            case "$ln" in *OK*) break ;; esac
        else
            n=$((n + 1))
        fi
    done
) &
rp=$!
printf 'AT+QENG="servingcell"\r' > "$PORT"
wait "$rp"
echo "  read -t получил байт: $(wc -c < /tmp/rt)"
tr -d '\r' < /tmp/rt

echo "=== 3. Проверенный cat-паттерн ==="
: > /tmp/ct
cat "$PORT" > /tmp/ct 2>/dev/null &
cp=$!
printf 'AT+QENG="servingcell"\r' > "$PORT"
sleep 2
kill "$cp" 2>/dev/null
echo "  cat получил байт: $(wc -c < /tmp/ct)"
tr -d '\r' < /tmp/ct

echo "=== 4. Наш cm_at ==="
. /usr/share/carmodem/at.sh
out=$(cm_at 'AT+QENG="servingcell"')
echo "  cm_at вернул байт: $(printf '%s' "$out" | wc -c)"
printf '%s\n' "$out"

rm -f /tmp/rt /tmp/ct
