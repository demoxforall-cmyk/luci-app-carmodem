'use strict';
'require view';
'require ui';
'require dom';
'require poll';
'require carmodem';

// CarModem — экран «Watchdog»: авто-восстановление связи модема.
// Наглядно показывает правила эскалации (лестница L1→L2→L3), живой маркер
// текущего strike, состояние (интернет/модем/сигнал) и журнал событий.
// Дизайн Console RF (cm-* классы, тема через currentColor/color-mix). GPL-2.0

var cm = carmodem;

function num(v, d) { v = parseInt(v, 10); return isNaN(v) ? d : v; }

return view.extend({
	handleSaveApply: null, handleSave: null, handleReset: null,

	load: function() {
		return L.resolveDefault(cm.rpc.getWatchdog(), {});
	},

	render: function(data) {
		cm.injectCSS();
		data = data || {};
		this.cfg = data.config || {};
		this.inp = {};
		this.elRung = {};
		this.enabled = num(this.cfg.enabled, 0);
		this.tglReboot = num(this.cfg.allow_reboot, 1);

		var tree = E('div', { 'class': 'cm-adv' }, [
			E('h2', {}, _('Modem watchdog')),
			E('div', { 'class': 'cm-grid' }, [
				this.masterCard(),
				this.ladderCard(),
				this.liveCard(),
				this.settingsCard(),
				this.eventLogCard()
			])
		]);

		poll.add(L.bind(this.pollWd, this), 5);
		this.applyLive(data.live || {}, data.log || []);
		return tree;
	},

	// --- Мастер: тумблер + статус + ручные действия -------------------------
	masterCard: function() {
		var self = this;
		this.elMaster = E('div', { 'class': 'cm-seg cm-wd-master' });
		this.renderEnable();
		this.elStatusBadge = E('span', { 'class': 'cm-wd-badge' });
		return E('div', { 'class': 'cm-card cm-wide' }, [
			E('div', { 'class': 'cm-card-head' }, [
				E('h3', {}, [ cm.icon('activity'), _('Auto-recovery') ]),
				this.elStatusBadge
			]),
			E('div', { 'class': 'cm-wd-toprow' }, [
				E('div', { 'class': 'cm-field-ctl' }, [
					E('span', { 'class': 'cm-field-lbl', 'style': 'margin:0 8px 0 0' }, _('Watchdog')),
					this.elMaster
				]),
				E('div', { 'class': 'cm-field-ctl', 'style': 'margin-left:auto' }, [
					E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'doTest') }, [ cm.icon('refresh'), _('Run check now') ]),
					E('button', { 'class': 'btn', 'click': ui.createHandlerFn(this, 'doClear') }, [ cm.icon('x'), _('Reset counter') ])
				])
			]),
			E('div', { 'class': 'cm-note' }, [ cm.icon('alert'),
				_('Safety rule: with no signal / not registered (covered parking) the watchdog does nothing — it never reconnects or reboots blindly.') ])
		]);
	},
	renderEnable: function() {
		var self = this;
		dom.content(this.elMaster, [ [1, _('On')], [0, _('Off')] ].map(function(o) {
			return E('button', {
				'class': 'cm-seg-btn' + (self.enabled === o[0] ? ' cm-on' : ''),
				'click': ui.createHandlerFn(self, 'toggleEnable', o[0])
			}, o[1]);
		}));
	},
	toggleEnable: function(v) {
		if (v === this.enabled) return Promise.resolve();
		return this.doSave(v);
	},

	// --- Лестница эскалации (как работает и по каким правилам) --------------
	ladderCard: function() {
		this.elMarker = E('div', { 'class': 'cm-wd-marker' }, _('—'));
		var rungs = E('div', { 'class': 'cm-wd-ladder' }, [
			this.rung(1, 'refresh', _('L1 · Reconnect interface'), 'l1_reconnect',
				_('ifdown/ifup of the WAN interface — the softest fix.'), ''),
			this.rung(2, 'cpu', _('L2 · Reset modem'), 'l2_reset',
				_('mmcli --reset (coordinated with ModemManager, not a raw AT command).'), 'cooldown_reset'),
			this.rung(3, 'alert', _('L3 · Reboot router'), 'l3_reboot',
				_('Full router reboot — only when the modem is connected (bearer up) but has no data, once per episode.'), '')
		]);
		return E('div', { 'class': 'cm-card cm-wide' }, [
			E('div', { 'class': 'cm-card-head' }, [
				E('h3', {}, [ cm.icon('stack'), _('Escalation rules') ]),
				this.elMarker
			]),
			E('div', { 'class': 'cm-wd-note2' },
				_('While registered but with no internet, the strike counter grows every cycle. One action per cycle, checked top-down; the counter resets only when internet returns.')),
			rungs
		]);
	},
	rung: function(lvl, icon, title, thKey, desc, cdKey) {
		var th = num(this.cfg[thKey], lvl === 1 ? 2 : lvl === 2 ? 5 : 8);
		var chip = E('span', { 'class': 'cm-chip cm-wd-led' }, [ E('span', { 'class': 'cm-chip-led' }), 'L' + lvl ]);
		var badge = lvl === 3 ? E('span', { 'class': 'cm-tag cm-wd-danger' }, _('reboot')) : '';
		var row = E('div', { 'class': 'cm-wd-rung', 'data-lvl': lvl }, [
			E('div', { 'class': 'cm-wd-rung-l' }, [ cm.icon(icon), chip ]),
			E('div', { 'class': 'cm-wd-rung-b' }, [
				E('div', { 'class': 'cm-wd-rung-title' }, [ E('span', {}, title), badge ]),
				E('div', { 'class': 'cm-wd-rung-desc' }, desc)
			]),
			E('div', { 'class': 'cm-wd-rung-th' }, [
				E('span', { 'class': 'cm-countchip' }, '≥ ' + th),
				cdKey ? E('span', { 'class': 'cm-tag', 'style': 'margin-top:4px' }, _('cooldown') + ' ' + num(this.cfg[cdKey], 300) + 's') : ''
			])
		]);
		this.elRung[lvl] = row;
		return row;
	},

	// --- Живое состояние ----------------------------------------------------
	liveCard: function() {
		this.elLiveInet = E('span', { 'class': 'cm-wd-badge' });
		this.elLiveModem = E('span', {});
		this.elLiveSig = E('span', { 'class': 'cm-mono' }, '—');
		this.elLiveStrike = E('span', { 'class': 'cm-countchip' }, '0');
		this.elLiveEpisode = E('span', { 'class': 'cm-tag' }, '');
		var kv = function(k, v) { return E('div', { 'class': 'cm-wd-liverow' }, [ E('span', { 'class': 'cm-field-lbl', 'style': 'margin:0' }, k), v ]); };
		return E('div', { 'class': 'cm-card cm-c3' }, [
			E('h3', {}, [ cm.icon('signal'), _('Live state') ]),
			kv(_('Internet'), this.elLiveInet),
			kv(_('Modem'), this.elLiveModem),
			kv('RSRP / SINR', this.elLiveSig),
			kv(_('Strike'), this.elLiveStrike),
			kv(_('Episode'), this.elLiveEpisode)
		]);
	},

	// --- Настройки ----------------------------------------------------------
	settingsCard: function() {
		var self = this;
		function nfield(key, label, def, w) {
			var i = E('input', { 'type': 'number', 'class': 'cbi-input-number', 'value': num(self.cfg[key], def), 'style': 'width:' + (w || 72) + 'px' });
			self.inp[key] = i;
			return E('div', { 'class': 'cm-field cm-field-div' }, [
				E('label', { 'class': 'cm-field-lbl' }, label),
				E('div', { 'class': 'cm-field-ctl' }, i)
			]);
		}
		function tfield(key, label, ph) {
			var i = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'value': (self.cfg[key] != null ? self.cfg[key] : ''), 'placeholder': ph || '', 'style': 'flex:1;min-width:120px' });
			self.inp[key] = i;
			return E('div', { 'class': 'cm-field cm-field-div' }, [
				E('label', { 'class': 'cm-field-lbl' }, label),
				E('div', { 'class': 'cm-field-ctl' }, i)
			]);
		}
		// тумблер разрешения ребута
		this.elRebootTgl = E('div', { 'class': 'cm-seg' });
		this.renderRebootTgl();

		return E('div', { 'class': 'cm-card cm-c3' }, [
			E('h3', {}, [ cm.icon('terminal'), _('Settings') ]),
			nfield('interval', _('Check interval (s)'), 60, 80),
			nfield('l1_reconnect', _('L1 threshold (cycles)'), 2),
			nfield('l2_reset', _('L2 threshold (cycles)'), 5),
			nfield('l3_reboot', _('L3 threshold (cycles)'), 8),
			nfield('cooldown_reset', _('Reset cooldown (s)'), 300, 80),
			tfield('ping_hosts', _('Ping hosts'), '1.1.1.1 8.8.8.8'),
			E('div', { 'class': 'cm-field cm-field-div' }, [
				E('label', { 'class': 'cm-field-lbl' }, _('Allow router reboot (L3)')),
				E('div', { 'class': 'cm-field-ctl' }, this.elRebootTgl)
			]),
			E('div', { 'class': 'cm-note cm-wd-danger-note' }, [ cm.icon('alert'),
				_('L3 reboots the whole router. Kept safe: only when connected (bearer up) but no data, and once per episode.') ]),
			tfield('recovery_service', _('Restart service after recovery'), 'podkop'),
			E('div', { 'class': 'cm-note' }, [ cm.icon('alert'),
				_('Optional: init.d service restarted once when internet returns — e.g. “podkop”, which otherwise starts blind with no network.') ]),
			tfield('wan_iface', _('WAN interface (for L1 dial)'), 'wwan'),
			tfield('wan_netdev', _('WAN netdev override'), _('blank = auto')),
			E('div', { 'class': 'cm-field-ctl', 'style': 'margin-top:12px' }, [
				E('button', { 'class': 'btn cbi-button-action', 'click': ui.createHandlerFn(this, 'doSaveBtn') }, [ cm.icon('check'), _('Save settings') ])
			])
		]);
	},
	renderRebootTgl: function() {
		var self = this;
		dom.content(this.elRebootTgl, [ [1, _('On')], [0, _('Off')] ].map(function(o) {
			return E('button', {
				'class': 'cm-seg-btn' + (self.tglReboot === o[0] ? ' cm-on' : ''),
				'click': function() { self.tglReboot = o[0]; self.renderRebootTgl(); }
			}, o[1]);
		}));
	},

	// --- Журнал событий -----------------------------------------------------
	eventLogCard: function() {
		this.elLog = E('div', { 'class': 'cm-term-log' }, E('div', { 'class': 'cm-term-hint' }, _('— no events yet —')));
		return E('div', { 'class': 'cm-card cm-wide' }, [
			E('div', { 'class': 'cm-card-head' }, [
				E('h3', {}, [ cm.icon('activity'), _('Event log') ]),
				E('span', { 'class': 'cm-log-live' }, [ E('span', { 'class': 'cm-pulse-dot' }), _('live') ])
			]),
			E('div', { 'class': 'cm-term' }, this.elLog)
		]);
	},

	// --- Сохранение / действия ----------------------------------------------
	collectCfg: function() {
		var self = this, gv = function(k, d) { var e = self.inp[k]; return (e && e.value !== '') ? e.value : (self.cfg[k] != null ? self.cfg[k] : d); };
		return {
			enabled: this.enabled ? 1 : 0,
			interval: num(gv('interval', 60), 60),
			ping_hosts: gv('ping_hosts', '1.1.1.1 8.8.8.8 77.88.8.8'),
			l1_reconnect: num(gv('l1_reconnect', 2), 2),
			l2_reset: num(gv('l2_reset', 5), 5),
			l3_reboot: num(gv('l3_reboot', 8), 8),
			cooldown_reset: num(gv('cooldown_reset', 300), 300),
			allow_reboot: this.tglReboot ? 1 : 0,
			recovery_service: gv('recovery_service', ''),
			wan_netdev: gv('wan_netdev', ''),
			wan_iface: gv('wan_iface', 'wwan')
		};
	},
	doSave: function(enabledOverride) {
		var self = this, c = this.collectCfg();
		if (enabledOverride != null) c.enabled = enabledOverride;
		return cm.rpc.setWatchdog(c.enabled, c.interval, c.ping_hosts, c.l1_reconnect, c.l2_reset, c.l3_reboot,
			c.cooldown_reset, c.allow_reboot, c.recovery_service, c.wan_netdev, c.wan_iface).then(function(r) {
			if (r && r.ok) {
				self.cfg = c; self.enabled = c.enabled; self.renderEnable();
				ui.addNotification(null, E('p', {}, _('Saved')), 'info');
				self.pollWd();
			} else ui.addNotification(null, E('p', {}, _('Save failed')), 'warning');
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, _('Request failed') + ': ' + ((e && e.message) || _('timeout'))), 'warning');
		});
	},
	doSaveBtn: function() { return this.doSave(null); },
	doTest: function() {
		var self = this;
		return cm.rpc.watchdogTest().then(function(r) {
			self.applyLive((r && r.live) || {}, (r && r.log) || []);
			ui.addNotification(null, E('p', {}, _('Check done')), 'info');
		}).catch(function() { ui.addNotification(null, E('p', {}, _('Request failed')), 'warning'); });
	},
	doClear: function() {
		var self = this;
		return cm.rpc.watchdogClear().then(function() { self.pollWd(); ui.addNotification(null, E('p', {}, _('Counter reset')), 'info'); })
			.catch(function() { ui.addNotification(null, E('p', {}, _('Request failed')), 'warning'); });
	},

	// --- Опрос + отрисовка живого состояния ---------------------------------
	pollWd: function() {
		var self = this;
		if (!this.elStatusBadge) return Promise.resolve();
		return L.resolveDefault(cm.rpc.getWatchdog(), {}).then(function(d) {
			if (d && d.config) self.cfg = d.config;
			self.applyLive((d && d.live) || {}, (d && d.log) || []);
		});
	},
	applyLive: function(live, log) {
		var strike = num(live.strike, 0);
		var enabled = num(this.cfg.enabled, this.enabled);
		// статус-бейдж
		var phase = enabled ? (live.phase || 'ok') : 'disabled';
		var map = {
			'disabled': [ _('Disabled'), 'cm-wd-b-off' ],
			'ok':        [ _('Watching'), 'cm-wd-b-ok' ],
			'no-signal': [ _('No signal — idle'), 'cm-wd-b-mut' ],
			'escalating':[ _('Escalating'), 'cm-wd-b-warn' ]
		};
		var m = map[phase] || map.ok;
		dom.content(this.elStatusBadge, [ E('span', { 'class': 'cm-wd-dot' }), E('span', {}, m[0]) ]);
		this.elStatusBadge.className = 'cm-wd-badge ' + m[1];

		// живая панель
		if (this.elLiveInet) {
			var up = (live.internet === 'up');
			dom.content(this.elLiveInet, [ E('span', { 'class': 'cm-wd-dot' }),
				E('span', {}, up ? (_('up') + (live.rtt ? ' · ' + live.rtt + ' ms' : '')) : _('down')) ]);
			this.elLiveInet.className = 'cm-wd-badge ' + (up ? 'cm-wd-b-ok' : 'cm-wd-b-warn');
			dom.content(this.elLiveModem, cm.connBadge(live.state, live.tech));
			this.elLiveSig.textContent = (live.rsrp || '—') + ' / ' + (live.sinr || '—');
			this.elLiveStrike.textContent = String(strike);
			var reb = num(live.episode_rebooted, 0);
			this.elLiveEpisode.textContent = reb ? _('rebooted this episode') : _('clean');
			this.elLiveEpisode.className = 'cm-tag' + (reb ? ' cm-wd-danger' : '');
		}

		// лестница: подсветка достигнутых ступеней + маркер следующего действия
		this.updateLadder(strike, enabled);

		// журнал
		if (this.elLog && log && log.length) {
			var self = this;
			dom.content(this.elLog, log.map(function(line) { return self.logLine(line); }));
			this.elLog.scrollTop = this.elLog.scrollHeight;
		}
	},
	updateLadder: function(strike, enabled) {
		var ths = { 1: num(this.cfg.l1_reconnect, 2), 2: num(this.cfg.l2_reset, 5), 3: num(this.cfg.l3_reboot, 8) };
		var allowReboot = num(this.cfg.allow_reboot, 1);
		for (var l = 1; l <= 3; l++) {
			var row = this.elRung[l];
			if (!row) continue;
			var reached = enabled && strike >= ths[l];
			var muted = (l === 3 && !allowReboot);
			row.classList.toggle('cm-wd-reached', !!reached);
			row.classList.toggle('cm-wd-muted', !!muted);
		}
		if (!this.elMarker) return;
		var nextLvl = 0, nextTh = 0, names = { 1: _('reconnect'), 2: _('modem reset'), 3: _('router reboot') };
		for (var k = 1; k <= 3; k++) { if ((k !== 3 || allowReboot) && strike < ths[k]) { nextLvl = k; nextTh = ths[k]; break; } }
		var txt;
		if (!enabled) txt = '—';
		else if (nextLvl) txt = _('Strike') + ' ' + strike + ' → ' + names[nextLvl] + ' @ ' + nextTh + ' (' + (nextTh - strike) + ' ' + _('cycles left') + ')';
		else txt = _('Strike') + ' ' + strike + ' · ' + _('all levels reached');
		this.elMarker.textContent = txt;
	},
	logLine: function(line) {
		// формат: ts|inet|rtt=..|state|tech|rsrp=..|sinr=..|strike=..|action|detail
		var p = String(line).split('|');
		var action = p[8] || '', detail = p[9] || '', ts = p[0] || '';
		var cls = 'cm-term-out';
		if (/reboot/.test(action)) cls = 'cm-term-err';
		else if (/reset|reconnect|recovery/.test(action)) cls = 'cm-wd-log-act';
		else if (action === 'ok') cls = 'cm-wd-log-ok';
		else if (/wait/.test(action)) cls = 'cm-term-hint';
		return E('div', { 'class': cls }, ts.replace(/^\d{4}-\d{2}-\d{2} /, '') + '  ' + action + (detail ? ' — ' + detail : ''));
	}
});
