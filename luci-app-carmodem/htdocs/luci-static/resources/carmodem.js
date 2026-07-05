'use strict';
'require baseclass';
'require rpc';

// CarModem — общий слой фронтенда: RPC к ubus-объекту carmodem,
// цветовые пороги качества (ТЗ раздел 7), форматирование и N/A-рендеринг.
// SPDX-License-Identifier: GPL-2.0

// Версия ассетов: добавляется в URL CSS как cache-buster. LuCI кэширует
// ресурсы по `?v=<версия_luci>`, которая между нашими сборками не меняется —
// поэтому браузер не перечитывает обновлённый carmodem.css. Бампить вместе с
// PKG_VERSION при изменении стилей/вьюх.
var CM_VER = '4.0';

var callGetStatus     = rpc.declare({ object: 'carmodem', method: 'get_status' });
var callGetDashboard  = rpc.declare({ object: 'carmodem', method: 'get_dashboard' });
var callGetConn       = rpc.declare({ object: 'carmodem', method: 'get_conn' });
var callGetConnLog    = rpc.declare({ object: 'carmodem', method: 'get_conn_log' });
var callGetSignal     = rpc.declare({ object: 'carmodem', method: 'get_signal' });
var callGetTelemetry  = rpc.declare({ object: 'carmodem', method: 'get_telemetry' });
// ubus возвращает объект; expect распаковывает массив -> фронтенд получает list
var callGetNeighbours = rpc.declare({ object: 'carmodem', method: 'get_neighbours', expect: { cells: [] } });
var callGetLocation   = rpc.declare({ object: 'carmodem', method: 'get_location' });
// без expect: метод асинхронный, возвращает {scanning:true} либо {networks:[...]}
var callScanOperators = rpc.declare({ object: 'carmodem', method: 'scan_operators' });
var callGetBands      = rpc.declare({ object: 'carmodem', method: 'get_bands' });
var callGetSms        = rpc.declare({ object: 'carmodem', method: 'get_sms', expect: { messages: [] } });
var callGetSmsSig     = rpc.declare({ object: 'carmodem', method: 'get_sms_sig' });
var callGetSmsStorage = rpc.declare({ object: 'carmodem', method: 'get_sms_storage' });
var callSetSmsStorage = rpc.declare({ object: 'carmodem', method: 'set_sms_storage', params: [ 'storage' ] });
var callGetSmsStorageFill = rpc.declare({ object: 'carmodem', method: 'get_sms_storage_fill' });
var callDeleteSms     = rpc.declare({ object: 'carmodem', method: 'delete_sms', params: [ 'ids' ] });
var callUssdRespond   = rpc.declare({ object: 'carmodem', method: 'ussd_respond', params: [ 'response' ] });
var callUssdCancel    = rpc.declare({ object: 'carmodem', method: 'ussd_cancel' });
var callSendAt        = rpc.declare({ object: 'carmodem', method: 'send_at',  params: [ 'cmd' ] });
var callSendUssd      = rpc.declare({ object: 'carmodem', method: 'send_ussd', params: [ 'code' ] });
var callSendSms       = rpc.declare({ object: 'carmodem', method: 'send_sms', params: [ 'to', 'text' ] });
var callSetBand       = rpc.declare({ object: 'carmodem', method: 'set_band', params: [ 'bands' ] });
var callSetRat        = rpc.declare({ object: 'carmodem', method: 'set_rat',  params: [ 'mode' ] });
var callSetSim        = rpc.declare({ object: 'carmodem', method: 'set_sim',  params: [ 'slot' ] });
var callSetTtl        = rpc.declare({ object: 'carmodem', method: 'set_ttl',  params: [ 'in', 'out' ] });
var callDial          = rpc.declare({ object: 'carmodem', method: 'dial',     params: [ 'up' ] });
var callResetModem    = rpc.declare({ object: 'carmodem', method: 'reset_modem' });
var callGetWatchdog   = rpc.declare({ object: 'carmodem', method: 'get_watchdog' });
var callSetWatchdog   = rpc.declare({ object: 'carmodem', method: 'set_watchdog', params: [ 'enabled', 'interval', 'ping_hosts', 'l1_reconnect', 'l2_reset', 'l3_reboot', 'cooldown_reset', 'allow_reboot', 'recovery_service', 'wan_netdev', 'wan_iface' ] });
var callWatchdogTest  = rpc.declare({ object: 'carmodem', method: 'watchdog_test' });
var callWatchdogClear = rpc.declare({ object: 'carmodem', method: 'watchdog_clear' });

// Пороги: [зелёный, жёлто-зелёный, жёлтый/оранж]; ниже последнего -> красный.
// Направление 'high' = больше лучше (по умолчанию для dBm/dB здесь).
var THRESHOLDS = {
	rsrp: [ -80, -90, -100 ],
	rsrq: [ -10, -15, -20 ],
	sinr: [ 20, 13, 0 ],
	rssi: [ -65, -85, -95 ]
};

// Диапазон [0%, 100%] для перевода метрики в проценты (визуализация бара).
var PCT = {
	rsrp: [ -120, -70 ],
	rsrq: [ -20, -3 ],
	sinr: [ -5, 25 ],
	rssi: [ -110, -50 ]
};

// Подробные пояснения параметров (тултипы при наведении), i18n.
var HELP = {
	rsrp: _('RSRP — Reference Signal Received Power. The average power of the cell reference signals, the main indicator of signal strength. Closer to 0 is better. Excellent ≥ −80, poor < −100 dBm.'),
	rsrq: _('RSRQ — Reference Signal Received Quality. Quality of the reference signal (RSRP relative to total power); accounts for interference and cell load. Excellent ≥ −10, poor < −20 dB.'),
	sinr: _('SINR — Signal to Interference plus Noise Ratio. Ratio of useful signal to interference and noise. Determines speed and stability. Excellent ≥ 20, poor < 0 dB.'),
	rssi: _('RSSI — Received Signal Strength Indicator. Total received signal power, including the useful signal, interference and noise across the whole band.'),
	tx_power: _('TX power — modem transmitter power (uplink). Appears only during active transmission; unavailable when idle (RRC idle).'),
	strength: _('Signal strength — an overall connection quality estimate in percent (per modem data).'),
	antenna: _('Per-antenna measurements: RSRP/RSRQ/SINR values for each receive path (Rx0–Rx3). The spread between antennas shows their balance and polarization.'),
	pci: _('PCI — Physical Cell ID, the physical cell identifier (0–503). Helps tell neighbouring sectors apart.'),
	earfcn: _('EARFCN — E-UTRA absolute radio-frequency channel number (LTE carrier). Uniquely defines the frequency and band.'),
	serving: _('Serving cell — the cell the modem is currently connected to. Marked with a star.')
};

// Инлайн-SVG иконки (outline, stroke=currentColor — адаптируются к теме).
var ICONS = {
	router:  '<path d="M3 13h18v7H3z"/><path d="M7 16.5h.01M11 16.5h3"/><path d="M16 13V8a3 3 0 0 1 3-3"/><path d="M13 13V9a3 3 0 0 1 3-3"/>',
	plug:    '<path d="M7 12l5 5l-1.5 1.5a3.5 3.5 0 0 1-5-5z"/><path d="M17 12l-5-5l1.5-1.5a3.5 3.5 0 0 1 5 5z"/><path d="M3 21l2.5-2.5M18.5 5.5L21 3M11 13l-1.5 1.5M14 16l-1.5 1.5"/>',
	cpu:     '<rect x="5" y="5" width="14" height="14" rx="1"/><rect x="9" y="9" width="6" height="6"/><path d="M3 10h2M3 14h2M10 3v2M14 3v2M19 10h2M19 14h2M10 19v2M14 19v2"/>',
	cell:    '<path d="M18.4 19.4a9 9 0 1 0-12.8 0"/><path d="M15.5 16.5a5 5 0 1 0-7 0"/><circle cx="12" cy="13" r="1"/><path d="M12 13v8"/>',
	signal:  '<path d="M12 12v.01"/><path d="M14.8 9.2a4 4 0 0 1 0 5.6M17.7 6.3a8 8 0 0 1 0 11.4"/><path d="M9.2 14.8a4 4 0 0 1 0-5.6M6.3 17.7a8 8 0 0 1 0-11.4"/>',
	antenna: '<path d="M6 18l6-6 6 6"/><path d="M4 10a8 8 0 0 1 16 0"/><path d="M7.5 11a4.5 4.5 0 0 1 9 0"/>',
	stack:   '<path d="M12 4l-8 4 8 4 8-4z"/><path d="M4 12l8 4 8-4M4 16l8 4 8-4"/>',
	grid:    '<circle cx="6" cy="6" r="1"/><circle cx="12" cy="6" r="1"/><circle cx="18" cy="6" r="1"/><circle cx="6" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="18" cy="12" r="1"/><circle cx="6" cy="18" r="1"/><circle cx="12" cy="18" r="1"/><circle cx="18" cy="18" r="1"/>',
	sim:     '<path d="M9 3h6l4 4v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><rect x="9" y="13" width="6" height="5" rx="1"/><path d="M12 13v5M9 15.5h6"/>',
	hash:    '<path d="M5 9h14M5 15h14M11 4L9 20M15 4l-2 16"/>',
	trash:   '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-13M9 7V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v3"/>',
	send:    '<path d="M10 14l11-11M21 3l-6.5 18a.55.55 0 0 1-1 0L10 14l-7-3.5a.55.55 0 0 1 0-1z"/>',
	user:    '<circle cx="12" cy="8" r="4"/><path d="M6 21v-1a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v1"/>',
	pencil:  '<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3z"/><path d="M13.5 6.5l3 3"/>',
	check:   '<path d="M5 12l5 5L20 7"/>',
	x:       '<path d="M6 6l12 12M18 6L6 18"/>',
	chat:    '<path d="M21 15a2 2 0 0 1-2 2H8l-4 4V5a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2z"/>',
	checks:  '<path d="M2 13l4 4L14 7"/><path d="M11 16l1.5 1.5L22 7"/>',
	search:  '<circle cx="11" cy="11" r="7"/><path d="M21 21l-4.35-4.35"/>',
	terminal:'<rect x="3" y="5" width="18" height="14" rx="1.5"/><path d="M7 9l3 3-3 3M13 15h4"/>',
	alert:   '<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17h.01"/>',
	refresh: '<path d="M4 12a8 8 0 0 1 13.7-5.6L20 8M20 4v4h-4"/><path d="M20 12a8 8 0 0 1-13.7 5.6L4 16M4 20v-4h4"/>',
	star:    '<path d="M12 4l2.5 5.1 5.6.8-4.05 3.95.96 5.6L12 16.9l-5.01 2.65.96-5.6L3.9 9.9l5.6-.8z"/>',
	activity:'<path d="M3 12h4l3 8 4-16 3 8h4"/>'
};

return baseclass.extend({
	rpc: {
		getStatus: callGetStatus, getDashboard: callGetDashboard, getConn: callGetConn, getConnLog: callGetConnLog, getSignal: callGetSignal,
		getTelemetry: callGetTelemetry,
		getNeighbours: callGetNeighbours,
		getLocation: callGetLocation,
		scanOperators: callScanOperators, getBands: callGetBands,
		getSms: callGetSms, getSmsSig: callGetSmsSig, deleteSms: callDeleteSms,
		getSmsStorage: callGetSmsStorage, setSmsStorage: callSetSmsStorage,
		getSmsStorageFill: callGetSmsStorageFill,
		sendAt: callSendAt,
		sendUssd: callSendUssd, ussdRespond: callUssdRespond, ussdCancel: callUssdCancel,
		sendSms: callSendSms,
		setBand: callSetBand, setRat: callSetRat, setSim: callSetSim,
		setTtl: callSetTtl, dial: callDial,
		resetModem: callResetModem,
		getWatchdog: callGetWatchdog, setWatchdog: callSetWatchdog,
		watchdogTest: callWatchdogTest, watchdogClear: callWatchdogClear
	},

	// Класс качества 'cm-q1'(отл)..'cm-q4'(плохо) по метрике и значению.
	quality: function(metric, val) {
		var t = THRESHOLDS[metric];
		if (t == null || val == null || isNaN(val))
			return 'cm-na';
		val = Number(val);
		if (val >= t[0]) return 'cm-q1';
		if (val >= t[1]) return 'cm-q2';
		if (val >= t[2]) return 'cm-q3';
		return 'cm-q4';
	},

	// Значение или прочерк (ТЗ FR-34): отсутствующее -> «N/A», не пропадает.
	isNA: function(v) {
		return (v == null || v === '' || v === '-' || (typeof v == 'number' && isNaN(v)));
	},

	// Форматирование числа с единицей; N/A -> «—».
	fmt: function(v, unit) {
		if (this.isNA(v)) return '—';
		return (unit != null) ? (v + ' ' + unit) : ('' + v);
	},

	// <span> со значением, единицей и классом качества (для цветовой индикации).
	metricSpan: function(metric, v, unit) {
		var cls = this.quality(metric, v);
		return E('span', { 'class': 'cm-metric ' + cls }, this.fmt(v, unit));
	},

	// Текст подсказки параметра (тултип).
	helpText: function(key) { return HELP[key] || ''; },

	// Метрика -> проценты [0..100] для визуализации бара; N/A -> null.
	signalPct: function(metric, val) {
		var r = PCT[metric];
		if (!r || this.isNA(val)) return null;
		var p = Math.round((Number(val) - r[0]) / (r[1] - r[0]) * 100);
		return Math.max(0, Math.min(100, p));
	},

	// Строка метрики: имя (с тултипом) + значение + % + цветной прогресс-бар.
	metricRow: function(metric, val, unit, name) {
		var cls = this.quality(metric, val);
		var pct = this.signalPct(metric, val);
		return E('div', { 'class': 'cm-mrow' }, [
			E('span', { 'class': 'cm-mname', 'title': this.helpText(metric) }, name || metric.toUpperCase()),
			E('span', { 'class': 'cm-mval ' + cls }, this.fmt(val, unit)),
			E('span', { 'class': 'cm-mpct' }, pct == null ? '' : (pct + '%')),
			E('div', { 'class': 'cm-bar' }, [
				E('div', { 'class': 'cm-bar-fill ' + cls, 'style': 'width:' + (pct == null ? 0 : pct) + '%' })
			])
		]);
	},

	// Крупный индикатор силы сигнала в процентах (по signal-quality модема, FR-15).
	strengthGauge: function(pct) {
		pct = this.isNA(pct) ? null : Math.max(0, Math.min(100, Number(pct)));
		var cls = pct == null ? 'cm-na' : (pct >= 66 ? 'cm-q1' : (pct >= 40 ? 'cm-q3' : 'cm-q4'));
		return E('div', { 'class': 'cm-strength' }, [
			E('div', { 'class': 'cm-strength-top' }, [
				E('span', { 'class': 'cm-strength-label', 'title': this.helpText('strength') }, _('Signal strength')),
				E('span', { 'class': 'cm-strength-val ' + cls }, pct == null ? '—' : (pct + '%'))
			]),
			E('div', { 'class': 'cm-bar cm-bar-lg' }, [
				E('div', { 'class': 'cm-bar-fill ' + cls, 'style': 'width:' + (pct == null ? 0 : pct) + '%' })
			])
		]);
	},

	// Кнопка «скопировать в буфер» рядом со значением (IMEI/номер и т.п.).
	copyButton: function(value) {
		if (this.isNA(value)) return '';
		var btn = E('button', { 'class': 'cm-copy', 'type': 'button', 'title': _('Copy to clipboard') }, '⧉');
		btn.addEventListener('click', function(ev) {
			ev.preventDefault();
			var txt = '' + value;
			if (navigator.clipboard && navigator.clipboard.writeText)
				navigator.clipboard.writeText(txt);
			else {
				var ta = document.createElement('textarea');
				ta.value = txt; document.body.appendChild(ta); ta.select();
				try { document.execCommand('copy'); } catch (e) {}
				document.body.removeChild(ta);
			}
			var prev = btn.textContent;
			btn.textContent = '✓'; btn.classList.add('cm-copied');
			window.setTimeout(function() { btn.textContent = prev; btn.classList.remove('cm-copied'); }, 1200);
		});
		return btn;
	},

	// Значение + кнопка копирования одним span (для IMEI/ICCID/номера).
	copyField: function(value) {
		return E('span', { 'class': 'cm-copyfield' }, [ this.fmt(value), this.copyButton(value) ]);
	},

	// Инлайн-SVG иконка по имени (цвет наследуется; color — акцент).
	icon: function(name, color) {
		var s = E('span', { 'class': 'cm-ico' });
		if (color) s.style.color = color;
		s.innerHTML = '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' + (ICONS[name] || '') + '</svg>';
		return s;
	},

	// Пилюля-бейдж: kind = 'accent' | 'plain' | 'q1'..'q4'.
	pill: function(text, kind) {
		if (this.isNA(text)) return '—';
		return E('span', { 'class': 'cm-pill2 cm-pill-' + (kind || 'plain') }, '' + text);
	},

	// Бейдж состояния соединения с пульсом (FR-12).
	connBadge: function(state, tech) {
		var on = (('' + state).toLowerCase() === 'connected');
		var txt = (on ? _('Connected') : (this.isNA(state) ? _('disconnected') : state));
		if (!this.isNA(tech)) txt += ' · ' + ('' + tech).toUpperCase();
		return E('span', { 'class': 'cm-badge ' + (on ? 'cm-on' : 'cm-off') }, [
			E('span', { 'class': 'cm-dot' + (on ? ' cm-pulse' : '') }, ''),
			txt
		]);
	},

	// Вертикальные полоски-«антенна» силы сигнала (5 шт., закрашены по %).
	signalBars: function(pct) {
		var cls = this.isNA(pct) ? 'cm-na' : (pct >= 66 ? 'cm-q1' : (pct >= 40 ? 'cm-q3' : 'cm-q4'));
		var n = this.isNA(pct) ? 0 : Math.max(1, Math.ceil(Number(pct) / 20));
		var bars = [];
		for (var i = 1; i <= 5; i++)
			bars.push(E('span', { 'class': 'cm-sbar' + (i <= n ? ' cm-on' : '') }, ''));
		return E('div', { 'class': 'cm-sbars ' + cls }, bars);
	},

	// Индикатор силы сигнала для hero: % + горизонтальный бар, под ним — sub
	// (бенды агрегации пилюлями).
	heroSignal: function(pct, sub) {
		pct = this.isNA(pct) ? null : Math.max(0, Math.min(100, Number(pct)));
		var cls = pct == null ? 'cm-na' : (pct >= 66 ? 'cm-q1' : (pct >= 40 ? 'cm-q3' : 'cm-q4'));
		return E('div', { 'class': 'cm-herosig' }, [
			E('div', { 'class': 'cm-herosig-top' }, [
				E('span', { 'class': 'cm-herosig-lbl', 'title': this.helpText('strength') }, _('Signal')),
				E('span', { 'class': 'cm-herosig-val ' + cls }, pct == null ? '—' : (pct + '%'))
			]),
			E('div', { 'class': 'cm-bar cm-bar-lg' }, [
				E('div', { 'class': 'cm-bar-fill ' + cls, 'style': 'width:' + (pct == null ? 0 : pct) + '%' })
			]),
			sub ? E('div', { 'class': 'cm-herosig-sub' }, sub) : ''
		]);
	},

	// Подмешать css модуля один раз.
	injectCSS: function() {
		if (document.getElementById('cm-style')) return;
		var l = E('link', {
			'id': 'cm-style', 'rel': 'stylesheet', 'type': 'text/css',
			'href': L.resource('view/carmodem/carmodem.css') + '?v=' + CM_VER
		});
		document.head.appendChild(l);
	},

	// Имя оператора: имя из MM, если осмысленное; иначе имя с SIM; иначе
	// резолв по PLMN из таблицы (MM часто отдаёт «250 02»). FR-12.
	operatorName: function(operator, plmn, simName) {
		if (operator && !this.isNA(operator) && !/^\d[\d\s]*$/.test(operator))
			return operator;
		if (simName && !this.isNA(simName) && !/^\d[\d\s]*$/.test(simName))
			return simName;
		var P = {
			'25001': 'MTS', '25002': 'MegaFon', '25099': 'Beeline',
			'25020': 'Tele2', '25011': 'Yota', '25017': 'MOTIV',
			'25027': 'Letai', '25039': 'Rostelecom', '25050': 'Tinkoff Mobile',
			'25062': 'Tinkoff Mobile', '25035': 'MOTIV'
		};
		return P[plmn] || operator || plmn;
	},

	// QCAINFO bandwidth (число RB LTE) -> МГц. Неизвестное -> null.
	caBwMhz: function(rb) {
		if (this.isNA(rb)) return null;
		var M = { 6: '1.4', 15: '3', 25: '5', 50: '10', 75: '15', 100: '20' };
		return M[rb] != null ? M[rb] : null;
	},

	// Байты -> человекочитаемо (B/KB/MB/GB). N/A -> «—».
	fmtBytes: function(v) {
		if (this.isNA(v)) return '—';
		v = Number(v);
		var u = [ 'B', 'KB', 'MB', 'GB', 'TB' ], i = 0;
		while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
		return (i === 0 ? v : v.toFixed(2)) + ' ' + u[i];
	},

	// Секунды -> «Xd HH:MM:SS» / «HH:MM:SS». N/A -> «—».
	fmtDuration: function(s) {
		if (this.isNA(s)) return '—';
		s = Math.floor(Number(s));
		var d = Math.floor(s / 86400); s %= 86400;
		var h = Math.floor(s / 3600);  s %= 3600;
		var m = Math.floor(s / 60),  sec = s % 60;
		function p(n) { return (n < 10 ? '0' : '') + n; }
		return (d > 0 ? d + 'd ' : '') + p(h) + ':' + p(m) + ':' + p(sec);
	},

	// Хранилище SMS: sm (SIM) / me (память модема) -> человекочитаемо.
	storageLabel: function(s) {
		if (s === 'sm') return _('SIM');
		if (s === 'me') return _('Modem');
		return s || '—';
	},

	// Технология -> код 4cells (2G=1, 3G=2, 4G=3, 5G=4).
	techCode: function(rat) {
		var r = ('' + (rat || '')).toLowerCase();
		if (/nr|5g/.test(r)) return 4;
		if (/lte|4g/.test(r)) return 3;
		if (/umts|wcdma|hspa|3g/.test(r)) return 2;
		if (/gsm|edge|gprs|2g/.test(r)) return 1;
		return 3;
	},

	// Deep-link на карту покрытия 4cells по конкретной соте (ТЗ FR-12/FR-33).
	// Формат: plmn=MCC(3)+MNC(3), tech=код, num=eNB, lac=TAC(дес.).
	cellMapUrl: function(mcc, mnc, enb, tac, rat) {
		if (this.isNA(mcc) || this.isNA(enb)) return null;
		function pad3(v) { v = '' + v; while (v.length < 3) v = '0' + v; return v; }
		var u = 'https://4cells.ru/?plmn=' + pad3(mcc) + pad3(mnc) +
		        '&tech=' + this.techCode(rat) + '&num=' + enb;
		if (!this.isNA(tac)) u += '&lac=' + tac;
		return u;
	}
});
