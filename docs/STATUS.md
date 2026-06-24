# Состояние разработки

Срез после этапа «Ядро + UX-экраны». Источник истины по объёму — `docs/TZ_v1.1.md`.

## Готово и проверено (без железа)

### Этап 1 — Ядро (бэкенд)
- **Парсеры AT** `root/usr/share/carmodem/parse.awk` (BusyBox awk): servingcell,
  QRSRP/QRSRQ/QSINR (по-антенные), QCAINFO, QNWINFO, QTEMP.
  Декодирование hex Cell ID → eNB/сектор, hex TAC, индекс BW → МГц, `-32768` → N/A.
- **MM-слой** `mm.sh` + `mm.awk`: status / signal / neighbours через стабильный
  `mmcli -K` (key-value). Скан операторов + спидтест — `control.awk`.
- **AT-слой** `at.sh`: единая точка `cm_at`, сериализация через flock на порт
  (ТЗ NFR-2). Транспорт подменяем (`CM_AT_TRANSPORT`) для mock-тестов.
- **Сборка телеметрии** `telemetry.sh`: единый JSON из AT-источников.
- **Управление** `control.sh`: band-lock/RAT/SIM/TTL/дозвон/сброс + санитизация
  ввода против AT/USSD-инъекций (ТЗ NFR-6).
- **rpcd-объект** `usr/libexec/rpcd/carmodem` — полный ubus-контракт; `acl.d` обновлён.
- **init.d** `etc/init.d/carmodem` — включает MM signal-polling при старте.

### Этап 3 — UX-экраны (фронтенд LuCI, JS)
- Общий модуль `resources/carmodem.js`: RPC, цветовые пороги (раздел 7),
  N/A-рендеринг (FR-34), маскирование IMEI (NFR-6), deep-link на карту (FR-33).
- `view/carmodem/info.js` — Modem Info (дашборд, опрос 3 с).
- `view/carmodem/antenna.js` — Setup antenna (крупные индикаторы, опрос 1 с).
- `view/carmodem/internet.js` — Internet Status (realtime-график + спидтест).
- `view/carmodem/control.js` — Расширенная панель (RAT/band/SIM/TTL/AT-консоль/скан).
- `view/carmodem/sms.js`, `view/carmodem/ussd.js` — сервисные экраны.
- CSS `view/carmodem/carmodem.css` — desktop-first адаптив, тема наследуется из LuCI.
- **i18n**: `po/ru` (полное покрытие), `po/templates` (.pot). Технические термины
  (RSRP/PCI/5G NR/SMS/USSD…) — латиницей в обоих языках (NFR-5).

### Тесты (без железа) — `sh tests/run_all.sh`
- `run_parsers.sh` — 15 кейсов (golden + поведение + граничные).
- `run_backend.sh` — 21 кейс (сборка телеметрии, MM signal/status/location/neighbours).
- `run_control.sh` — 12 кейсов (парсеры скана/спидтеста + санитизация).
- `check_js.mjs` (deno) — синтаксис всех вьюх. `sh -n` — синтаксис всех скриптов.
- **Итого: 57 функциональных тестов зелёные.**

### Фикстуры сверены с железом ✅
Захваты сняты с реального RM520N-GL (ImmortalWRT, MegaFon, LTE Band 7) и лежат
в `tests/fixtures/` + `tests/fixtures/mm/`. По ним подтверждены/исправлены:
- AT-ответы несут CR (`\r`) — снимается во всех парсерах;
- `mmcli -K` cell-info = композитная строка `modem.generic.cell-info.value[N]`,
  PCI (`physical ci`) в hex (F3/A0/102) — neighbours-парсер переписан под это;
- 5G-поля при LTE = `-32768`/`-3276.80` → null;
- location-3gpp отдаёт Cell ID/TAC в hex (`01A8D1AB`/`002364`).

## 5G / CA — обработано по документации (захват недоступен)
Площадка не в зоне 5G-покрытия, живой NR-фикстуры не будет. Поэтому 5G/CA
реализованы по документации Quectel/MM и закрыты **синтетическими** тестами
(`tests/fixtures/synthetic/`, помечены как не снятые с железа):
- `servingcell` ветвится по RAT: NR5G-SA разбирается отдельной раскладкой,
  LTE-позиции на NR-ответ не применяются (защита от мусора); enb/sector для NR = N/A
  (декомпозиция NCI у gNB иная).
- NR-сигнал идёт через версионно-стабильный `modem.signal.5g.*` (MM).
- Активная CA: многострочный `+QCAINFO` (PCC+SCC) → массив компонент.
Если устройство когда-нибудь окажется в 5G — снять `+QENG`/`--signal-get` и сверить
NR-раскладку (один тест-фикстур), правки будут точечными.

## Ещё требует захватов (не критично)
- `mmcli -K -m 0 --messaging-list-sms` **с сообщениями** в памяти (сейчас 0) —
  финализировать SMS-листинг (пустой случай работает).
- `mmcli -K -m 0 --3gpp-scan` — формат списка операторов (сейчас реконструирован).
- `librespeed-cli --json` с устройства (поля сверены по документации).

## Развёрнут и проверен на железе ✅ (2026-06-20)
Установлен на RM520N-GL/ImmortalWRT (dropbear), дашборд телеметрии работает.
Полный `ubus call carmodem get_telemetry` ~1с, все секции заполнены (сота, band,
по-антенные Rx0/Rx1, CA, температура 17 датчиков) + MM (статус/сигнал/соседи/инфо).

Критичные правки под реальный BusyBox этой прошивки (внесены в код):
- нет `stty`/`timeout`/`microcom` (есть `socat`); порт уже raw (держит MM) — ок;
- `flock` без `-w` → блокирующий `flock -x`;
- `read -t` на tty не работает → AT-чтение через фоновый `cat`, ожидание OK/ERROR;
- модем теряет очередь из нескольких AT-команд → все метрики ОДНОЙ строкой через
  конкатенацию Quectel `;` (опрос упал с ~4с-с-потерями до ~1с-полный);
- ubus/rpcd не принимает массив верхнего уровня → get_neighbours/scan_operators/
  get_sms обёрнуты в объект (`{"cells":[...]}`) + `expect` на фронтенде;
- доставка файлов на dropbear-роутер — только `scp -O`.

## Сборка — ВЫПОЛНЕНА ✅ (DEL-3)
`.apk` собран в ImmortalWRT SDK 25.12 (mediatek/filogic) через WSL Ubuntu 24.04.
Результат проверен `apk adbdump`:
- `luci-app-carmodem-0.1-r1.apk`, **arch: `noarch`** → ставится на любой 25.12-таргет;
- depends: `libc`, `luci-base`, `luci-proto-modemmanager`, `modemmanager` (4 шт.);
- `/usr/libexec/rpcd/carmodem` и `/etc/init.d/carmodem` — **mode 0755** (биты +x ок);
- внутри все бэкенд-скрипты, парсеры, вьюхи, ACL, меню.

Сборочные ассеты (для повтора/CI):
- `build/wsl-fix-build.sh` — рабочий рецепт (выборочные фиды, без `-a`).
- `build/build-in-sdk.sh` — сборка в готовом распакованном SDK.
- `build/Dockerfile` — контейнерная сборка.
- `tests/check_package.sh` — линтер целостности (30 проверок), зелёный.

Грабли, на которые наступили и обошли:
- `feeds install -a` тащит весь base/packages (uboot-mediatek prereq, рекурсивные
  deps nginx) → ставим ТОЛЬКО зависимости.
- `librespeed-cli` (Go) не собирается в SDK → вынесен из build-deps, ставится на
  устройстве отдельно (`apk add librespeed-cli`).
- WSL2 + VPN на хосте = нет сети в WSL → `networkingMode=mirrored` в `.wslconfig`.

## Не начато
- Профиль адаптации RM520N одним файлом (DEL-4) — данные уже в docs/, свести.
- `set_sim`/`set_ttl` действия (заглушки в контракте; реализовать через UCI/iptables).
- Событийный мониторинг `--monitor-state` (FR-32b).
