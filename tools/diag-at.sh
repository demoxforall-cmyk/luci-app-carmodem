#!/bin/sh
# CarModem — диагностика AT-порта на устройстве (только базовый BusyBox).
# Запуск: sh /tmp/diag-at.sh

echo "=== busybox: какие applet'ы есть ==="
for a in stty microcom timeout socat; do
    command -v "$a" >/dev/null 2>&1 && echo "  есть: $a" || echo "  НЕТ:  $a"
done
echo "  read -t поддержка:"
if echo | (read -t 1 x 2>/dev/null); then echo "    read -t РАБОТАЕТ"; else echo "    read -t НЕ работает (rc=$?)"; fi

echo
echo "=== кто держит ttyUSB2/ttyUSB3 открытыми ==="
found=0
for fd in /proc/[0-9]*/fd/*; do
    L=$(readlink "$fd" 2>/dev/null)
    case "$L" in
        */ttyUSB2|*/ttyUSB3)
            p=$(echo "$fd" | sed 's#/proc/##; s#/fd/.*##')
            echo "  $L <- PID $p ($(cat /proc/$p/comm 2>/dev/null))"
            found=1 ;;
    esac
done
[ "$found" = 0 ] && echo "  никто не держит (порты свободны)"

# сырой обмен: фоновый cat в файл, пишем команду, ждём, убиваем cat
raw_at() {
    port=$1; out=$2
    : > "$out"
    cat "$port" > "$out" 2>/dev/null &
    cpid=$!
    printf 'AT+QENG="servingcell"\r' > "$port" 2>/dev/null
    sleep 2
    kill "$cpid" 2>/dev/null
    echo "  --- ответ $port (байт: $(wc -c < "$out")) ---"
    cat "$out"
    echo "  --- /$port ---"
}

echo
echo "=== СЫРОЙ AT (без stty) ==="
echo "ttyUSB2:"; raw_at /dev/ttyUSB2 /tmp/at2
echo "ttyUSB3:"; raw_at /dev/ttyUSB3 /tmp/at3

echo
echo "=== наш cm_at (после фикса flock) ==="
. /usr/share/carmodem/at.sh
echo "вывод:"; cm_at 'AT+QENG="servingcell"'; echo "(exit=$?)"
