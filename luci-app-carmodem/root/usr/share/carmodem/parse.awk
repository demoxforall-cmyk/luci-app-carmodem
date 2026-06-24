# CarModem — библиотека парсеров AT-ответов RM520N-GL
# SPDX-License-Identifier: GPL-2.0
#
# Совместимо с BusyBox awk (без gensub/asorti/gawk-расширений).
# Использование:  awk -v fn=<name> -f parse.awk < raw_at_output
# На stdout — одна строка JSON (объект или массив).
#
# Поддерживаемые fn:
#   servingcell  +QENG="servingcell" (LTE)  -> объект
#   qrsrp        +QRSRP   по-антенные RSRP   -> объект
#   qrsrq        +QRSRQ   по-антенные RSRQ   -> объект
#   qsinr        +QSINR   по-антенные SINR   -> объект
#   qcainfo      +QCAINFO компоненты CA      -> массив объектов
#   qnwinfo      +QNWINFO ведущий band       -> объект
#   qtemp        +QTEMP   температуры         -> объект
#
# Граничные правила (проверены на железе, см. docs/sources_MM_vs_AT.md):
#   -32768 в по-антенных = «нет тракта» -> JSON null (UI: N/A)
#   Cell ID и TAC в servingcell приходят в HEX.
#   Отсутствующее числовое поле '-' -> null.

function jnum(x) {
    # числовое значение -> JSON-число или null
    if (x == "" || x == "-" || x == "--") return "null"
    return x
}
function jant(x) {
    # по-антенное значение: «нет тракта» -> null.
    # -32768 — сентинел в простое; -140 и ниже — пол RSRP при активной CA
    # (тракт без сигнала). Реальные RSRP/RSRQ/SINR не опускаются до -140.
    if (x == "" || x == "-" || x+0 <= -140) return "null"
    return x+0
}
function jstr(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/,  "\\\"", s)
    return "\"" s "\""
}
function trimq(s) {
    # убрать обрамляющие кавычки и пробелы
    gsub(/^[ \t]+|[ \t]+$/, "", s)
    gsub(/^"|"$/, "", s)
    return s
}
function hex2dec(h,   n, i, c, d, up) {
    n = 0; up = toupper(h)
    if (up == "") return ""
    for (i = 1; i <= length(up); i++) {
        c = substr(up, i, 1)
        d = index("0123456789ABCDEF", c) - 1
        if (d < 0) return ""   # не hex
        n = n * 16 + d
    }
    return n
}
function bwmhz(idx,   a, n) {
    # 3GPP индекс ширины канала LTE -> МГц
    n = split("1.4 3 5 10 15 20", a, " ")
    idx = idx + 1
    if (idx >= 1 && idx <= n) return a[idx]
    return ""
}
# разбить CSV-строку, снимая кавычки с каждого поля
function csv_split(s, arr,   n, i) {
    n = split(s, arr, ",")
    for (i = 1; i <= n; i++) arr[i] = trimq(arr[i])
    return n
}

# ---- servingcell (LTE и NR5G-SA) ----
# LTE: +QENG: "servingcell","NOCONN","LTE","FDD",250,02,1A8D147,258,2850,7,5,5,2364,-91,-8,-63,21,0,-,32
# NR:  +QENG: "servingcell","NOCONN","NR5G-SA","TDD",250,02,<NCI>,<PCI>,<TAC>,<ARFCN>,<band>,<bw>,<RSRP>,<SINR>,<RSRQ>
#
# Общий префикс (f1..f6: state,rat,duplex,mcc,mnc,cellID) одинаков у LTE и NR —
# поэтому разбираем его всегда, а «хвост» ветвим по RAT. Это защищает от
# раскладки NR-полей по LTE-позициям (выдало бы мусор на 5G-регистрации).
function parse_servingcell(line,   rest, p, n, f, cid, tac, mhz, lte, nr) {
    p = index(line, "\"servingcell\",")
    if (p == 0) return 0
    rest = substr(line, p + length("\"servingcell\","))
    n = csv_split(rest, f)
    if (n < 7) return 0
    lte = (f[2] ~ /LTE/)
    nr  = (f[2] ~ /NR5G/)
    cid = hex2dec(f[6])

    # неизвестный RAT — безопасный минимум, без позиционной раскладки
    if (!lte && !nr) {
        printf "{\"state\":%s,\"rat\":%s,\"duplex\":%s,\"mcc\":%s,\"mnc\":%s,\"plmn\":%s,\"cell_id_raw\":%s}\n", \
            jstr(f[1]), jstr(f[2]), jstr(f[3]), jstr(f[4]), jstr(f[5]), jstr(f[4] f[5]), jstr(f[6])
        return 1
    }

    # --- общий префикс ---
    printf "{"
    printf "\"state\":%s,",  jstr(f[1])
    printf "\"rat\":%s,",    jstr(f[2])
    printf "\"duplex\":%s,", jstr(f[3])
    printf "\"mcc\":%s,",    jstr(f[4])
    printf "\"mnc\":%s,",    jstr(f[5])
    printf "\"plmn\":%s,",   jstr(f[4] f[5])
    printf "\"cell_id_raw\":%s,", jstr(f[6])
    printf "\"cell_id\":%s,", (cid == "" ? "null" : cid)

    if (lte) {
        # f7=pci f8=earfcn f9=band f10=ulbw f11=dlbw f12=tac(hex)
        # f13=rsrp f14=rsrq f15=rssi f16=sinr f17=cqi f18=txpwr f19=srxlev
        tac = hex2dec(f[12]); mhz = bwmhz(f[11] + 0)
        printf "\"enb\":%s,",    (cid == "" ? "null" : int(cid / 256))
        printf "\"sector\":%s,", (cid == "" ? "null" : cid % 256)
        printf "\"pci\":%s,",    jnum(f[7])
        printf "\"earfcn\":%s,", jnum(f[8])
        printf "\"band\":%s,",   jstr("B" f[9])
        printf "\"bw_mhz\":%s,", (mhz == "" ? "null" : jstr(mhz))
        printf "\"tac_raw\":%s,", jstr(f[12])
        printf "\"tac\":%s,",     (tac == "" ? "null" : tac)
        printf "\"rsrp\":%s,",   jnum(f[13])
        printf "\"rsrq\":%s,",   jnum(f[14])
        printf "\"rssi\":%s,",   jnum(f[15])
        printf "\"sinr\":%s,",   jnum(f[16])
        printf "\"cqi\":%s,",    jnum(f[17])
        printf "\"tx_power\":%s,", jnum(f[18])
        printf "\"srxlev\":%s",  jnum(f[19])
        # Timing Advance в LTE-формате servingcell отсутствует -> бэкенд проставит ta=N/A
    } else {
        # NR5G-SA (раскладка по документации Quectel, не верифицировано на железе —
        # нет 5G-покрытия для захвата): f7=pci f8=tac f9=arfcn f10=band f11=bw
        # f12=rsrp f13=sinr f14=rsrq. gNB-декомпозиция NCI иная -> enb/sector=N/A.
        tac = hex2dec(f[8])
        printf "\"enb\":null,"
        printf "\"sector\":null,"
        printf "\"pci\":%s,",    jnum(f[7])
        printf "\"earfcn\":%s,", jnum(f[9])
        printf "\"band\":%s,",   jstr("n" f[10])
        printf "\"bw_mhz\":null,"
        printf "\"tac_raw\":%s,", jstr(f[8])
        printf "\"tac\":%s,",     (tac == "" ? "null" : tac)
        printf "\"rsrp\":%s,",   jnum(f[12])
        printf "\"rsrq\":%s,",   jnum(f[14])
        printf "\"rssi\":null,"
        printf "\"sinr\":%s,",   jnum(f[13])
        printf "\"cqi\":null,"
        printf "\"srxlev\":null"
    }
    printf "}\n"
    return 1
}

# ---- по-антенные QRSRP/QRSRQ/QSINR ----
# +QRSRP: -95,-91,-32768,-32768,LTE
function parse_perant(line, tag, key,   p, rest, f, n) {
    p = index(line, tag)
    if (p == 0) return 0
    rest = substr(line, p + length(tag))
    sub(/^:[ \t]*/, "", rest)
    n = csv_split(rest, f)
    if (n < 4) return 0
    printf "{"
    printf "\"%s0\":%s,", key, jant(f[1])
    printf "\"%s1\":%s,", key, jant(f[2])
    printf "\"%s2\":%s,", key, jant(f[3])
    printf "\"%s3\":%s,", key, jant(f[4])
    printf "\"rat\":%s",  (n >= 5 ? jstr(f[5]) : "null")
    printf "}\n"
    return 1
}

# ---- QCAINFO: компоненты агрегации ----
# +QCAINFO: "PCC",2850,100,"LTE BAND 7",1,258,-91,-10,-61,20
# Может быть несколько строк (PCC + SCC...). Возвращаем массив.
function parse_qcainfo_line(line, first,   p, rest, f, n) {
    p = index(line, "+QCAINFO:")
    if (p == 0) return first
    rest = substr(line, p + length("+QCAINFO:"))
    n = csv_split(rest, f)
    if (n < 6) return first
    if (!first) printf ","
    printf "{"
    printf "\"type\":%s,",   jstr(f[1])          # PCC / SCC
    printf "\"earfcn\":%s,", jnum(f[2])
    printf "\"bw\":%s,",     jnum(f[3])          # ширина (число RB/класс — сырое)
    printf "\"band\":%s,",   jstr(f[4])          # "LTE BAND 7"
    printf "\"pci\":%s,",    jnum(f[6])
    printf "\"rsrp\":%s,",   jnum(f[7])
    printf "\"rsrq\":%s,",   jnum(f[8])
    printf "\"rssi\":%s,",   jnum(f[9])
    printf "\"sinr\":%s",    jnum(f[10])
    printf "}"
    return 0   # больше не first
}

# ---- QNWINFO: ведущий band ----
# +QNWINFO: "FDD LTE","25002","LTE BAND 7",2850
function parse_qnwinfo(line,   p, rest, f, n) {
    p = index(line, "+QNWINFO:")
    if (p == 0) return 0
    rest = substr(line, p + length("+QNWINFO:"))
    n = csv_split(rest, f)
    if (n < 4) return 0
    printf "{"
    printf "\"act\":%s,",    jstr(f[1])   # FDD LTE / TDD LTE / NR5G ...
    printf "\"plmn\":%s,",   jstr(f[2])
    printf "\"band\":%s,",   jstr(f[3])
    printf "\"channel\":%s", jnum(f[4])   # EARFCN / NR-ARFCN
    printf "}\n"
    return 1
}

# ---- QTEMP: температуры ----
# Формат варьируется по прошивкам; типично пары "<sensor>","<value>".
# +QTEMP: "modem-skin0",37
# +QTEMP:"cpu0-0-usr","40"
function parse_qtemp_line(line, first,   p, rest, f, n, name, val) {
    p = index(line, "+QTEMP:")
    if (p == 0) return first
    rest = substr(line, p + length("+QTEMP:"))
    n = csv_split(rest, f)
    if (n < 2) return first
    name = f[1]; val = f[2]
    if (name == "" || val == "") return first
    if (!first) printf ","
    printf "%s:%s", jstr(name), jnum(val)
    return 0
}

BEGIN { started = 0 }

{ gsub(/\r/, "") }   # реальные AT-ответы несут CR (\r) — снять до разбора

# QCAINFO и QTEMP — потоковые (несколько строк): открываем контейнер заранее
fn == "qcainfo" && !started { printf "["; started = 1; first = 1 }
fn == "qtemp"   && !started { printf "{"; started = 1; first = 1 }

fn == "qcainfo" { first = parse_qcainfo_line($0, first); next }
fn == "qtemp"   { first = parse_qtemp_line($0, first);   next }

# Одностраничные парсеры: берём первую подходящую строку
fn == "servingcell" && !done { if (parse_servingcell($0))               done = 1; next }
fn == "qrsrp"       && !done { if (parse_perant($0, "+QRSRP", "rx"))    done = 1; next }
fn == "qrsrq"       && !done { if (parse_perant($0, "+QRSRQ", "rx"))    done = 1; next }
fn == "qsinr"       && !done { if (parse_perant($0, "+QSINR", "rx"))    done = 1; next }
fn == "qnwinfo"     && !done { if (parse_qnwinfo($0))                   done = 1; next }

END {
    if (fn == "qcainfo") { if (!started) printf "["; printf "]\n" }
    else if (fn == "qtemp") { if (!started) printf "{"; printf "}\n" }
    else if (!done) printf "null\n"   # не нашли ожидаемую строку
}
