# CarModem — парсеры скана операторов и хранилища SMS
# SPDX-License-Identifier: GPL-2.0
# Совместимо с BusyBox awk. Usage: awk -v fn=<name> -f control.awk
#   scan       `mmcli --3gpp-scan -K`     -> массив операторов
#   cpms       ответ `AT+CPMS?` (3GPP 27.005) -> {storage,used,total}

function jstr(s) {
    if (s == "" ) return "null"
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    return "\"" s "\""
}
function jnum(x) { if (x == "" || x == "--") return "null"; return x + 0 }
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

# вытащить "field: value" из композитной строки mmcli scan-networks
function field(s, name,   re, p, rest, e) {
    re = name ": "
    p = index(s, re)
    if (p == 0) return ""
    rest = substr(s, p + length(re))
    e = index(rest, ",")
    if (e > 0) rest = substr(rest, 1, e - 1)
    return trim(rest)
}

BEGIN { if (fn == "scan") { printf "["; first = 1 } }

{ gsub(/\r/, "") }   # снять возможный CR из реальных ответов

fn == "scan" {
    p = index($0, "scan-networks.value[")
    if (p == 0) next
    q = index($0, ":")
    if (q == 0) next
    val = substr($0, q + 1)
    code = field(val, "operator-code")
    name = field(val, "operator-name")
    tech = field(val, "access-technologies")
    avail = field(val, "availability")
    if (code == "" && name == "") next
    if (!first) printf ","
    first = 0
    printf "{\"plmn\":%s,\"name\":%s,\"tech\":%s,\"status\":%s}", \
        jstr(code), jstr(name), jstr(tech), jstr(avail)
    next
}

# AT+CPMS? -> +CPMS: "ME",used1,total1,"ME",used2,total2,"ME",used3,total3
# Берём mem1 (хранилище чтения/удаления) и его счётчики.
fn == "cpms" { line = line $0 " " }

END {
    if (fn == "scan") { printf "]\n" }
    else if (fn == "cpms") {
        p = index(line, "+CPMS:")
        if (p == 0) { printf "{\"storage\":null}\n" }
        else {
            rest = substr(line, p + 6)
            n = split(rest, a, ",")
            mem = a[1]; gsub(/[^A-Za-z]/, "", mem)   # «"ME"» -> ME
            printf "{\"storage\":%s,\"used\":%s,\"total\":%s}\n", \
                jstr(tolower(mem)), jnum(a[2]), jnum(a[3])
        }
    }
}
