# CarModem — слой ModemManager (mmcli)
# SPDX-License-Identifier: GPL-2.0
#
# Источник большинства полей (ТЗ 3.2, MM-first): идентификация, оператор,
# регистрация, сигнал, соседние соты, IP/трафик. AT не используется.
#
# Используем стабильный машинный формат `mmcli -K` (key-value) и парсим его
# через mm.awk. Транспорт подменяем для тестов: CM_MM_RAW переопределяет
# вызов mmcli (получает аргументы, печатает -K вывод).
#
# Ключи и форматы сверены с реальными захватами RM520N-GL (ImmortalWRT):
# cell-info приходит композитной строкой в modem.generic.cell-info.value[N],
# PCI ("physical ci") — в hex; 5G-поля при LTE-регистрации = -32768 -> null.

CM_SHARE="${CM_SHARE:-/usr/share/carmodem}"
CM_MM_AWK="${CM_MM_AWK:-$CM_SHARE/mm.awk}"
CM_MM_INDEX="${CM_MM_INDEX:-0}"

# Сырой вызов mmcli с -K. Подменяется через CM_MM_RAW для тестов.
cm_mm_raw() {
    if [ -n "${CM_MM_RAW:-}" ]; then
        "$CM_MM_RAW" "$@"
        return $?
    fi
    mmcli -K "$@" 2>/dev/null
}

_cm_mm_parse() { awk -v fn="$1" -f "$CM_MM_AWK"; }

# Актуальный индекс модема. MM нумерует объекты монотонно: после --reset,
# смены USB-режима или слота SIM модем получает НОВЫЙ индекс (0 -> 1 -> ...),
# и захардкоженный 0 бьёт в несуществующий объект. Вызывается один раз на
# rpcd-процесс (rpcd/carmodem, ветка call) — далее все функции берут
# разрезолвленный CM_MM_INDEX. Fallback — прежний дефолт.
cm_mm_resolve_idx() {
    idx=$(cm_mm_raw -L 2>/dev/null | sed -n 's#.*/Modem/\([0-9][0-9]*\).*#\1#p' | head -1)
    printf '%s' "${idx:-${CM_MM_INDEX:-0}}"
}

cm_mm_status() {
    modem=$(cm_mm_raw -m "$CM_MM_INDEX")
    [ -n "$modem" ] || { echo '{}'; return; }
    # SIM (IMSI/ICCID/имя оператора)
    sim=$(cm_mm_raw -i "$CM_MM_INDEX" 2>/dev/null)
    # активный bearer: индекс берём из modem.generic.bearers.value[1]
    bidx=$(printf '%s\n' "$modem" | sed -n 's#.*bearers\.value\[1\].*Bearer/\([0-9]\{1,\}\).*#\1#p' | head -1)
    bearer=""
    [ -n "$bidx" ] && bearer=$(cm_mm_raw -b "$bidx" 2>/dev/null)
    # ЖИВОЙ трафик: счётчики bearer.stats у MM обновляются не в реальном времени,
    # поэтому берём счётчики интерфейса из ядра (/sys/class/net/<iface>/statistics).
    # Дописываем строки ПОСЛЕ bearer — awk перезапишет bytes_rx/tx последним значением.
    iface=$(printf '%s\n' "$bearer" | sed -n 's/.*bearer\.status\.interface *: *//p' | head -1)
    netdir="${CM_NET_DIR:-/sys/class/net}"
    live=""
    if [ -n "$iface" ] && [ -d "$netdir/$iface/statistics" ]; then
        rx=$(cat "$netdir/$iface/statistics/rx_bytes" 2>/dev/null)
        tx=$(cat "$netdir/$iface/statistics/tx_bytes" 2>/dev/null)
        [ -n "$rx" ] && live="${live}bearer.stats.bytes-rx : ${rx}
"
        [ -n "$tx" ] && live="${live}bearer.stats.bytes-tx : ${tx}
"
    fi
    # один проход awk по объединённому выводу (namespace'ы modem./sim./bearer. не пересекаются)
    printf '%s\n%s\n%s\n%s' "$modem" "$sim" "$bearer" "$live" | _cm_mm_parse status
}

# Лёгкий опрос состояния модема (живой бейдж Connection, ~1 c): одно обращение
# mmcli -m -> state + access-technology, без bearer/SIM/трафика (быстро).
cm_mm_conn() {
    out=$(cm_mm_raw -m "$CM_MM_INDEX" 2>/dev/null)
    st=$(printf '%s\n' "$out" | sed -n 's/.*modem\.generic\.state *: *//p' | head -1)
    tech=$(printf '%s\n' "$out" | sed -n 's/.*modem\.generic\.access-technologies\.value\[1\] *: *//p' | head -1)
    [ -n "$st" ] || st="--"
    printf '{"state":"%s","access_tech":"%s"}\n' "$st" "$tech"
}

cm_mm_signal() {
    # требуется заранее: mmcli --signal-setup=<rate> (включает init.d).
    # Самолечение: после reset/переиндексации модема setup слетает (init.d
    # делает его один раз при старте) -> refresh.rate=0 и пустые метрики.
    # Включаем заново и перечитываем.
    out=$(cm_mm_raw -m "$CM_MM_INDEX" --signal-get)
    if ! printf '%s' "$out" | grep -q 'signal\.refresh\.rate *: *[1-9]'; then
        cm_mm_raw -m "$CM_MM_INDEX" --signal-setup=5 >/dev/null 2>&1
        out=$(cm_mm_raw -m "$CM_MM_INDEX" --signal-get)
    fi
    [ -n "$out" ] || { echo '{}'; return; }
    printf '%s\n' "$out" | _cm_mm_parse signal
}

cm_mm_neighbours() {
    out=$(cm_mm_raw -m "$CM_MM_INDEX" --get-cell-info)
    [ -n "$out" ] || { echo '[]'; return; }
    printf '%s\n' "$out" | _cm_mm_parse neighbours
}

# Cell ID / LAC / TAC через MM location-3gpp (ТЗ FR-13, hex).
# Источник по ТЗ и фоллбэк, когда AT-порт занят телеметрией.
cm_mm_location() {
    out=$(cm_mm_raw -m "$CM_MM_INDEX" --location-get)
    [ -n "$out" ] || { echo '{}'; return; }
    printf '%s\n' "$out" | _cm_mm_parse location
}

# Список входящих SMS. MM сам декодирует UCS2/собирает длинные (ТЗ FR-31).
# Финализировать парсинг на реальном `mmcli --messaging-list-sms` (нужны
# захваты с устройства — см. STATUS.md). Пока — безопасный пустой список.
# JSON-экранирование содержимого строки (БЕЗ обрамляющих кавычек): \, ", таб, CR;
# многострочный ввод -> \n. ВАЖНО: для удвоения '\' в awk-gsub нужна замена из
# 4 символов-бэкслэшей (в литерале — 8); меньше = no-op (awk съедает половину).
# LC_ALL=C — чтобы байты UTF-8 (кириллица) проходили как есть, без локали.
_cm_json_str() {
    LC_ALL=C awk '
        BEGIN { ORS = ""; first = 1 }
        { line = $0
          gsub(/\\/, "\\\\\\\\", line)
          gsub(/"/,  "\\\"", line)
          gsub(/\t/, "\\t", line)
          gsub(/\r/, "\\r", line)
          if (!first) printf "\\n"; first = 0
          printf "%s", line }
    '
}

# Список SMS как массив тредов. Парсим в shell (а не awk), потому что текст
# кириллицы mmcli -K отдаёт ОКТАЛ-эскейпами (\NNN) — их надо раскодировать в
# UTF-8 (иначе \3.. = невалидный JSON-эскейп -> ubus «Invalid argument»).
cm_mm_sms_list() {
    ids=$(cm_mm_raw -m "$CM_MM_INDEX" --messaging-list-sms | sed -n 's#.*/SMS/\([0-9][0-9]*\).*#\1#p')
    out=""
    for s in $ids; do
        blk=$(cm_mm_raw -s "$s")
        [ -n "$blk" ] || continue
        pdu=$(printf '%s\n' "$blk" | sed -n 's/^sms\.properties\.pdu-type *: *//p' | head -1)
        case "$pdu" in
            deliver) dir=in ;;
            *) continue ;;   # submit/status-report: исходящие берём из локального реестра
        esac
        num=$(printf '%s\n' "$blk" | sed -n 's/^sms\.content\.number *: *//p' | head -1)
        ts=$(printf  '%s\n' "$blk" | sed -n 's/^sms\.properties\.timestamp *: *//p' | head -1)
        sto=$(printf '%s\n' "$blk" | sed -n 's/^sms\.properties\.storage *: *//p' | head -1)
        # текст: \NNN -> \0NNN, затем printf %b декодирует октал в байты (UTF-8)
        rawtxt=$(printf '%s\n' "$blk" | sed -n 's/^sms\.content\.text *: *//p')
        txt=$(printf '%s' "$rawtxt" | sed 's/\\\([0-7][0-7][0-7]\)/\\0\1/g')
        txt=$(printf '%b' "$txt")
        jnum="\"$(printf '%s' "$num" | _cm_json_str)\""
        jtxt="\"$(printf '%s' "$txt" | _cm_json_str)\""
        case "$ts"  in ''|'--') jts=null  ;; *) jts="\"$(printf '%s' "$ts"  | _cm_json_str)\"" ;; esac
        case "$sto" in ''|'--') jsto=null ;; *) jsto="\"$(printf '%s' "$sto" | _cm_json_str)\"" ;; esac
        obj=$(printf '{"id":%s,"number":%s,"timestamp":%s,"text":%s,"storage":%s,"dir":"%s"}' \
            "$s" "$jnum" "$jts" "$jtxt" "$jsto" "$dir")
        [ -z "$out" ] && out="$obj" || out="$out,$obj"
    done
    # Исходящие — из собственного реестра (модем не хранит копию надёжно). Каждая
    # строка файла = готовый JSON-объект {"id":"sNN",...,"dir":"out"}. Дублей нет:
    # submit-копии модема выше пропускаются, id реестра — в своём пространстве.
    store="${CM_SMS_SENT:-/etc/carmodem/sent_sms.jsonl}"
    if [ -f "$store" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in '{'*'}') ;; *) continue ;; esac
            [ -z "$out" ] && out="$line" || out="$out,$line"
        done < "$store"
    fi
    printf '[%s]\n' "$out"
}

# Дешёвый сигнал изменений SMS для частого опроса (живое обновление треда).
# ОДИН вызов mmcli (только список id, без чтения тел `mmcli -s`):
#   n   — число входящих id, max — макс. числовой id (ловит приход/удаление),
#   out — число строк в реестре отправленных (ловит свои отправки/удаления).
# Меняется ключ n:max:out -> фронтенд делает полную (дорогую) cm_mm_sms_list.
cm_mm_sms_sig() {
    ids=$(cm_mm_raw -m "$CM_MM_INDEX" --messaging-list-sms | sed -n 's#.*/SMS/\([0-9][0-9]*\).*#\1#p')
    n=0; mx=0
    for s in $ids; do
        n=$((n+1))
        [ "$s" -gt "$mx" ] 2>/dev/null && mx="$s"
    done
    store="${CM_SMS_SENT:-/etc/carmodem/sent_sms.jsonl}"
    out=0
    [ -f "$store" ] && out=$(grep -c '^{' "$store" 2>/dev/null)
    printf '{"n":%d,"max":%d,"out":%d}\n' "$n" "$mx" "$out"
}

# Удаление SMS по списку id (через запятую/пробел). Только цифры (NFR-6).
cm_mm_sms_delete() {
    store="${CM_SMS_SENT:-/etc/carmodem/sent_sms.jsonl}"
    ok=0; fail=0
    for id in $(printf '%s' "$1" | tr ',' ' '); do
        # исходящее из реестра: id вида sNN -> удаляем строку из файла
        case "$id" in
            s[0-9]*)
                if [ -f "$store" ] && grep -qF "\"id\":\"$id\"," "$store"; then
                    grep -vF "\"id\":\"$id\"," "$store" > "$store.tmp" 2>/dev/null && mv "$store.tmp" "$store"
                    ok=$((ok+1))
                else fail=$((fail+1)); fi
                continue ;;
        esac
        case "$id" in ''|*[!0-9]*) continue ;; esac
        if mmcli -m "$CM_MM_INDEX" --messaging-delete-sms="$id" >/dev/null 2>&1; then
            ok=$((ok+1)); else fail=$((fail+1)); fi
    done
    printf '{"deleted":%d,"failed":%d}\n' "$ok" "$fail"
}
