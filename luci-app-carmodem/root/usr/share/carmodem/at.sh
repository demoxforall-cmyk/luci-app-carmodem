# CarModem — клиент AT-слоя (сериализованный доступ к ttyUSB)
# SPDX-License-Identifier: GPL-2.0
#
# Единственная точка вызова AT-команд для всех потребителей (телеметрия,
# AT-консоль, USSD). Сериализация обязательна (ТЗ NFR-2): через flock.
#
# Транспорт подменяем для тестов: если задан CM_AT_TRANSPORT, cm_at/cm_at_multi
# вызывают его (он получает команду как $1 и печатает сырой ответ модема).
#
# РЕАЛИЗАЦИЯ ПРОВЕРЕНА НА ЖЕЛЕЗЕ (RM520N-GL/ImmortalWRT, BusyBox):
#  - нет stty/timeout/microcom; порт уже в raw-режиме (его держит MM) — ок;
#  - `read -t` на этом tty НЕ работает (читает мусор) -> используем `cat`;
#  - читатель `cat port > tmp &`, пишем команду отдельным открытием, ждём
#    появления OK/ERROR в tmp (целые секунды), затем kill cat.

CM_AT_PORT="${CM_AT_PORT:-/dev/ttyUSB2}"
CM_AT_PORT2="${CM_AT_PORT2:-/dev/ttyUSB3}"
CM_AT_LOCK="${CM_AT_LOCK:-/var/lock/carmodem-at.lock}"
CM_AT_TIMEOUT="${CM_AT_TIMEOUT:-4}"

# Выбрать существующий AT-порт (echo путь, rc=0) или rc=1.
cm_at_resolve_port() {
    [ -c "$CM_AT_PORT" ]  && { echo "$CM_AT_PORT";  return 0; }
    [ -c "$CM_AT_PORT2" ] && { echo "$CM_AT_PORT2"; return 0; }
    return 1
}

# Одна AT-команда -> сырой ответ модема (многострочный).
cm_at() {
    if [ -n "${CM_AT_TRANSPORT:-}" ]; then
        "$CM_AT_TRANSPORT" "$1"
        return $?
    fi
    cm_at_exchange "$1"
}

# --- Реальный транспорт (на устройстве) ----------------------------------
# Одна AT-строка (можно с конкатенацией Quectel через `;`). cat-читатель +
# запись команды + ожидание OK/ERROR. Сериализация — flock -x (BusyBox без -w),
# время удержания ограничено CM_AT_TIMEOUT.
# ВАЖНО: модем НЕ принимает несколько отдельных команд очередью (теряет их) —
# для нескольких метрик используем конкатенацию `;` в одной строке.
cm_at_exchange() {
    port=$(cm_at_resolve_port) || { echo "ERROR: no AT port" >&2; return 2; }
    tmp="/tmp/carmodem-at.$$"
    (
        flock -x 9 || { echo "ERROR: at lock failed" >&2; exit 2; }
        : > "$tmp"
        cat "$port" > "$tmp" 2>/dev/null &
        cpid=$!
        printf '%s\r' "$1" > "$port"
        i=0
        while [ "$i" -lt "$CM_AT_TIMEOUT" ]; do
            grep -qE '^OK|ERROR' "$tmp" 2>/dev/null && break
            sleep 1
            i=$((i + 1))
        done
        kill "$cpid" 2>/dev/null
        wait "$cpid" 2>/dev/null
    ) 9>"$CM_AT_LOCK"
    tr -d '\r' < "$tmp" 2>/dev/null
    rm -f "$tmp"
}
