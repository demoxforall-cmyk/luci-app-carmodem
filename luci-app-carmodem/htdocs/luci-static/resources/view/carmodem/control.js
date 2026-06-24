'use strict';
'require view';
'require ui';
'require dom';
'require poll';
'require carmodem';

// CarModem — «Расширенная панель» (управление, ТЗ 4). Дизайн «Console RF»:
// приборная панель — LED-чипы диапазонов, моноширинные регистры/счётчики,
// сегментники, терминальная AT-консоль. Всё на currentColor/color-mix (одна
// таблица стилей на светлую и тёмную тему). SPDX-License-Identifier: GPL-2.0

var cm = carmodem;

// Сетки диапазонов (ТЗ FR-5)
var LTE_BANDS = [ 1,2,3,4,5,7,8,12,13,14,17,18,19,20,25,26,28,29,30,32,38,39,40,41,42,43,46,48,66,71 ];
var NR_BANDS  = [ 1,2,3,5,7,8,12,20,25,28,38,40,41,48,66,71,77,78,79 ];

function confirmDanger(msg) { return Promise.resolve(window.confirm(msg)); }

return view.extend({
	// глушим стандартный CBI-футер LuCI (Save & Apply / Save / Reset) — страница не
	// форма, у каждого параметра своя кнопка (Apply RAT / Set / Save & apply)
	handleSaveApply: null, handleSave: null, handleReset: null,

	load: function() {
		// текущие активные диапазоны — чтобы зажечь LED активных чипов
		return L.resolveDefault(cm.rpc.getBands(), {});
	},

	render: function(bands) {
		cm.injectCSS();
		bands = bands || {};
		var lteAct = (bands.lte || '').split(',');
		var nrAct  = (bands.nr  || '').split(',');
		var tree = E('div', { 'class': 'cm-adv' }, [
			E('h2', {}, _('Advanced settings')),
			E('div', { 'class': 'cm-grid' }, [
				this.ratCard(),
				this.simTtlCard(),
				this.connectionCard(),
				this.logCard(),                        // фрейм журнала (скрыт), выше band-lock
				this.bandCard(_('LTE band-lock'), 'B', LTE_BANDS, lteAct, ''),
				this.bandCard(_('5G NR band-lock'), 'n', NR_BANDS, nrAct, 'cm-band-nr'),
				this.scanCard(),
				this.atConsoleCard()
			])
		]);
		poll.add(L.bind(this.pollConn, this), 1);   // живой статус Connection раз в секунду
		this.pollConn();                            // сразу, не ждём первый тик
		poll.add(L.bind(this.pollLog, this), 2);    // журнал дозвона (только когда открыт)
		return tree;
	},

	// опрос текущего состояния модема -> бейдж в карточке Connection
	pollConn: function() {
		var self = this;
		if (!this.elConnBadge) return Promise.resolve();
		return L.resolveDefault(cm.rpc.getConn(), {}).then(function(r) {
			dom.content(self.elConnBadge, cm.connBadge(r && r.state, r && r.access_tech));
		});
	},

	// --- RAT mode: select + Apply, моно-регистр «MODE: X», теги поколений ------
	ratCard: function() {
		var sel = E('select', { 'class': 'cbi-input-select', 'style': 'flex:1;min-width:0' }, [
			['auto', _('Auto (all)')], ['5g','5G'], ['4g','4G/LTE'], ['3g','3G'], ['2g','2G']
		].map(function(o) { return E('option', { 'value': o[0] }, o[1]); }));
		// пилюли-селектор: клик меняет режим и подсвечивает активный (синхр. с select)
		var pills = {};
		var pillRow = E('div', { 'class': 'cm-rat-tags' }, [ ['auto', _('All')],['5g','5G'],['4g','4G'],['3g','3G'],['2g','2G'] ].map(function(m) {
			var p = E('span', { 'class': 'cm-pill-sel', 'click': function() { sel.value = m[0]; sync(); } }, m[1]);
			pills[m[0]] = p; return p;
		}));
		function sync() { Object.keys(pills).forEach(function(k) { pills[k].classList.toggle('cm-pill-on', k === sel.value); }); }
		sel.addEventListener('change', sync);
		var card = E('div', { 'class': 'cm-card cm-c2' }, [
			E('h3', {}, [ cm.icon('signal'), _('RAT mode') ]),
			E('div', { 'class': 'cm-field-ctl', 'style': 'margin:2px 0 12px' }, [ sel,
				E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, function() {
					return cm.rpc.setRat(sel.value).then(this.report.bind(this));
				}) }, _('Apply RAT')) ]),
			pillRow
		]);
		sync();
		return card;
	},

	// --- SIM & TTL: сегментный выбор слота + степпер TTL IN/OUT ---------------
	simTtlCard: function() {
		var simVal = 1, simBtns = {};
		var seg = E('div', { 'class': 'cm-seg' });
		[ [1,'SIM1'], [2,'SIM2'] ].forEach(function(o) {
			var b = E('button', { 'class': 'cm-seg-btn' + (o[0] === 1 ? ' cm-on' : '') }, [ cm.icon('sim'), o[1] ]);
			b.addEventListener('click', function() {
				simVal = o[0];
				Object.keys(simBtns).forEach(function(k) { simBtns[k].classList.toggle('cm-on', Number(k) === o[0]); });
			});
			simBtns[o[0]] = b; seg.appendChild(b);
		});
		var ttlIn  = E('input', { 'type': 'number', 'class': 'cbi-input-number', 'placeholder': _('in'),  'style': 'width:66px' });
		var ttlOut = E('input', { 'type': 'number', 'class': 'cbi-input-number', 'placeholder': _('out'), 'style': 'width:66px' });
		return E('div', { 'class': 'cm-card cm-c2' }, [
			E('h3', {}, [ cm.icon('sim'), _('SIM & TTL') ]),
			E('div', { 'class': 'cm-field' }, [
				E('label', { 'class': 'cm-field-lbl' }, _('SIM slot')),
				E('div', { 'class': 'cm-field-ctl' }, [ seg,
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, function() {
						return cm.rpc.setSim(simVal).then(this.report.bind(this));
					}) }, _('Set')) ])
			]),
			E('div', { 'class': 'cm-field cm-field-div' }, [
				E('label', { 'class': 'cm-field-lbl' }, _('TTL in / out')),
				E('div', { 'class': 'cm-field-ctl' }, [ ttlIn, E('span', { 'class': 'cm-sep' }, '/'), ttlOut,
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, function() {
						return cm.rpc.setTtl(Number(ttlIn.value), Number(ttlOut.value)).then(this.report.bind(this));
					}) }, _('Set')) ])
			])
		]);
	},

	// --- Band-lock: LED-чипы в утопленном отсеке + живой счётчик --------------
	bandCard: function(title, prefix, list, active, variant) {
		var act = {}; (active || []).forEach(function(a) { if (a) act[a] = 1; });
		var boxes = {}, self = this;
		var count = E('span', { 'class': 'cm-countchip' });
		function refresh() {
			var on = Object.keys(boxes).filter(function(k) { return boxes[k].checked; }).length;
			count.textContent = on + ' / ' + list.length + ' locked';
		}
		var grid = E('div', { 'class': 'cm-chipgrid' }, list.map(function(b) {
			var id = prefix + b;
			var inp = E('input', { 'type': 'checkbox', 'value': id });
			if (act[id]) inp.checked = true;
			boxes[id] = inp;
			var chip = E('label', { 'class': 'cm-chip' + (act[id] ? ' cm-on' : '') }, [
				inp, E('span', { 'class': 'cm-chip-led' }), E('span', {}, id)
			]);
			inp.addEventListener('change', function() { chip.classList.toggle('cm-on', inp.checked); refresh(); });
			return chip;
		}));
		function collect() { return Object.keys(boxes).filter(function(k) { return boxes[k].checked; }).join(','); }
		function setAll(v) {
			Object.keys(boxes).forEach(function(k) {
				boxes[k].checked = v;
				var lab = boxes[k].parentNode;
				if (lab && lab.classList) lab.classList.toggle('cm-on', v);
			});
			refresh();
		}
		var card = E('div', { 'class': 'cm-card cm-wide ' + (variant || '') }, [
			E('h3', {}, [ cm.icon('antenna'), title, count ]),
			E('div', { 'class': 'cm-chipwell' }, grid),
			E('div', { 'class': 'cm-band-actions' }, [
				E('div', { 'class': 'cm-seg' }, [
					E('button', { 'class': 'cm-seg-btn', 'click': function() { setAll(true); } }, [ cm.icon('check'), _('Enable all') ]),
					E('button', { 'class': 'cm-seg-btn', 'click': function() { setAll(false); } }, [ cm.icon('x'), _('Disable all') ])
				]),
				E('button', { 'class': 'btn cbi-button-action', 'style': 'margin-left:auto', 'click': ui.createHandlerFn(this, function() {
					return confirmDanger(_('Save & apply band-lock? Connection may drop briefly.')).then(function(ok) {
						if (!ok) return;
						return cm.rpc.setBand(collect()).then(self.report.bind(self));
					});
				}) }, _('Save & apply'))
			])
		]);
		refresh();
		return card;
	},

	// --- Connection: кнопки с иконками + моно-подсказка ------------------------
	connectionCard: function() {
		this.elConnBadge = E('span', { 'class': 'cm-conn-status' });
		// кнопка-переключатель живого журнала дозвона (фрейм появляется выше band-lock)
		this.elLogBtn = E('button', { 'class': 'btn cm-conn-btn cm-logbtn', 'click': ui.createHandlerFn(this, 'toggleLog') }, [ cm.icon('activity'), _('Dial log') ]);
		// бейдж — СНАРУЖИ <h3> (иначе типографика заголовка раздувает текст пилюли):
		// заголовок и бейдж в одной flex-строке, подчёркивание на обёртке
		return E('div', { 'class': 'cm-card cm-c2' }, [
			E('div', { 'class': 'cm-card-head' }, [
				E('h3', {}, [ cm.icon('plug'), _('Connection') ]),
				this.elConnBadge
			]),
			E('div', { 'class': 'cm-conn-grid' }, [
				E('button', { 'class': 'btn cbi-button-positive cm-conn-btn', 'click': ui.createHandlerFn(this, function() {
					return cm.rpc.dial(true).then(this.report.bind(this));
				}) }, [ cm.icon('plug'), _('Connect') ]),
				E('button', { 'class': 'btn cbi-button-negative cm-conn-btn', 'click': ui.createHandlerFn(this, function() {
					return cm.rpc.dial(false).then(this.report.bind(this));
				}) }, [ cm.icon('x'), _('Disconnect') ]),
				E('button', { 'class': 'btn cbi-button-reset cm-conn-btn', 'click': ui.createHandlerFn(this, function() {
					return confirmDanger(_('Reset the modem? This drops the connection.')).then(function(ok) {
						if (ok) return cm.rpc.resetModem();
					}).then(this.report.bind(this));
				}) }, [ cm.icon('refresh'), _('Reset modem') ]),
				this.elLogBtn
			])
		]);
	},

	// --- Живой журнал дозвона: полноширинный фрейм, появляется выше band-lock --
	logCard: function() {
		this.logVisible = false;
		this.elLogBody = E('div', { 'class': 'cm-term-log cm-log-body' }, E('span', { 'class': 'cm-term-hint' }, _('— waiting for connection log… —')));
		this.elLogCard = E('div', { 'class': 'cm-card cm-wide cm-log-card', 'style': 'display:none' }, [
			E('div', { 'class': 'cm-card-head' }, [
				E('h3', {}, [ cm.icon('activity'), _('Dial log') ]),
				E('span', { 'class': 'cm-log-live' }, [ E('span', { 'class': 'cm-pulse-dot' }), _('live') ])
			]),
			E('div', { 'class': 'cm-term' }, this.elLogBody)
		]);
		return this.elLogCard;
	},

	toggleLog: function() {
		this.logVisible = !this.logVisible;
		if (this.elLogCard) this.elLogCard.style.display = this.logVisible ? '' : 'none';
		if (this.elLogBtn) this.elLogBtn.classList.toggle('cm-on', this.logVisible);
		if (this.logVisible) this.pollLog();   // заполнить сразу, не ждать тик опроса
	},

	// опрос журнала — только пока фрейм открыт; обновляет содержимое в реальном времени
	pollLog: function() {
		var self = this;
		if (!this.logVisible || !this.elLogBody) return Promise.resolve();
		return L.resolveDefault(cm.rpc.getConnLog(), {}).then(function(r) {
			var txt = (r && r.log) ? r.log : '';
			if (!txt || self.elLogBody.textContent === txt) return;
			self.elLogBody.textContent = txt;
			self.elLogBody.scrollTop = self.elLogBody.scrollHeight;   // автопрокрутка вниз
		});
	},

	// --- Operator scan: чип-предупреждение + теги + строка current ------------
	scanCard: function() {
		var out = E('div', {}, E('em', { 'class': 'cm-conv-empty' }, _('press scan')));
		function techPill(t) {
			var s = String(t || '').toLowerCase();
			var hot = (s.indexOf('lte') >= 0 || s.indexOf('5g') >= 0 || s.indexOf('nr') >= 0);
			return E('span', { 'class': 'cm-tag' + (hot ? ' cm-tag-accent' : '') }, t || '—');
		}
		function renderList(list) {
			if (!list.length) { dom.content(out, E('div', { 'class': 'cm-conv-empty' }, _('no networks'))); return; }
			var rows = [ E('tr', {}, [ 'PLMN', _('Name'), _('Tech'), _('Status') ].map(function(h) { return E('th', {}, h); })) ];
			list.forEach(function(o) {
				var cur = String(o.status || '').toLowerCase() === 'current';
				rows.push(E('tr', { 'class': cur ? 'cm-row-current' : '' }, [
					E('td', { 'class': 'cm-mono' + (cur ? ' cm-accent' : '') }, cur ? [ cm.icon('star'), ' ' + (o.plmn || '—') ] : (o.plmn || '—')),
					E('td', {}, o.name || '—'),
					E('td', {}, techPill(o.tech)),
					cur ? E('td', {}, E('span', { 'class': 'cm-tag cm-tag-accent' }, _('current')))
					    : E('td', { 'style': 'color:var(--cm-muted)' }, o.status || '—')
				]));
			});
			dom.content(out, E('table', { 'class': 'cm-table' }, rows));
		}
		// скан асинхронный: первый вызов запускает фон, далее опрашиваем, пока
		// бэкенд отвечает {scanning:true}; затем приходит {networks:[...]}
		function poll() {
			return cm.rpc.scanOperators().then(function(r) {
				if (r && r.scanning)
					return new Promise(function(res) { window.setTimeout(res, 3000); }).then(poll);
				renderList((r && r.networks) || []);
			});
		}
		return E('div', { 'class': 'cm-card cm-wide' }, [
			E('h3', {}, [ cm.icon('search'), _('Operator scan'),
				E('button', { 'class': 'btn cbi-button-action cm-btn-ico', 'style': 'margin-left:auto', 'click': ui.createHandlerFn(this, function() {
					dom.content(out, E('div', { 'class': 'cm-conv-empty' }, [ E('span', { 'class': 'cm-pulse-dot' }), _('scanning…') ]));
					return poll();
				}) }, [ cm.icon('search'), _('Scan networks') ]) ]),
			E('div', { 'class': 'cm-note' }, [ cm.icon('alert'), _('Scan takes 1–2 min and briefly affects the connection.') ]),
			out
		]);
	},

	// --- AT console: единая командная строка + лог сессии ---------------------
	// реестр частых AT-команд Quectel RM520N-GL (значение = команда, текст = + описание)
	AT_CMDS: [
		[ '', _('— pick a command —') ],
		[ 'ATI', _('ATI — model and firmware') ],
		[ 'AT+CGSN', _('AT+CGSN — IMEI') ],
		[ 'AT+QCCID', _('AT+QCCID — SIM card ICCID') ],
		[ 'AT+CIMI', _('AT+CIMI — IMSI') ],
		[ 'AT+CPIN?', _('AT+CPIN? — SIM / PIN status') ],
		[ 'AT+CSQ', _('AT+CSQ — signal level (RSSI)') ],
		[ 'AT+QRSRP', _('AT+QRSRP — RSRP per antenna') ],
		[ 'AT+QRSRQ', _('AT+QRSRQ — RSRQ per antenna') ],
		[ 'AT+QSINR', _('AT+QSINR — SINR per antenna') ],
		[ 'AT+QNWINFO', _('AT+QNWINFO — network: tech / band / channel') ],
		[ 'AT+QENG="servingcell"', _('AT+QENG="servingcell" — serving cell') ],
		[ 'AT+QCAINFO', _('AT+QCAINFO — carrier aggregation (CA)') ],
		[ 'AT+QTEMP', _('AT+QTEMP — modem temperature') ],
		[ 'AT+COPS?', _('AT+COPS? — current operator') ],
		[ 'AT+CEREG?', _('AT+CEREG? — network registration') ],
		[ 'AT+CGDCONT?', _('AT+CGDCONT? — PDP contexts / APN') ],
		[ 'AT+QUIMSLOT?', _('AT+QUIMSLOT? — active SIM slot') ],
		[ 'AT+CFUN?', _('AT+CFUN? — modem mode') ],
		[ 'AT+QNWPREFCFG="mode_pref"', _('AT+QNWPREFCFG="mode_pref" — preferred RAT') ],
		[ 'AT+QNWPREFCFG="lte_band"', _('AT+QNWPREFCFG="lte_band" — allowed LTE bands') ],
		[ 'AT+QNWPREFCFG="nr5g_band"', _('AT+QNWPREFCFG="nr5g_band" — allowed NR bands') ],
		[ 'AT+QCFG="usbnet"', _('AT+QCFG="usbnet" — USB net mode (0 QMI · 1 ECM · 2 MBIM · 3 RNDIS · 5 NCM)') ],
		[ 'AT+QCFG="usbnet",0', _('AT+QCFG="usbnet",0 — switch to QMI/RMNET (reboot)') ],
		[ 'AT+QCFG="usbnet",1', _('AT+QCFG="usbnet",1 — switch to ECM (reboot)') ],
		[ 'AT+QCFG="usbnet",2', _('AT+QCFG="usbnet",2 — switch to MBIM (reboot)') ],
		[ 'AT+QCFG="usbnet",3', _('AT+QCFG="usbnet",3 — switch to RNDIS (reboot)') ],
		[ 'AT+QCFG="data_interface"', _('AT+QCFG="data_interface" — data path: 0 USB / 1 PCIe') ],
		[ 'AT+QCFG="data_interface",0,0', _('AT+QCFG="data_interface",0,0 — data path USB (reboot)') ],
		[ 'AT+QCFG="data_interface",1,0', _('AT+QCFG="data_interface",1,0 — data path PCIe (reboot)') ],
		[ 'AT+CFUN=1,1', _('AT+CFUN=1,1 — reboot modem (apply changes)') ]
	],

	atConsoleCard: function() {
		var picker = E('select', { 'class': 'cbi-input-select', 'style': 'max-width:100%' },
			this.AT_CMDS.map(function(c) { return E('option', { 'value': c[0] }, c[1]); }));
		var input = E('input', { 'type': 'text', 'class': 'cm-term-input', 'placeholder': 'AT+QRSRP', 'spellcheck': 'false' });
		var log = E('div', { 'class': 'cm-term-log' }, E('div', { 'class': 'cm-term-hint' }, _('— modem console — pick a command above or type your own —')));
		var started = false;
		function append(node) {
			if (!started) { dom.content(log, []); started = true; }   // убрать подсказку при первом выводе
			log.appendChild(node);
			log.scrollTop = log.scrollHeight;
		}
		function send() {
			var cmd = String(input.value || '').trim();
			if (!cmd) return Promise.resolve();
			append(E('div', { 'class': 'cm-term-cmd' }, '› ' + cmd));
			input.value = '';
			return cm.rpc.sendAt(cmd).then(function(r) {
				var err = !!(r && r.error);
				var reply = (r && r.raw != null) ? r.raw : (err ? ('error: ' + r.error) : '—');
				append(E('div', { 'class': err ? 'cm-term-err' : 'cm-term-out' }, reply));
			});
		}
		picker.addEventListener('change', function() {
			if (picker.value) { input.value = picker.value; picker.selectedIndex = 0; input.focus(); }
		});
		input.addEventListener('keydown', function(e) { if (e.key === 'Enter') { e.preventDefault(); send(); } });
		return E('div', { 'class': 'cm-card cm-wide' }, [
			E('h3', {}, [ cm.icon('terminal'), _('AT console') ]),
			E('div', { 'class': 'cm-field-ctl', 'style': 'margin-bottom:10px' }, [ picker ]),
			E('div', { 'class': 'cm-term' }, [
				log,
				E('div', { 'class': 'cm-term-line' }, [
					E('span', { 'class': 'cm-term-prompt' }, '›'),
					input,
					E('button', { 'class': 'cm-term-send', 'click': ui.createHandlerFn(this, send) }, [ cm.icon('send'), _('Send') ])
				])
			])
		]);
	},

	report: function(r) {
		var ok = r && (r.ok || r.raw != null);
		ui.addNotification(null,
			E('p', {}, ok ? _('Done') : ((r && r.error) ? ('Error: ' + r.error) : _('Failed'))),
			ok ? 'info' : 'warning');
	}
});
