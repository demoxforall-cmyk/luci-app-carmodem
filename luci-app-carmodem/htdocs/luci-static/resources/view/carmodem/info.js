'use strict';
'require view';
'require poll';
'require dom';
'require carmodem';

// CarModem — экран «Modem Info» (главный дашборд, ТЗ 5.1).
// Опрос активного экрана 3 с (ТЗ 3.4). Недоступные поля -> «—»/N/A (FR-34).
// SPDX-License-Identifier: GPL-2.0

var cm = carmodem;

function na(v) { return cm.isNA(v) ? '—' : v; }

function kv(pairs) {
	var dl = E('dl', { 'class': 'cm-kv' });
	pairs.forEach(function(p) {
		if (p == null) return;
		dl.appendChild(E('dt', {}, p[0]));
		dl.appendChild(E('dd', {}, [ p[1] ]));
	});
	return dl;
}

// card(title, body, {span:2|3|6, icon:'name', color:'#..'})
function card(title, body, opts) {
	opts = opts || {};
	var cls = 'cm-card';
	if (opts.span === 6) cls += ' cm-wide';
	else if (opts.span === 3) cls += ' cm-c3';
	else if (opts.span === 2) cls += ' cm-c2';
	return E('div', { 'class': cls }, [
		E('h3', {}, [ opts.icon ? cm.icon(opts.icon, opts.color) : '', title ]),
		body
	]);
}

var ACC = { teal: '#1d9e75', purple: '#534ab7', pink: '#d4537e', blue: '#378add' };

return view.extend({
	handleSaveApply: null, handleSave: null, handleReset: null,

	load: function() {
		return Promise.all([
			L.resolveDefault(cm.rpc.getStatus(), {}),
			L.resolveDefault(cm.rpc.getSignal(), {}),
			L.resolveDefault(cm.rpc.getTelemetry(), {}),
			L.resolveDefault(cm.rpc.getNeighbours(), [])
		]);
	},

	render: function(data) {
		cm.injectCSS();
		var grid = E('div', { 'class': 'cm-grid' });
		this.update(grid, data);
		poll.add(L.bind(function() {
			return this.load().then(L.bind(this.update, this, grid));
		}, this), 3);
		return E('div', {}, [
			E('h2', {}, _('Status')),
			grid
		]);
	},

	update: function(grid, data) {
		var st = data[0] || {}, sig = data[1] || {}, tel = data[2] || {}, nb = data[3] || [];
		var sc = tel.servingcell || {}, ant = tel.antenna || {}, ca = tel.ca || [];
		var cards = [];

		var plmn = st.plmn || sc.plmn;
		var band = na(sc.band) + (cm.isNA(sc.bw_mhz) ? '' : ' · ' + sc.bw_mhz + ' MHz');
		var rsrp = cm.isNA(sig.rsrp) ? sc.rsrp : sig.rsrp;

		// --- HERO: оператор + статус + трафик/сессия + сила сигнала (FR-12/15) ---
		cards.push(E('div', { 'class': 'cm-card cm-wide cm-hero' }, [
			E('div', { 'class': 'cm-hero-l' }, [
				E('div', { 'class': 'cm-hero-op' }, [
					cm.icon('router', ACC.blue),
					E('span', { 'class': 'cm-hero-name' }, cm.operatorName(st.operator, plmn, st.sim_operator)),
					cm.connBadge(st.state, st.access_tech)
				]),
				E('div', { 'class': 'cm-hero-meta' }, [
					E('span', {}, 'PLMN ' + na(plmn)),
					E('span', { 'class': 'cm-up' }, '↓ ' + cm.fmtBytes(st.bytes_rx)),
					E('span', { 'class': 'cm-dn' }, '↑ ' + cm.fmtBytes(st.bytes_tx)),
					E('span', {}, cm.fmtDuration(st.duration))
				])
			]),
			E('div', { 'class': 'cm-hero-r' }, [
				cm.heroSignal(st.signal_quality, this.heroBands(ca, sc))
			])
		]));

		// --- Соединение (FR-12) — registration здесь ---
		cards.push(card(_('Connection'), kv([
			[ _('Registration'), na(st.registration) ],
			[ 'APN', na(st.apn) ],
			[ _('IP (WWAN)'), na(st.ipv4) + (cm.isNA(st.ipv6) ? '' : ' / ' + st.ipv6) ],
			[ _('Gateway'), na(st.gw4) ],
			[ 'DNS', na(st.dns1) + (cm.isNA(st.dns2) ? '' : ', ' + st.dns2) ],
			[ _('Session time'), cm.fmtDuration(st.duration) ],
			[ _('Traffic ↓ / ↑'), cm.fmtBytes(st.bytes_rx) + ' / ' + cm.fmtBytes(st.bytes_tx) ]
		]), { span: 2, icon: 'plug', color: ACC.teal }));

		// --- Информация об устройстве (FR-22) — с Firmware/HW, без IMSI ---
		cards.push(card(_('Device info'), kv([
			[ _('Model'), [ st.manufacturer, st.model ].filter(function(x) { return !cm.isNA(x); }).join(' ') || '—' ],
			[ _('Firmware'), na(st.firmware) ],
			[ _('Hardware revision'), na(st.hw_revision) ],
			[ 'IMEI', cm.copyField(st.imei) ],
			[ 'ICCID', cm.copyField(st.iccid) ],
			[ _('Phone number'), cm.copyField(st.phone) ],
			[ _('Temperature'), this.temp(tel.temp) ]
		]), { span: 2, icon: 'cpu', color: ACC.purple }));

		// --- Параметры соты (FR-13). TA эта прошивка через QENG не отдаёт. ---
		var mapUrl = cm.cellMapUrl(sc.mcc, sc.mnc, sc.enb, sc.tac, sc.rat);
		cards.push(card(_('Cell parameters'), kv([
			[ _('Global Cell ID'), na(sc.cell_id) + ' (0x' + na(sc.cell_id_raw) + ')' ],
			[ _('eNB / Sector'), na(sc.enb) + ' / ' + na(sc.sector) ],
			[ 'MCC / MNC', na(sc.mcc) + ' / ' + na(sc.mnc) ],
			[ 'TAC', na(sc.tac) ],
			[ 'PCI', na(sc.pci) ],
			[ 'CQI', na(sc.cqi) ],
			mapUrl ? [ _('Cell on map'), E('a', { 'href': mapUrl, 'target': '_blank', 'rel': 'noopener', 'class': 'cm-maplink' }, [ cm.icon('cell'), _('open 4cells') ]) ] : null
		]), { span: 2, icon: 'cell', color: ACC.pink }));

		// --- Качество сигнала (FR-15): бары + %, цвета раздела 7 ---
		var vRsrp = rsrp;
		var vRsrq = cm.isNA(sig.rsrq) ? sc.rsrq : sig.rsrq;
		var vSinr = cm.isNA(sig.sinr) ? sc.sinr : sig.sinr;
		var vRssi = cm.isNA(sig.rssi) ? sc.rssi : sig.rssi;
		cards.push(card(_('Signal quality'), E('div', { 'class': 'cm-signal' }, [
			cm.metricRow('rsrp', vRsrp, 'dBm'),
			cm.metricRow('rsrq', vRsrq, 'dB'),
			cm.metricRow('sinr', vSinr, 'dB'),
			cm.metricRow('rssi', vRssi, 'dBm'),
			E('div', { 'class': 'cm-mrow cm-mrow-plain' }, [
				E('span', { 'class': 'cm-mname', 'title': cm.helpText('tx_power') }, _('TX power')),
				E('span', { 'class': 'cm-mval' }, cm.fmt(sc.tx_power, 'dBm'))
			])
		]), { span: 3, icon: 'signal', color: ACC.teal }));

		// --- По-антенные Rx0-3 (FR-16) ---
		cards.push(card(_('Per-antenna (Rx0–3)'), this.antennaTable(ant),
			{ span: 3, icon: 'antenna', color: ACC.blue }));

		// --- Несущие: ведущая (★) + агрегация (FR-14 + FR-18) ---
		cards.push(card(_('Carrier aggregation'), this.caTable(ca, sc),
			{ span: 6, icon: 'stack', color: ACC.pink }));

		// --- 5G NR (FR-19) — только при наличии NR ---
		if (!cm.isNA(sig.nr_rsrp) || !cm.isNA(sig.nr_rsrq) || !cm.isNA(sig.nr_sinr))
			cards.push(card(_('5G NR'), kv([
				[ 'NR RSRP', cm.metricSpan('rsrp', sig.nr_rsrp, 'dBm') ],
				[ 'NR RSRQ', cm.metricSpan('rsrq', sig.nr_rsrq, 'dB') ],
				[ 'NR SINR', cm.metricSpan('sinr', sig.nr_sinr, 'dB') ]
			]), { span: 6, icon: 'signal', color: ACC.teal }));

		// --- Соседние соты (FR-21); ведущая (★) — сверху ---
		cards.push(card(_('Neighbour cells'), this.neighbourTable(nb),
			{ span: 6, icon: 'grid', color: ACC.blue }));

		dom.content(grid, cards);
	},

	// Бенды агрегации (напр. B7+B7+B3+B3) пилюлями в стиле таблицы CA
	// (PCC — акцентная, SCC — нейтральная).
	heroBands: function(ca, sc) {
		var rows = (ca && ca.length) ? ca : (cm.isNA(sc.band) ? [] : [ { type: 'PCC', band: sc.band } ]);
		return rows.map(function(c) {
			var b = ('' + (c.band || '')).replace(/LTE BAND /, 'B').replace(/NR5G BAND /, 'n');
			return cm.pill(b, c.type === 'PCC' ? 'accent' : 'plain');
		});
	},

	antennaTable: function(ant) {
		var rsrp = ant.rsrp || {}, rsrq = ant.rsrq || {}, sinr = ant.sinr || {};
		var rows = [ E('tr', {}, [
			E('th', { 'title': cm.helpText('antenna') }, 'Rx'),
			E('th', { 'title': cm.helpText('rsrp') }, 'RSRP'),
			E('th', { 'title': cm.helpText('rsrq') }, 'RSRQ'),
			E('th', { 'title': cm.helpText('sinr') }, 'SINR')
		]) ];
		for (var i = 0; i < 4; i++) {
			rows.push(E('tr', {}, [
				E('td', {}, 'Rx' + i),
				E('td', {}, [ cm.metricSpan('rsrp', rsrp['rx' + i], 'dBm') ]),
				E('td', {}, [ cm.metricSpan('rsrq', rsrq['rx' + i], 'dB') ]),
				E('td', {}, [ cm.metricSpan('sinr', sinr['rx' + i], 'dB') ])
			]));
		}
		return E('table', { 'class': 'cm-table' }, rows);
	},

	// Ведущая частота (★, PCC) + компоненты CA одной таблицей (FR-14 + FR-18).
	caTable: function(ca, sc) {
		ca = (ca || []).slice();
		if (!ca.length && sc && !cm.isNA(sc.band))
			ca = [ { type: 'PCC', band: sc.band, earfcn: sc.earfcn, pci: sc.pci,
			         bw_mhz: sc.bw_mhz, rsrp: sc.rsrp, sinr: sc.sinr } ];
		if (!ca.length) return E('em', {}, _('no data'));
		ca.sort(function(a, b) { return (b.type == 'PCC') - (a.type == 'PCC'); });
		var rows = [ E('tr', {}, [
			E('th', { 'title': cm.helpText('serving') }, ''),
			E('th', {}, _('Type')), E('th', {}, _('Band')),
			E('th', { 'title': cm.helpText('earfcn') }, 'EARFCN'),
			E('th', { 'title': cm.helpText('pci') }, 'PCI'),
			E('th', {}, 'BW'),
			E('th', { 'title': cm.helpText('rsrp') }, 'RSRP'),
			E('th', { 'title': cm.helpText('sinr') }, 'SINR')
		]) ];
		ca.forEach(function(c) {
			var primary = (c.type == 'PCC');
			var bw = cm.isNA(c.bw_mhz) ? cm.caBwMhz(c.bw) : c.bw_mhz;
			rows.push(E('tr', primary ? { 'class': 'cm-primary' } : {}, [
				E('td', {}, primary ? '★' : ''),
				E('td', {}, na(c.type)),
				E('td', {}, [ cm.pill(c.band ? ('' + c.band).replace(/LTE BAND /, 'B').replace(/NR5G BAND /, 'n') : '', primary ? 'accent' : 'plain') ]),
				E('td', {}, na(c.earfcn)),
				E('td', {}, na(c.pci)), E('td', {}, cm.fmt(bw, 'MHz')),
				E('td', {}, [ cm.metricSpan('rsrp', c.rsrp, 'dBm') ]),
				E('td', {}, [ cm.metricSpan('sinr', c.sinr, 'dB') ])
			]));
		});
		return E('table', { 'class': 'cm-table cm-celltbl' }, rows);
	},

	neighbourTable: function(nb) {
		if (!nb || !nb.length) return E('em', {}, _('no neighbours reported'));
		nb = nb.slice().sort(function(a, b) {
			return (b.serving == 'yes') - (a.serving == 'yes');
		});
		var rows = [ E('tr', {}, [
			E('th', { 'title': cm.helpText('serving') }, ''),
			E('th', {}, _('Type')),
			E('th', { 'title': cm.helpText('earfcn') }, 'EARFCN'),
			E('th', { 'title': cm.helpText('pci') }, 'PCI'),
			E('th', { 'title': cm.helpText('rsrp') }, 'RSRP'),
			E('th', { 'title': cm.helpText('rsrq') }, 'RSRQ')
		]) ];
		nb.forEach(function(c) {
			var serving = (c.serving == 'yes');
			rows.push(E('tr', serving ? { 'class': 'cm-primary' } : {}, [
				E('td', {}, serving ? '★' : ''),
				E('td', {}, na(c.type)), E('td', {}, na(c.earfcn)), E('td', {}, na(c.pci)),
				E('td', {}, [ cm.metricSpan('rsrp', c.rsrp, 'dBm') ]),
				E('td', {}, [ cm.metricSpan('rsrq', c.rsrq, 'dB') ])
			]));
		});
		return E('table', { 'class': 'cm-table cm-celltbl' }, rows);
	},

	temp: function(t) {
		if (!t) return '—';
		var keys = Object.keys(t);
		if (!keys.length) return '—';
		var max = null;
		keys.forEach(function(k) { if (t[k] != null && (max == null || t[k] > max)) max = t[k]; });
		return cm.fmt(max, '°C');
	}
});
