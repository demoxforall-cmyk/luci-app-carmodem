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

# Телефонный номер для SMS: строго +цифры (NFR-6) — иные символы (кавычки,
# буквы, пробелы) ломают key-value парсер mmcli --messaging-create-sms.
# ВАЖНО: сначала case (матчит строку ЦЕЛИКОМ, включая перевод строки) — иначе
# многострочный ввод "+123\n',text=pwn" обошёл бы построчный grep -q по первой
# валидной строке и позволил дописать чужие свойства SMS через jshn-декод \n.
cm_sanitize_phone() {
    case "$1" in ''|*[!0-9+]*) return 1 ;; esac
    printf '%s' "$1" | grep -qE '^\+?[0-9]{2,20}$'
}

# Текст SMS: mmcli не умеет экранировать одинарную кавычку внутри text='...'
# (апостроф досрочно закрывает значение и позволяет дописать чужие свойства).
# Заменяем ASCII-апостроф на типографский U+2019 — смысл сообщения сохраняется.
cm_sms_text_clean() {
    printf '%s' "$1" | sed "s/'/’/g"
}

# UI-токены band-lock (B1,n78) -> имена ModemManager с разделителем mmcli '|'
# (eutran-1|ngran-78). Пустой список = снять блокировку = 'any'.
cm_bands_to_mm() {
    printf '%s' "$1" | awk '
        BEGIN { RS=","; ORS=""; c=0 }
        { t=$0; gsub(/^[ \t\n]+|[ \t\n]+$/, "", t); if (t == "") next
          printf "%s%s", (c++ ? "|" : ""), \
              (substr(t,1,1) == "B" ? "eutran-" substr(t,2) : "ngran-" substr(t,2)) }
        END { if (!c) printf "any" }'
}

# --- Действия (на устройстве; не тестируются на dev-машине) --------------
cm_set_band() {
    cm_validate_bands "$1" || { echo '{"error":"bad_bands"}'; return 1; }
    mm=$(cm_bands_to_mm "$1")
    mmcli -m "$CM_MM_INDEX" --set-current-bands="$mm" >/dev/null 2>&1 \
        && echo '{"ok":true}' || echo '{"error":"set_band_failed"}'
}

cm_set_rat() {
    # строгий whitelist; 'auto' с фронтенда -> 'any' в терминах mmcli
    case "$1" in
        auto)        mode="any" ;;
        2g|3g|4g|5g) mode="$1" ;;
        *) echo '{"error":"bad_mode"}'; return 1 ;;
    esac
    mmcli -m "$CM_MM_INDEX" --set-allowed-modes="$mode" >/dev/null 2>&1 \
        && echo '{"ok":true}' || echo '{"error":"set_rat_failed"}'
}

# --- SIM-слот (FR-3): RM520N-GL, AT+QUIMSLOT. После смены слота модем
# переинициализируется (~10-20 с) и может получить новый индекс MM — бэкенд
# это переживает (индекс резолвится на каждый rpcd-вызов).
cm_set_sim() {
    case "$1" in 1|2) ;; *) echo '{"error":"bad_slot"}'; return 1 ;; esac
    cur=$(cm_at 'AT+QUIMSLOT?' 2>/dev/null | sed -n 's/.*+QUIMSLOT: *\([12]\).*/\1/p' | head -1)
    [ "$cur" = "$1" ] && { printf '{"ok":true,"slot":%s}\n' "$1"; return 0; }
    out=$(cm_at "AT+QUIMSLOT=$1" 2>&1)
    case "$out" in
        *OK*) printf '{"ok":true,"slot":%s}\n' "$1" ;;
        *)    echo '{"error":"set_sim_failed"}'; return 1 ;;
    esac
}

# --- TTL-фикс (FR-3): nftables через fw4-инклюды (/etc/nftables.d/*.nft
# включаются внутрь таблицы inet fw4). out = исходящие в сторону оператора
# (типовой анти-tethering: 64), in = входящие от оператора. 0 = не ставить
# правило; оба 0 = снять фикс. Файл в /etc переживает ребут; применение —
# reload fw4 с предварительной проверкой синтаксиса (fw4 check).
CM_TTL_NFT="${CM_TTL_NFT:-/etc/nftables.d/90-carmodem-ttl.nft}"
cm_ttl_ruleset() {   # $1=in $2=out $3=iface -> текст .nft на stdout
    printf '# CarModem TTL fix — файл генерируется, не редактировать\n'
    if [ "$2" -gt 0 ] 2>/dev/null; then
        printf 'chain carmodem_ttl_post {\n'
        printf '  type filter hook postrouting priority 300; policy accept;\n'
        printf '  oifname "%s" ip ttl set %s\n' "$3" "$2"
        printf '  oifname "%s" ip6 hoplimit set %s\n' "$3" "$2"
        printf '}\n'
    fi
    if [ "$1" -gt 0 ] 2>/dev/null; then
        printf 'chain carmodem_ttl_pre {\n'
        printf '  type filter hook prerouting priority 300; policy accept;\n'
        printf '  iifname "%s" ip ttl set %s\n' "$3" "$1"
        printf '  iifname "%s" ip6 hoplimit set %s\n' "$3" "$1"
        printf '}\n'
    fi
}
cm_set_ttl() {
    tin="${1:-0}"; tout="${2:-0}"
    case "$tin"  in ''|*[!0-9]*) echo '{"error":"bad_ttl"}'; return 1 ;; esac
    case "$tout" in ''|*[!0-9]*) echo '{"error":"bad_ttl"}'; return 1 ;; esac
    [ "$tin" -le 255 ] && [ "$tout" -le 255 ] || { echo '{"error":"bad_ttl"}'; return 1; }
    if [ "$tin" -eq 0 ] && [ "$tout" -eq 0 ]; then
        rm -f "$CM_TTL_NFT"
        command -v fw4 >/dev/null 2>&1 && fw4 reload >/dev/null 2>&1
        echo '{"ok":true,"in":0,"out":0}'; return 0
    fi
    # интерфейс модема — из активного bearer'а MM; без соединения — wwan0
    ifc="wwan0"
    if type cm_mm_raw >/dev/null 2>&1; then
        bidx=$(cm_mm_raw -m "$CM_MM_INDEX" 2>/dev/null | sed -n 's#.*bearers\.value\[1\].*Bearer/\([0-9]\{1,\}\).*#\1#p' | head -1)
        [ -n "$bidx" ] && bif=$(cm_mm_raw -b "$bidx" 2>/dev/null | sed -n 's/.*bearer\.status\.interface *: *//p' | head -1)
        [ -n "$bif" ] && ifc="$bif"
    fi
    prev=$(cat "$CM_TTL_NFT" 2>/dev/null)
    mkdir -p "$(dirname "$CM_TTL_NFT")" 2>/dev/null
    cm_ttl_ruleset "$tin" "$tout" "$ifc" > "$CM_TTL_NFT"
    if command -v fw4 >/dev/null 2>&1; then
        if ! fw4 check >/dev/null 2>&1; then
            # откат: не оставляем невалидный инклюд, который сломает firewall
            if [ -n "$prev" ]; then printf '%s\n' "$prev" > "$CM_TTL_NFT"; else rm -f "$CM_TTL_NFT"; fi
            echo '{"error":"nft_invalid"}'; return 1
        fi
        fw4 reload >/dev/null 2>&1 || { echo '{"error":"fw_reload_failed"}'; return 1; }
    fi
    # Предупреждение: при включённом flow offloading установленные соединения
    # уходят на fastpath (ingress) мимо prerouting/postrouting -> перезапись TTL
    # на офлоаженных потоках НЕ применяется, и анти-tethering-фикс молча не
    # действует. Правило видно в nft, но эффекта нет -> честно сигналим в UI.
    warn=""
    if command -v uci >/dev/null 2>&1; then
        off=$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)
        offh=$(uci -q get firewall.@defaults[0].flow_offloading_hw 2>/dev/null)
        { [ "$off" = "1" ] || [ "$offh" = "1" ]; } && warn=',"warn":"flow_offloading"'
    fi
    printf '{"ok":true,"in":%s,"out":%s,"iface":"%s"%s}\n' "$tin" "$tout" "$ifc" "$warn"
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
    # -l ограничивает выборку последними N записями НА СТОРОНЕ logd -> не тянем и
    # не грепаем весь кольцевой буфер syslog каждые 2 c (важно при большом log_size)
    log=$(logread -l 500 2>/dev/null | grep -iE 'modemmanager|netifd|wwan|bearer' | tail -n 120)
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

