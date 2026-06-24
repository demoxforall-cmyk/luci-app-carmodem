# CarModem — управляющие и сервисные операции
# SPDX-License-Identifier: GPL-2.0
#
# Управление band/RAT/SIM/TTL/дозвоном — через ModemManager/netifd (ТЗ 4).
# Скан операторов и спидтест — с парсерами (control.awk). Везде —
# санитизация пользовательского ввода против инъекций (NFR-6).

CM_SHARE="${CM_SHARE:-/usr/share/carmodem}"
CM_CTRL_AWK="${CM_CTRL_AWK:-$CM_SHARE/control.awk}"
CM_MM_INDEX="${CM_MM_INDEX:-0}"
CM_WWAN_IFACE="${CM_WWAN_IFACE:-wwan}"

# --- Санитизация ---------------------------------------------------------
# AT-команда: запретить CR/LF и управляющие символы (защита от инъекции
# второй команды в один write). Возврат: очищенная строка на stdout,
# код 1 если ввод содержал запрещённые символы.
cm_sanitize_at() {
    # Стрип всех управляющих (C0 0x00-0x1F + DEL 0x7F) через tr. ВАЖНО: именно tr,
    # а НЕ awk-класс — busybox awk не понимает октал-диапазоны/[]-классы в regex
    # (gawk/mawk терпят, поэтому баг ловился лишь на роутере). tr ведёт себя
    # одинаково везде. Возврат 1, если что-то срезано (CR/LF -> попытка инъекции
    # второй команды) или ввод был многострочным.
    clean=$(printf '%s' "$1" | tr -d '\000-\037\177')
    printf '%s' "$clean"
    [ "$clean" = "$1" ]
}

# USSD-код: разрешены цифры, * # +. Иначе пусто+код 1.
cm_sanitize_ussd() {
    printf '%s' "$1" | awk '
        { if ($0 ~ /[^0-9*#+]/) { exit 1 } printf "%s", $0 }'
}

# Band-список: токены вида B1, n78, разделённые запятой.
cm_validate_bands() {
    printf '%s' "$1" | awk '
        BEGIN { RS=","; ok=1 }
        { t=$0; gsub(/^[ \t]+|[ \t]+$/, "", t)
          if (t != "" && t !~ /^(B|n)[0-9]+$/) ok=0 }
        END { exit (ok ? 0 : 1) }'
}

# --- Действия (на устройстве; не тестируются на dev-машине) --------------
cm_set_band() {
    cm_validate_bands "$1" || { echo '{"error":"bad_bands"}'; return 1; }
    # MM band-id маппинг выполняется отдельным конфигом; здесь — точка вызова
    mmcli -m "$CM_MM_INDEX" --set-current-bands="$1" >/dev/null 2>&1 \
        && echo '{"ok":true}' || echo '{"error":"set_band_failed"}'
}

cm_set_rat() {
    mode=$1
    case "$mode" in
        2g|3g|4g|5g|auto|*g) : ;;
        *) echo '{"error":"bad_mode"}'; return 1 ;;
    esac
    mmcli -m "$CM_MM_INDEX" --set-allowed-modes="$mode" >/dev/null 2>&1 \
        && echo '{"ok":true}' || echo '{"error":"set_rat_failed"}'
}

cm_dial() {
    case "$1" in
        true|1|up)   ifup "$CM_WWAN_IFACE" ;;
        *)           ifdown "$CM_WWAN_IFACE" ;;
    esac >/dev/null 2>&1
    echo '{"ok":true}'
}

# Журнал дозвона: хвост системного лога, отфильтрованный по соединению
# (ModemManager / netifd / wwan / bearer). Фронтенд опрашивает в реальном времени.
# jshn (json_add_string) корректно экранирует многострочный текст -> валидный JSON.
cm_conn_log() {
    log=$(logread 2>/dev/null | grep -iE 'modemmanager|netifd|wwan|bearer' | tail -n 120)
    json_init
    json_add_string log "$log"
    json_dump
}

cm_reset_modem() {
    mmcli -m "$CM_MM_INDEX" --reset >/dev/null 2>&1 \
        && echo '{"ok":true}' || echo '{"error":"reset_failed"}'
}

# --- Скан операторов (FR-32a): АСИНХРОННО ---------------------------------
# mmcli --3gpp-scan длится 1–2 мин и превышает таймаут uhttpd/ubus при
# синхронном вызове -> запускаем в фоне, фронтенд опрашивает ЭТОТ ЖЕ метод:
#   блокировка есть         -> {"scanning":true}
#   результат готов         -> {"networks":[...]} (отдаём и удаляем — следующий
#                              клик запускает скан заново)
#   ни того, ни другого     -> старт фона + {"scanning":true}
CM_SCAN_RES="${CM_SCAN_RES:-/tmp/cm_scan.json}"
CM_SCAN_LOCK="${CM_SCAN_LOCK:-/tmp/cm_scan.lock}"
cm_scan_operators() {
    if [ -f "$CM_SCAN_LOCK" ]; then
        # страховка от зависшей блокировки (процесс убит / модем завис)
        if [ -n "$(find "$CM_SCAN_LOCK" -mmin +5 2>/dev/null)" ]; then
            rm -f "$CM_SCAN_LOCK"
        else
            echo '{"scanning":true}'; return
        fi
    fi
    if [ -f "$CM_SCAN_RES" ]; then
        nets=$(cat "$CM_SCAN_RES" 2>/dev/null); rm -f "$CM_SCAN_RES"
        [ -n "$nets" ] || nets='[]'
        printf '{"networks":%s}\n' "$nets"; return
    fi
    : > "$CM_SCAN_LOCK"
    (   trap '' HUP                       # пережить выход родителя (rpcd)
        out=$(mmcli -K -m "$CM_MM_INDEX" --3gpp-scan --timeout=300 2>/dev/null)
        printf '%s\n' "$out" | awk -v fn=scan -f "$CM_CTRL_AWK" > "$CM_SCAN_RES" 2>/dev/null
        rm -f "$CM_SCAN_LOCK"
    ) >/dev/null 2>&1 &
    echo '{"scanning":true}'
}

# --- Текущие активные диапазоны (для отметки чекбоксов band-lock) ----------
# MM: modem.generic.current-bands.value[N] = eutran-N (LTE) / ngran-N (NR).
# В auto-режиме модем перечисляет все используемые диапазоны -> отметятся все.
cm_get_bands() {
    lte=""; nr=""
    for b in $(mmcli -K -m "$CM_MM_INDEX" 2>/dev/null | sed -n 's/.*current-bands[^:]*: *//p'); do
        case "$b" in
            eutran-*) lte="$lte${lte:+,}B${b#eutran-}" ;;
            ngran-*)  nr="$nr${nr:+,}n${b#ngran-}" ;;
        esac
    done
    printf '{"lte":"%s","nr":"%s"}\n' "$lte" "$nr"
}

# --- Хранилище SMS: sm (SIM) / me (память модема), 3GPP TS 27.005 ---------
# GET: текущее приёмное хранилище + счётчики через AT+CPMS? (cm_at — прямой
# AT-канал, определён в at.sh, подключается rpcd).
cm_sms_storage_get() {
    cm_at 'AT+CPMS?' 2>/dev/null | awk -v fn=cpms -f "$CM_CTRL_AWK"
}
# SET: предпочтительно MM-нативно через D-Bus Messaging.SetDefaultStorage
# (sm=MM_SMS_STORAGE_SM=2, me=ME=3) — не конфликтует с MM. Если в системе нет
# gdbus/dbus-send — fallback на прямой AT+CPMS. Оба пути меняют CPMS модема,
# поэтому GET (AT+CPMS?) остаётся консистентным.
cm_sms_storage_set() {
    case "$1" in
        sm|SM) m=SM; code=2 ;;
        me|ME) m=ME; code=3 ;;
        mt|MT) m=MT; code=4 ;;   # combined: модем (ME) → при заполнении SIM
        *) echo '{"error":"bad_storage"}'; return 1 ;;
    esac
    obj="/org/freedesktop/ModemManager1/Modem/${CM_MM_INDEX}"
    meth="org.freedesktop.ModemManager1.Modem.Messaging.SetDefaultStorage"
    rc=1
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --system --dest org.freedesktop.ModemManager1 \
            --object-path "$obj" --method "$meth" "$code" >/dev/null 2>&1 && rc=0
    elif command -v dbus-send >/dev/null 2>&1; then
        dbus-send --system --print-reply --dest=org.freedesktop.ModemManager1 \
            "$obj" "$meth" uint32:"$code" >/dev/null 2>&1 && rc=0
    fi
    if [ "$rc" -ne 0 ]; then                # fallback: прямой AT+CPMS
        out=$(cm_at "AT+CPMS=\"$m\",\"$m\",\"$m\"" 2>&1)
        case "$out" in *OK*) rc=0 ;; esac
    fi
    [ "$rc" -eq 0 ] && cm_sms_storage_get || echo '{"error":"set_failed"}'
}

# Текущее хранилище + счётчики SM и ME — ОДНИМ атомарным вызовом под flock.
# Раньше это были два метода (get_sms_storage + fill), которые шли параллельно
# (Promise.all) и оба лезли в AT+CPMS -> гонка: read-хранилище ловилось в момент
# временного AT+CPMS="SM" и переключатель показывал SIM. Теперь весь обмен
# сериализован: читаем текущее (orig), опрашиваем SM/ME, ВОЗВРАЩАЕМ orig.
# AT+CPMS="X" меняет только mem1 (read), mem3 (приём) не трогаем.
CM_CPMS_LOCK="${CM_CPMS_LOCK:-/tmp/cm_cpms.lock}"
cm_sms_storage_fill() {
    {
        flock 9 2>/dev/null
        orig=$(cm_at 'AT+CPMS?' 2>/dev/null | sed -n 's/.*+CPMS: *"\([A-Za-z]*\)".*/\1/p' | head -1)
        smr=$(cm_at 'AT+CPMS="SM"' 2>/dev/null)
        mer=$(cm_at 'AT+CPMS="ME"' 2>/dev/null)
        [ -n "$orig" ] && cm_at "AT+CPMS=\"$orig\"" >/dev/null 2>&1
    } 9>"$CM_CPMS_LOCK"
    smu=$(printf '%s' "$smr" | sed -n 's/.*+CPMS: *\([0-9][0-9]*\),\([0-9][0-9]*\).*/\1/p' | head -1)
    smt=$(printf '%s' "$smr" | sed -n 's/.*+CPMS: *\([0-9][0-9]*\),\([0-9][0-9]*\).*/\2/p' | head -1)
    meu=$(printf '%s' "$mer" | sed -n 's/.*+CPMS: *\([0-9][0-9]*\),\([0-9][0-9]*\).*/\1/p' | head -1)
    met=$(printf '%s' "$mer" | sed -n 's/.*+CPMS: *\([0-9][0-9]*\),\([0-9][0-9]*\).*/\2/p' | head -1)
    cur=$(printf '%s' "$orig" | tr 'A-Z' 'a-z')
    case "$cur" in sm|me|mt) sj="\"$cur\"" ;; *) sj=null ;; esac
    printf '{"storage":%s,"sim":{"used":%s,"total":%s},"modem":{"used":%s,"total":%s}}\n' \
        "$sj" "${smu:-0}" "${smt:-0}" "${meu:-0}" "${met:-0}"
}

