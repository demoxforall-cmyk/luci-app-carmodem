# Карта источников RM520N-GL — ФИНАЛ (проверено на железе)

## Только ModemManager (AT не нужен)
- Идентификация: производитель, модель, прошивка, IMEI, номер телефона
- Оператор / PLMN / регистрация / состояние / access tech
- Сигнал агрегированный: RSRP/RSRQ/RSSI/SINR  -> `--signal-setup` + `--signal-get`
- 5G NR сигнал (когда есть; иначе N/A)
- RAT (allowed/preferred) + грубый band-lock -> Modes / `--set-current-bands`
- SIM-слоты -> `mmcli -m 0`
- IP / DNS / шлюз / трафик -> bearer `mmcli -b 0`
- SMS список/отправка/удаление -> `--messaging-*`
- PIN/PUK -> `-i 0 --pin=/--puk=`
- Cell ID / LAC -> `--location-get-3gpp`
- СОСЕДНИЕ СОТЫ (PCI/EARFCN/RSRP/RSRQ) -> `--get-cell-info`  [НОВОЕ, подтверждено]
- Скан операторов -> `--3gpp-scan`  [новая функция]
- Событийный мониторинг -> `--monitor-state`
- Сброс -> `--reset` / `--factory-reset`

## Только AT (через AT-демон) — MM НЕ покрывает
- По-антенные Rx0-3 RSRP/RSRQ/SINR -> `AT+QRSRP/QRSRQ/QSINR`
- Компоненты CA (PCC/SCC) -> `AT+QCAINFO`
- Timing Advance -> `AT+QENG="servingcell"`
- Температура модема -> `AT+QTEMP`
- Тонкий NR band-lock (покабельно) -> `AT+QNWPREFCFG`

## Нюансы для парсеров/тестов
- GetCellInfo: PCI в HEX (A0/F3/102); QENG давал decimal -> учесть в парсере
- GetCellInfo: нет TA, нет RSSI/SINR соседей -> TA только из QENG
- по-антенные: -32768 = нет тракта = "N/A"
- 5G-поля появляются только при 5G-регистрации
