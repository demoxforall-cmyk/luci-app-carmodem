// Генератор po/ru/luci-app-carmodem.po: msgid берём ИЗ исходников (байт-точно),
// msgstr — из карты ниже. Непереведённые печатаем (должны быть только аббревиатуры).
const files = ["carmodem.js", "view/carmodem/info.js", "view/carmodem/control.js", "view/carmodem/sms.js"];
const base = "luci-app-carmodem/htdocs/luci-static/resources/";
const re = /\b_\(\s*'((?:[^'\\]|\\.)*)'\s*\)/g;
const ids = new Set();
for (const f of files) { const t = Deno.readTextFileSync(base + f); let m; while ((m = re.exec(t))) ids.add(m[1].replace(/\\'/g, "'")); }

const MAP = {
  // меню (titles тоже переводятся через каталог)
  "Modem": "Модем", "Status": "Статус", "Messages": "Сообщения", "Advanced": "Дополнительно",
  // общий UI
  "(no response)": "(нет ответа)",
  "5G NR band-lock": "5G NR: блокировка диапазонов",
  "AT console": "AT-консоль",
  "Advanced settings": "Расширенные настройки",
  "Apply RAT": "Применить RAT",
  "Auto (all)": "Авто (все)",
  "All": "Все",
  "Band": "Диапазон",
  "Cancel USSD": "Отменить USSD",
  "Carrier aggregation": "Агрегация несущих",
  "Cell on map": "Сота на карте",
  "Cell parameters": "Параметры соты",
  "Combined": "Совмещённое",
  "Connect": "Подключить",
  "Connected": "Подключено",
  "Connection": "Соединение",
  "Dial log": "Журнал дозвона",
  "live": "онлайн",
  "— waiting for connection log… —": "— ожидание журнала дозвона… —",
  "Copy to clipboard": "Копировать в буфер",
  "Delete": "Удалить",
  "Delete entire conversation": "Удалить всю переписку",
  "Delete failed": "Не удалось удалить",
  "Device info": "Об устройстве",
  "Disable all": "Снять все",
  "Disconnect": "Отключить",
  "Done": "Готово",
  "Enable all": "Выбрать все",
  "Error": "Ошибка",
  "Failed": "Не удалось",
  "Firmware": "Прошивка",
  "Gateway": "Шлюз",
  "Global Cell ID": "Глобальный Cell ID",
  "Hardware revision": "Ревизия оборудования",
  "LTE band-lock": "LTE: блокировка диапазонов",
  "Message": "Сообщение",
  "Model": "Модель",
  "Name": "Название",
  "Neighbour cells": "Соседние соты",
  "New conversation — enter a number above and a message below": "Новая переписка — введите номер сверху и сообщение снизу",
  "New message": "Новое сообщение",
  "New messages": "Новые сообщения",
  "No conversations": "Нет переписок",
  "Operator scan": "Поиск операторов",
  "Per-antenna (Rx0–3)": "По антеннам (Rx0–3)",
  "Phone number": "Номер телефона",
  "RAT mode": "Режим RAT",
  "Receive new SMS into this storage": "Принимать новые SMS в это хранилище",
  "Recipient required": "Укажите получателя",
  "Registration": "Регистрация",
  "Reply to menu": "Ответить в меню",
  "Reset modem": "Сброс модема",
  "Reset the modem? This drops the connection.": "Сбросить модем? Соединение прервётся.",
  "SIM & TTL": "SIM и TTL",
  "SIM slot": "Слот SIM",
  "Save & apply": "Сохранить и применить",
  "Save & apply band-lock? Connection may drop briefly.": "Сохранить и применить блокировку диапазонов? Соединение может ненадолго прерваться.",
  "Scan networks": "Искать сети",
  "Scan takes 1–2 min and briefly affects the connection.": "Поиск занимает 1–2 мин и кратко влияет на соединение.",
  "Select & delete": "Выбрать и удалить",
  "Select a conversation": "Выберите переписку",
  "Send": "Отправить",
  "Send a service code, e.g. *100#": "Отправьте сервисный код, напр. *100#",
  "Send failed": "Не удалось отправить",
  "Service codes": "Сервисные коды",
  "Session cancelled": "Сессия отменена",
  "Session time": "Время сессии",
  "Set": "Задать",
  "Signal": "Сигнал",
  "Signal quality": "Качество сигнала",
  "Signal strength": "Сила сигнала",
  "TTL in / out": "TTL вход / выход",
  "TTL rule saved, but flow offloading is enabled — offloaded connections bypass it. Disable “Software flow offloading” in Network → Firewall for the fix to take effect.": "TTL-правило сохранено, но включён flow offloading — оффлоаженные соединения его обходят. Отключите «Software flow offloading» в Network → Firewall, чтобы фикс заработал.",
  "TX power": "Мощность TX",
  "Tech": "Технология",
  "Temperature": "Температура",
  "To": "Кому",
  "Today": "Сегодня",
  "Traffic ↓ / ↑": "Трафик ↓ / ↑",
  "Type": "Тип",
  "Yesterday": "Вчера",
  "current": "текущая",
  "disconnected": "отключено",
  "eNB / Sector": "eNB / Сектор",
  "in": "вход",
  "messages": "сообщений",
  "no data": "нет данных",
  "no neighbours reported": "соседние соты не сообщены",
  "no networks": "сети не найдены",
  "open 4cells": "открыть 4cells",
  "out": "выход",
  "press scan": "нажмите «Искать»",
  "scanning…": "идёт поиск…",
  "selected": "выбрано",
  "session active": "сессия активна",
  "— modem console — pick a command above or type your own —": "— консоль модема — выберите команду сверху или введите свою —",
  // HELP-подсказки
  "RSRP — Reference Signal Received Power. The average power of the cell reference signals, the main indicator of signal strength. Closer to 0 is better. Excellent ≥ −80, poor < −100 dBm.": "RSRP — Reference Signal Received Power. Средняя мощность опорных сигналов соты, главный показатель силы сигнала. Ближе к 0 — лучше. Отлично ≥ −80, плохо < −100 dBm.",
  "RSRQ — Reference Signal Received Quality. Quality of the reference signal (RSRP relative to total power); accounts for interference and cell load. Excellent ≥ −10, poor < −20 dB.": "RSRQ — Reference Signal Received Quality. Качество опорного сигнала (RSRP к суммарной мощности), учитывает помехи и загрузку соты. Отлично ≥ −10, плохо < −20 dB.",
  "SINR — Signal to Interference plus Noise Ratio. Ratio of useful signal to interference and noise. Determines speed and stability. Excellent ≥ 20, poor < 0 dB.": "SINR — Signal to Interference plus Noise Ratio. Отношение полезного сигнала к помехам и шуму. Определяет скорость и стабильность. Отлично ≥ 20, плохо < 0 dB.",
  "RSSI — Received Signal Strength Indicator. Total received signal power, including the useful signal, interference and noise across the whole band.": "RSSI — Received Signal Strength Indicator. Суммарная мощность принимаемого сигнала, включая полезный сигнал, помехи и шум всей полосы.",
  "TX power — modem transmitter power (uplink). Appears only during active transmission; unavailable when idle (RRC idle).": "TX power — мощность передатчика модема (uplink). Появляется только при активной передаче; в простое (RRC idle) недоступна.",
  "Signal strength — an overall connection quality estimate in percent (per modem data).": "Сила сигнала — обобщённая оценка качества соединения в процентах (по данным модема).",
  "Per-antenna measurements: RSRP/RSRQ/SINR values for each receive path (Rx0–Rx3). The spread between antennas shows their balance and polarization.": "По-антенные измерения: значения RSRP/RSRQ/SINR для каждого приёмного тракта (Rx0–Rx3). Разброс между антеннами показывает их баланс и поляризацию.",
  "PCI — Physical Cell ID, the physical cell identifier (0–503). Helps tell neighbouring sectors apart.": "PCI — Physical Cell ID, физический идентификатор соты (0–503). Помогает различать соседние секторы.",
  "EARFCN — E-UTRA absolute radio-frequency channel number (LTE carrier). Uniquely defines the frequency and band.": "EARFCN — номер частотного канала E-UTRA (несущая LTE). Однозначно задаёт частоту и диапазон.",
  "Serving cell — the cell the modem is currently connected to. Marked with a star.": "Ведущая (serving) сота — та, к которой модем сейчас подключён. Отмечена звездой.",
  // AT-команды (описания)
  "— pick a command —": "— выберите команду —",
  "ATI — model and firmware": "ATI — модель и прошивка",
  "AT+QCCID — SIM card ICCID": "AT+QCCID — ICCID SIM-карты",
  "AT+CPIN? — SIM / PIN status": "AT+CPIN? — статус SIM / PIN",
  "AT+CSQ — signal level (RSSI)": "AT+CSQ — уровень сигнала (RSSI)",
  "AT+QRSRP — RSRP per antenna": "AT+QRSRP — RSRP по антеннам",
  "AT+QRSRQ — RSRQ per antenna": "AT+QRSRQ — RSRQ по антеннам",
  "AT+QSINR — SINR per antenna": "AT+QSINR — SINR по антеннам",
  "AT+QNWINFO — network: tech / band / channel": "AT+QNWINFO — сеть: технология / band / канал",
  'AT+QENG="servingcell" — serving cell': 'AT+QENG="servingcell" — ведущая сота',
  "AT+QCAINFO — carrier aggregation (CA)": "AT+QCAINFO — агрегация несущих (CA)",
  "AT+QTEMP — modem temperature": "AT+QTEMP — температура модема",
  "AT+COPS? — current operator": "AT+COPS? — текущий оператор",
  "AT+CEREG? — network registration": "AT+CEREG? — регистрация в сети",
  "AT+CGDCONT? — PDP contexts / APN": "AT+CGDCONT? — PDP-контексты / APN",
  "AT+QUIMSLOT? — active SIM slot": "AT+QUIMSLOT? — активный слот SIM",
  "AT+CFUN? — modem mode": "AT+CFUN? — режим модема",
  'AT+QNWPREFCFG="mode_pref" — preferred RAT': 'AT+QNWPREFCFG="mode_pref" — предпочтительный RAT',
  'AT+QNWPREFCFG="lte_band" — allowed LTE bands': 'AT+QNWPREFCFG="lte_band" — разрешённые LTE band',
  'AT+QNWPREFCFG="nr5g_band" — allowed NR bands': 'AT+QNWPREFCFG="nr5g_band" — разрешённые NR band',
  'AT+QCFG="usbnet" — USB net mode (0 QMI · 1 ECM · 2 MBIM · 3 RNDIS · 5 NCM)': 'AT+QCFG="usbnet" — режим USB-сети (0 QMI · 1 ECM · 2 MBIM · 3 RNDIS · 5 NCM)',
  'AT+QCFG="usbnet",0 — switch to QMI/RMNET (reboot)': 'AT+QCFG="usbnet",0 — переключить на QMI/RMNET (ребут)',
  'AT+QCFG="usbnet",1 — switch to ECM (reboot)': 'AT+QCFG="usbnet",1 — переключить на ECM (ребут)',
  'AT+QCFG="usbnet",2 — switch to MBIM (reboot)': 'AT+QCFG="usbnet",2 — переключить на MBIM (ребут)',
  'AT+QCFG="usbnet",3 — switch to RNDIS (reboot)': 'AT+QCFG="usbnet",3 — переключить на RNDIS (ребут)',
  'AT+QCFG="data_interface" — data path: 0 USB / 1 PCIe': 'AT+QCFG="data_interface" — канал данных: 0 USB / 1 PCIe',
  'AT+QCFG="data_interface",0,0 — data path USB (reboot)': 'AT+QCFG="data_interface",0,0 — канал данных USB (ребут)',
  'AT+QCFG="data_interface",1,0 — data path PCIe (reboot)': 'AT+QCFG="data_interface",1,0 — канал данных PCIe (ребут)',
  'AT+CFUN=1,1 — reboot modem (apply changes)': 'AT+CFUN=1,1 — перезагрузить модем (применить изменения)',
};

function esc(s) { return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"'); }
let po = 'msgid ""\nmsgstr ""\n"Project-Id-Version: luci-app-carmodem\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n"Language: ru\\n"\n"Plural-Forms: nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<12 || n%100>14) ? 1 : 2);\\n"\n';
const emitted = new Set();
function emit(id, tr) { if (emitted.has(id)) return; emitted.add(id); po += `\nmsgid "${esc(id)}"\nmsgstr "${esc(tr)}"\n`; }

const sorted = [...ids].sort();
const missing = [];
for (const id of sorted) { if (MAP[id] !== undefined) emit(id, MAP[id]); else missing.push(id); }
// меню-строки, которых нет среди _() в JS
for (const k of ["Modem", "Advanced"]) if (!ids.has(k)) emit(k, MAP[k]);

// .po-источник держим ВНЕ po/ (иначе luci.mk сделал бы отдельный пакет
// luci-i18n-carmodem-ru). Сборка (wsl-quick.sh) компилит его в root/ пакета ->
// один apk. Имя каталога = carmodem (по префиксу пути вьюх view/carmodem/*).
Deno.mkdirSync("luci-app-carmodem/translations", { recursive: true });
Deno.writeTextFileSync("luci-app-carmodem/translations/carmodem.ru.po", po);
console.log("msgid из JS:", ids.size, "| переведено:", emitted.size, "| без перевода:", missing.length);
console.log("\n=== БЕЗ ПЕРЕВОДА (ожидаем только аббревиатуры -> fallback на англ.) ===");
missing.forEach((s) => console.log("  ⋄ " + s));
// проверка: ключи MAP, которых НЕТ среди msgid (опечатка/несовпадение тире)
const orphan = Object.keys(MAP).filter((k) => !ids.has(k) && k !== "Modem" && k !== "Advanced");
console.log("\n=== КЛЮЧИ MAP без совпадения в JS (опечатки/тире) ===", orphan.length ? "" : "нет");
orphan.forEach((s) => console.log("  ✗ " + s));
