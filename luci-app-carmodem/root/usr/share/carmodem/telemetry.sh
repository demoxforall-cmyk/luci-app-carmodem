# CarModem — сборка телеметрии из AT-источников
# SPDX-License-Identifier: GPL-2.0
#
# Собирает «глубокие» метрики, которые НЕ покрывает ModemManager (ТЗ 3.2):
# по-антенные Rx0-3, компоненты CA, servingcell (сота/band), температура.
# Сигнал, соседние соты, идентификацию отдаёт MM-слой (mm.sh).
#
# Все метрики берутся ОДНОЙ AT-командой через конкатенацию Quectel (`;`):
# модем отдаёт все подответы и единственный OK (проверено на RM520N-GL).
# Объединённый ответ скармливается каждому парсеру — каждый выбирает свою
# строку (+QENG, +QRSRP, +QCAINFO, ...). Один обмен вместо семи: опрос ~1с,
# без потери команд (очередь из 7 команд модем терял).

CM_SHARE="${CM_SHARE:-/usr/share/carmodem}"
CM_PARSE="${CM_PARSE:-$CM_SHARE/parse.awk}"

_cm_parse() { awk -v fn="$1" -f "$CM_PARSE"; }

# значение или дефолт, если парсер вернул пусто/null
_cm_def() {
    if [ -z "$1" ] || [ "$1" = "null" ]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

cm_telemetry_at() {
    buf=$(cm_at 'AT+QENG="servingcell";+QRSRP;+QRSRQ;+QSINR;+QCAINFO;+QNWINFO;+QTEMP')

    sc=$(  _cm_def "$(printf '%s\n' "$buf" | _cm_parse servingcell)" '{}')
    rsrp=$(_cm_def "$(printf '%s\n' "$buf" | _cm_parse qrsrp)" '{}')
    rsrq=$(_cm_def "$(printf '%s\n' "$buf" | _cm_parse qrsrq)" '{}')
    sinr=$(_cm_def "$(printf '%s\n' "$buf" | _cm_parse qsinr)" '{}')
    ca=$(  _cm_def "$(printf '%s\n' "$buf" | _cm_parse qcainfo)" '[]')
    nw=$(  _cm_def "$(printf '%s\n' "$buf" | _cm_parse qnwinfo)" '{}')
    temp=$(_cm_def "$(printf '%s\n' "$buf" | _cm_parse qtemp)" '{}')

    printf '{'
    printf '"servingcell":%s,' "$sc"
    printf '"antenna":{"rsrp":%s,"rsrq":%s,"sinr":%s},' "$rsrp" "$rsrq" "$sinr"
    printf '"ca":%s,' "$ca"
    printf '"nwinfo":%s,' "$nw"
    printf '"temp":%s' "$temp"
    printf '}'
}

# Агрегат экрана Status: status+signal+telemetry+cells в ОДНОМ процессе rpcd
# (1 форк + 1 сорсинг набора shell-файлов на тик вместо 4). Число mmcli/AT-вызовов
# не меняется — экономятся форки rpcd-плагина и HTTP/ubus-накладные.
cm_dashboard() {
    printf '{"status":%s,"signal":%s,"telemetry":%s,"cells":%s}\n' \
        "$(cm_mm_status)" "$(cm_mm_signal)" "$(cm_telemetry_at)" "$(cm_mm_neighbours)"
}
