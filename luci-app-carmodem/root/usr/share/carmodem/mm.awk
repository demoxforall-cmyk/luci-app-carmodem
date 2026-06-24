# CarModem — парсер вывода `mmcli ... -K` (key-value) в JSON
# SPDX-License-Identifier: GPL-2.0
# Совместимо с BusyBox awk.
#
# `mmcli -K` даёт строки `key.path : value`. Формат стабилен между версиями MM.
# Проверено на RM520N-GL (ImmortalWRT). Usage: awk -v fn=<name> -f mm.awk
#
# fn:
#   signal      modem.signal.lte/5g.*       -> объект (RSRP/RSRQ/RSSI/SINR)
#   status      modem.generic.* + modem.3gpp.* -> объект
#   neighbours  modem.generic.cell-info.value[N] (композитная строка) -> массив
#   location    modem.location.3gpp.*        -> объект (cid/tac/mcc/mnc, hex)

function jnum(x) {
    if (x == "" || x == "--" || x == "-" || tolower(x) == "n/a") return "null"
    return x + 0
}
# сигнальное значение: сентинел «нет тракта» (-32768 / snr -3276.80) -> null
function jsig(x,   v) {
    if (x == "" || x == "--") return "null"
    v = x + 0
    if (v < -1000) return "null"      # реальные RSRP/RSRQ/SINR не ниже ~ -140
    return v
}
function jstr(s) {
    if (s == "" || s == "--") return "null"
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    return "\"" s "\""
}
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function kv(line,   p) {
    p = index(line, ":")
    if (p == 0) return 0
    K = substr(line, 1, p - 1); V = substr(line, p + 1)
    K = trim(K); V = trim(V)
    return 1
}
# Разобрать композитную строку "k1: v1, k2: v2, …" в массив M["k1"]=v1.
function comp(s, M,   n, parts, i, p, k, v) {
    split("", M)
    n = split(s, parts, ", ")
    for (i = 1; i <= n; i++) {
        p = index(parts[i], ": ")
        if (p == 0) continue
        k = trim(substr(parts[i], 1, p - 1))
        v = trim(substr(parts[i], p + 2))
        M[k] = v
    }
}

BEGIN { FS = "\n" }

{ gsub(/\r/, "") }   # реальные ответы могут нести CR — снять до разбора

{
    if (!kv($0)) next

    if (fn == "signal") {
        if (K == "modem.signal.lte.rsrp") d["lte_rsrp"] = V
        else if (K == "modem.signal.lte.rsrq") d["lte_rsrq"] = V
        else if (K == "modem.signal.lte.rssi") d["lte_rssi"] = V
        else if (K == "modem.signal.lte.snr")  d["lte_sinr"] = V
        else if (K == "modem.signal.5g.rsrp")  d["nr_rsrp"] = V
        else if (K == "modem.signal.5g.rsrq")  d["nr_rsrq"] = V
        else if (K == "modem.signal.5g.snr")   d["nr_sinr"] = V
    }
    else if (fn == "status") {
        if (K == "modem.generic.manufacturer") d["manufacturer"] = V
        else if (K == "modem.generic.model") d["model"] = V
        else if (K == "modem.generic.revision") d["firmware"] = V
        else if (K == "modem.generic.hardware-revision") d["hw_revision"] = V
        else if (K == "modem.generic.equipment-identifier") d["imei"] = V
        else if (K == "modem.generic.state") d["state"] = V
        else if (K == "modem.generic.access-technologies.value[1]") d["access_tech"] = V
        else if (K == "modem.generic.signal-quality.value") d["signal_quality"] = V
        else if (K == "modem.3gpp.operator-name") d["operator"] = V
        else if (K == "modem.3gpp.operator-code") d["plmn"] = V
        else if (K == "modem.3gpp.registration-state") d["registration"] = V
        else if (K == "modem.generic.own-numbers.value[1]") d["phone"] = V
        # SIM (mmcli -i): IMSI/ICCID/имя оператора
        else if (K == "sim.properties.imsi") d["imsi"] = V
        else if (K == "sim.properties.iccid") d["iccid"] = V
        else if (K == "sim.properties.operator-name") d["sim_operator"] = V
        # bearer (mmcli -b): интерфейс/APN/IP/DNS/трафик/сессия
        else if (K == "bearer.status.interface") d["interface"] = V
        else if (K == "bearer.properties.apn") d["apn"] = V
        else if (K == "bearer.ipv4-config.address") d["ipv4"] = V
        else if (K == "bearer.ipv4-config.gateway") d["gw4"] = V
        else if (K == "bearer.ipv4-config.dns.value[1]") d["dns1"] = V
        else if (K == "bearer.ipv4-config.dns.value[2]") d["dns2"] = V
        else if (K == "bearer.ipv6-config.address") d["ipv6"] = V
        else if (K == "bearer.stats.duration") d["duration"] = V
        else if (K == "bearer.stats.bytes-rx") d["bytes_rx"] = V
        else if (K == "bearer.stats.bytes-tx") d["bytes_tx"] = V
    }
    else if (fn == "location") {
        if (K == "modem.location.3gpp.mcc") d["mcc"] = V
        else if (K == "modem.location.3gpp.mnc") d["mnc"] = V
        else if (K == "modem.location.3gpp.lac") d["lac"] = V
        else if (K == "modem.location.3gpp.tac") d["tac"] = V
        else if (K == "modem.location.3gpp.cid") d["cid"] = V
    }
    else if (fn == "neighbours") {
        # ключ modem.generic.cell-info.value[N], значение — композитная строка
        if (index(K, "cell-info.value[") > 0) {
            comp(V, C)
            obj = "{" \
                "\"serving\":" jstr(C["serving"]) "," \
                "\"type\":"    jstr(C["cell type"]) "," \
                "\"pci\":"     jstr(C["physical ci"]) "," \
                "\"earfcn\":"  jnum(C["earfcn"]) "," \
                "\"rsrp\":"    jsig(C["rsrp"]) "," \
                "\"rsrq\":"    jsig(C["rsrq"]) "," \
                "\"ci\":"      jstr(C["ci"]) "," \
                "\"tac\":"     jstr(C["tac"]) "}"
            cells[++ncells] = obj
        }
    }
    else if (fn == "sms") {
        # один блок `mmcli -K -s N`. id берём из dbus-path (/.../SMS/N).
        if (K == "sms.dbus-path") { id = V; gsub(/.*\/SMS\//, "", id); d["id"] = id }
        else if (K == "sms.content.number") d["number"] = V
        else if (K == "sms.content.text") d["text"] = V
        else if (K == "sms.properties.pdu-type") d["pdu"] = V
        else if (K == "sms.properties.timestamp") d["timestamp"] = V
        else if (K == "sms.properties.storage") d["storage"] = V   # sm (SIM) / me (модем)
    }
}

END {
    if (fn == "signal") {
        printf "{"
        printf "\"rsrp\":%s,",  jsig(d["lte_rsrp"])
        printf "\"rsrq\":%s,",  jsig(d["lte_rsrq"])
        printf "\"rssi\":%s,",  jsig(d["lte_rssi"])
        printf "\"sinr\":%s,",  jsig(d["lte_sinr"])
        printf "\"nr_rsrp\":%s,", jsig(d["nr_rsrp"])
        printf "\"nr_rsrq\":%s,", jsig(d["nr_rsrq"])
        printf "\"nr_sinr\":%s",  jsig(d["nr_sinr"])
        printf "}\n"
    }
    else if (fn == "status") {
        printf "{"
        printf "\"manufacturer\":%s,", jstr(d["manufacturer"])
        printf "\"model\":%s,",        jstr(d["model"])
        printf "\"firmware\":%s,",     jstr(d["firmware"])
        printf "\"hw_revision\":%s,",  jstr(d["hw_revision"])
        printf "\"imei\":%s,",         jstr(d["imei"])
        printf "\"state\":%s,",        jstr(d["state"])
        printf "\"access_tech\":%s,",  jstr(d["access_tech"])
        printf "\"signal_quality\":%s,", jnum(d["signal_quality"])
        printf "\"operator\":%s,",     jstr(d["operator"])
        printf "\"plmn\":%s,",         jstr(d["plmn"])
        printf "\"registration\":%s,", jstr(d["registration"])
        printf "\"phone\":%s,",        jstr(d["phone"])
        printf "\"imsi\":%s,",         jstr(d["imsi"])
        printf "\"iccid\":%s,",        jstr(d["iccid"])
        printf "\"sim_operator\":%s,", jstr(d["sim_operator"])
        printf "\"interface\":%s,",    jstr(d["interface"])
        printf "\"apn\":%s,",          jstr(d["apn"])
        printf "\"ipv4\":%s,",         jstr(d["ipv4"])
        printf "\"gw4\":%s,",          jstr(d["gw4"])
        printf "\"dns1\":%s,",         jstr(d["dns1"])
        printf "\"dns2\":%s,",         jstr(d["dns2"])
        printf "\"ipv6\":%s,",         jstr(d["ipv6"])
        printf "\"duration\":%s,",     jnum(d["duration"])
        printf "\"bytes_rx\":%s,",     jnum(d["bytes_rx"])
        printf "\"bytes_tx\":%s",      jnum(d["bytes_tx"])
        printf "}\n"
    }
    else if (fn == "location") {
        printf "{"
        printf "\"mcc\":%s,", jstr(d["mcc"])
        printf "\"mnc\":%s,", jstr(d["mnc"])
        printf "\"lac\":%s,", jstr(d["lac"])
        printf "\"tac_hex\":%s,", jstr(d["tac"])
        printf "\"cid_hex\":%s",  jstr(d["cid"])
        printf "}\n"
    }
    else if (fn == "neighbours") {
        printf "["
        for (i = 1; i <= ncells; i++) printf "%s%s", (i > 1 ? "," : ""), cells[i]
        printf "]\n"
    }
    else if (fn == "sms") {
        # тред-объект для входящих (deliver=in) И исходящих (submit=out);
        # прочие pdu (status-report и т.п.) пропускаем
        dir = ""
        if (d["pdu"] == "deliver") dir = "in"
        else if (d["pdu"] == "submit") dir = "out"
        if (dir != "")
            printf "{\"id\":%s,\"number\":%s,\"timestamp\":%s,\"text\":%s,\"storage\":%s,\"dir\":\"%s\"}\n", \
                jnum(d["id"]), jstr(d["number"]), jstr(d["timestamp"]), jstr(d["text"]), jstr(d["storage"]), dir
    }
}
