# Тесты

Прогон всего набора (нужен только `sh` + `awk`, как на устройстве):

    sh tests/run_all.sh

Наборы:
- `run_parsers.sh` — юнит-тесты AT-парсеров (`parse.awk`) на фикстурах: golden,
  поведение (hex Cell ID → eNB/сектор, `-32768` → N/A), граничные случаи.
- `run_backend.sh` — сборка телеметрии и MM-слой (signal/status/location/neighbours)
  через mock-транспорты (`tests/mocks/`).
- `run_control.sh` — парсеры скана/спидтеста (`control.awk`) + санитизация ввода.
- `check_js.mjs` (deno) — синтаксис LuCI-вьюх:
  `deno run --allow-read tests/check_js.mjs <файлы>`.

Итого 48 кейсов, все зелёные.

## Фикстуры — реальные захваты RM520N-GL
Сняты с устройства (ImmortalWRT, MegaFon, LTE Band 7) скриптом
`tools/capture_fixtures.sh`:
- `fixtures/*.txt` — AT-ответы (servingcell, QRSRP/QRSRQ/QSINR, QCAINFO, QNWINFO,
  QTEMP, QNWPREFCFG). Несут CR (`\r`) — как на устройстве; парсеры его снимают.
- `fixtures/mm/*.kv` — `mmcli -K`: status, signal, cellinfo (композитный, hex PCI),
  location (hex Cell ID/TAC), sms_list (пусто).
- `expected/*.json` — golden, сгенерированы из реального вывода парсеров.
- `fixtures/mm/scan.kv`, `fixtures/speedtest.json` — реконструированы по документации
  (реальных захватов пока нет, см. docs/STATUS.md).

## Прототип
`parse_servingcell.py` — исходный эталон разбора servingcell (Python). Боевой парсер —
`parse.awk` (BusyBox awk, работает на устройстве без Python).

## Что докрутить (нужны новые захваты)
- Фикстуры при **5G-NR-регистрации** и при **активной CA** (несколько +QCAINFO).
- `--messaging-list-sms` с сообщениями в памяти → финализировать SMS-листинг.
- Реальные `--3gpp-scan` и `librespeed-cli --json`.
- mock-AT через socat-PTY для проверки сериализации AT-демона на хосте.
