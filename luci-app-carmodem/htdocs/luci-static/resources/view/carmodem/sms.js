'use strict';
'require view';
'require ui';
'require dom';
'require carmodem';

// CarModem — экран «Messages»: мессенджер-стиль (ТЗ 5.4).
// Слева список диалогов (по номеру) + закреплённый USSD; справа тред с пузырями
// (вход/исход), метка хранилища на каждом сообщении. Переключатель приёмного
// хранилища SIM/Modem/Combined(MT) + полоски заполнения. Кодирование UCS2 и
// сборку длинных делает ModemManager. SPDX: GPL-2.0

var cm = carmodem;

function normNum(n) { return String(n || '').replace(/[\s()\-]/g, '') || '—'; }
function tsShort(ts) {
	if (!ts) return '';
	var m = String(ts).match(/T(\d{2}:\d{2})/);
	return m ? m[1] : String(ts).slice(0, 10);
}
function pad2(n) { return (n < 10 ? '0' : '') + n; }
function dateLabel(d) {   // d = "YYYY-MM-DD" -> Today / Yesterday / DD.MM.YYYY
	var now = new Date();
	var t = now.getFullYear() + '-' + pad2(now.getMonth() + 1) + '-' + pad2(now.getDate());
	var yo = new Date(now.getTime() - 86400000);
	var y = yo.getFullYear() + '-' + pad2(yo.getMonth() + 1) + '-' + pad2(yo.getDate());
	if (d === t) return _('Today');
	if (d === y) return _('Yesterday');
	var p = d.split('-'); return (p.length === 3) ? p[2] + '.' + p[1] + '.' + p[0] : d;
}
function avaColor(num) {   // стабильный цвет аватара по номеру (0..5)
	var s = String(num || ''), h = 0, i;
	for (i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 6;
	return h;
}

return view.extend({
	handleSaveApply: null, handleSave: null, handleReset: null,

	active: null,       // ключ диалога | '__new__' | '__ussd__'
	selectMode: false,
	selected: {},       // id -> true
	ussdLog: [],        // [{dir,text}]
	ussdActive: false,

	load: function() {
		// один объединённый вызов хранилища (storage + счётчики) — без гонки AT+CPMS
		return Promise.all([
			L.resolveDefault(cm.rpc.getSms(), []),
			L.resolveDefault(cm.rpc.getSmsStorageFill(), {})
		]);
	},

	render: function(data) {
		cm.injectCSS();
		this.ingest(data);
		if (!this.active && this.order.length) this.active = this.order[0];

		this.elSwitch = E('div', { 'class': 'cm-seg' });
		this.elFill   = E('div', { 'class': 'cm-msg-fill' });
		this.elList   = E('div', { 'class': 'cm-msg-list' });
		this.elRight  = E('div', { 'class': 'cm-msg-right' });
		this.renderSwitch(); this.renderFill(); this.renderList(); this.renderRight();

		return E('div', {}, [
			E('h2', {}, _('Messages')),
			E('div', { 'class': 'cm-grid' }, [
				E('div', { 'class': 'cm-card cm-wide cm-msg' }, [
					E('div', { 'class': 'cm-msg-top' }, [
						E('div', { 'class': 'cm-msg-title' }, [ cm.icon('chat'), E('span', {}, _('SMS/USSD')) ]),
						this.elSwitch
					]),
					this.elFill,
					E('div', { 'class': 'cm-msg-panes' }, [ this.elList, this.elRight ])
				])
			])
		]);
	},

	ingest: function(data) {
		this.messages = (data && data[0]) || [];
		var info = (data && data[1]) || {};
		this.storage = info;   // info.storage -> переключатель
		this.fill = info;      // info.sim / info.modem -> полоски заполнения
		var g = {};
		this.messages.forEach(function(m) { var k = normNum(m.number); (g[k] = g[k] || []).push(m); });
		// Сортируем по id: MM присваивает id в порядке создания/прихода — это
		// единый ключ и для входящих, и для исходящих (у submit нет таймстампа,
		// но id у отправленного раньше ответа меньше). Хронология: старые сверху.
		function gid(m) { return (m.id == null ? 0 : m.id) + 0; }
		Object.keys(g).forEach(function(k) {
			g[k].sort(function(a, b) { return gid(a) - gid(b); });
		});
		this.convos = g;
		this.order = Object.keys(g).sort(function(a, b) {
			var la = g[a][g[a].length - 1], lb = g[b][g[b].length - 1];
			return gid(lb) - gid(la);   // диалоги: с самой свежей активностью (макс. id) сверху
		});
	},

	reload: function() {
		var self = this;
		return this.load().then(function(d) {
			self.ingest(d);
			if (self.active && self.active.indexOf('__') !== 0 && !self.convos[self.active])
				self.active = self.order[0] || null;
			self.renderSwitch(); self.renderFill(); self.renderList(); self.renderRight();
		});
	},

	// --- переключатель приёмного хранилища ---
	renderSwitch: function() {
		var self = this, cur = (this.storage && this.storage.storage) || '';
		var opts = [ ['sm', _('SIM'), 'sim'], ['me', _('Modem'), 'cpu'], ['mt', _('Combined'), 'stack'] ];
		dom.content(this.elSwitch, opts.map(function(o) {
			return E('button', {
				'class': 'cm-seg-btn' + (cur === o[0] ? ' cm-on' : ''),
				'title': _('Receive new SMS into this storage'),
				'click': ui.createHandlerFn(self, 'setStorage', o[0])
			}, [ cm.icon(o[2]), E('span', {}, o[1]) ]);
		}));
	},
	setStorage: function(s) {
		var self = this;
		return cm.rpc.setSmsStorage(s).then(function(r) {
			if (r && r.error) ui.addNotification(null, E('p', {}, 'Error: ' + r.error), 'warning');
			return self.reload();
		});
	},

	// --- полоски заполнения ---
	renderFill: function() {
		var f = this.fill || {}, sim = f.sim || {}, mod = f.modem || {};
		function bar(icon, label, used, total, color) {
			var pct = (total > 0) ? Math.min(100, Math.round(used / total * 100)) : 0;
			return E('div', { 'class': 'cm-fill' }, [
				cm.icon(icon), E('span', { 'class': 'cm-fill-lbl' }, label),
				E('span', { 'class': 'cm-fill-track' }, E('span', { 'class': 'cm-fill-bar', 'style': 'width:' + pct + '%;background:' + color })),
				E('span', { 'class': 'cm-fill-num' }, (used != null ? used : '—') + ' / ' + (total != null ? total : '—'))
			]);
		}
		dom.content(this.elFill, [
			bar('sim', _('SIM'), sim.used, sim.total, '#BA7517'),
			bar('cpu', _('Modem'), mod.used, mod.total, '#378add')
		]);
	},

	// --- список диалогов ---
	avatarEl: function(num) {
		var n = String(num || '');
		var inner = /^[+\d]/.test(n) ? cm.icon('user')
			: E('span', {}, (n.replace(/[^0-9A-Za-zА-Яа-я]/g, '').slice(0, 1) || '?').toUpperCase());
		return E('span', { 'class': 'cm-ava cm-ava-c' + avaColor(n) }, inner);
	},
	renderList: function() {
		var self = this, rows = [];
		rows.push(E('div', { 'class': 'cm-conv cm-conv-new', 'click': ui.createHandlerFn(self, 'open', '__new__') }, [
			E('span', { 'class': 'cm-ava cm-ava-accent' }, cm.icon('pencil')),
			E('div', { 'class': 'cm-conv-body' }, E('div', { 'class': 'cm-conv-name cm-accent' }, _('New message')))
		]));
		this.order.forEach(function(k) {
			var msgs = self.convos[k], last = msgs[msgs.length - 1];
			rows.push(E('div', { 'class': 'cm-conv' + (self.active === k ? ' cm-active' : ''), 'click': ui.createHandlerFn(self, 'open', k) }, [
				self.avatarEl(last.number),
				E('div', { 'class': 'cm-conv-body' }, [
					E('div', { 'class': 'cm-conv-line' }, [
						E('span', { 'class': 'cm-conv-name' }, last.number || k),
						E('span', { 'class': 'cm-conv-time' }, tsShort(last.timestamp))
					]),
					E('div', { 'class': 'cm-conv-prev' }, (last.dir === 'out' ? '✓ ' : '') + (last.text || ''))
				])
			]));
		});
		if (!this.order.length)
			rows.push(E('div', { 'class': 'cm-conv-empty' }, E('em', {}, _('No conversations'))));
		var ussd = E('div', { 'class': 'cm-conv cm-conv-ussd' + (self.active === '__ussd__' ? ' cm-active' : ''), 'click': ui.createHandlerFn(self, 'open', '__ussd__') }, [
			E('span', { 'class': 'cm-ava cm-ava-ussd' }, cm.icon('hash')),
			E('div', { 'class': 'cm-conv-body' }, [
				E('div', { 'class': 'cm-conv-name' }, _('USSD')),
				E('div', { 'class': 'cm-conv-prev' }, _('Service codes'))
			])
		]);
		dom.content(this.elList, [ E('div', { 'class': 'cm-conv-scroll' }, rows), ussd ]);
	},
	open: function(k) { this.active = k; this.selectMode = false; this.selected = {}; this.renderList(); this.renderRight(); },

	// --- правая панель ---
	renderRight: function() {
		if (this.active === '__new__') return this.renderNew();
		if (this.active === '__ussd__') return this.renderUssd();
		if (this.active && this.convos[this.active]) return this.renderThread(this.active);
		dom.content(this.elRight, E('div', { 'class': 'cm-msg-empty' }, E('em', {}, _('Select a conversation'))));
	},

	renderThread: function(k) {
		var self = this, msgs = this.convos[k], num = msgs[msgs.length - 1].number || k;
		var head = this.selectMode
			? E('div', { 'class': 'cm-th-head cm-th-sel' }, [
				E('button', { 'class': 'cm-icon-btn', 'click': ui.createHandlerFn(self, 'exitSelect') }, cm.icon('x')),
				E('span', { 'class': 'cm-th-name' }, this.countSel() + ' ' + _('selected'))
			  ])
			: E('div', { 'class': 'cm-th-head' }, [
				this.avatarEl(num),
				E('div', { 'style': 'flex:1;min-width:0' }, [
					E('div', { 'class': 'cm-th-name' }, num),
					E('div', { 'class': 'cm-th-sub' }, msgs.length + ' ' + _('messages'))
				]),
				E('button', { 'class': 'cm-icon-btn', 'title': _('Select & delete'), 'click': ui.createHandlerFn(self, 'enterSelect') }, cm.icon('trash'))
			  ]);
		var bubbles = [], lastDate = '';
		msgs.forEach(function(m, i) {
			var d = m.timestamp ? String(m.timestamp).slice(0, 10) : '';
			if (d && d !== lastDate) {            // разделитель даты (Today/дата)
				lastDate = d;
				bubbles.push(E('div', { 'class': 'cm-date-sep' }, E('span', {}, dateLabel(d))));
			}
			var out = (m.dir === 'out'), sel = !!self.selected[m.id];
			var circle = self.selectMode
				? E('span', { 'class': 'cm-sel-circle' + (sel ? ' cm-sel-on' : '') }, sel ? cm.icon('check') : [])
				: '';
			// время — только у ПОСЛЕДНЕГО в череде сообщений с одинаковым временем
			var tm = tsShort(m.timestamp), nxt = msgs[i + 1];
			var showTime = tm && (!nxt || tsShort(nxt.timestamp) !== tm);
			var meta = [];
			if (showTime) meta.push(E('span', {}, tm));
			if (m.storage) meta.push(E('span', { 'class': 'cm-bub-stor cm-stor-' + m.storage }, [ cm.icon(m.storage === 'sm' ? 'sim' : 'cpu'), cm.storageLabel(m.storage) ]));
			var bubble = E('div', { 'class': 'cm-bub ' + (out ? 'cm-bub-out' : 'cm-bub-in') }, [
				E('div', { 'class': 'cm-bub-text' }, m.text || ''),
				meta.length ? E('div', { 'class': 'cm-bub-meta' }, meta) : ''
			]);
			bubbles.push(E('div', {
				'class': 'cm-bub-row ' + (out ? 'cm-row-out' : 'cm-row-in') + (self.selectMode ? ' cm-selmode' : '') + (sel ? ' cm-selected' : ''),
				'click': self.selectMode ? ui.createHandlerFn(self, 'toggleSel', m.id) : null
			}, [ circle, bubble ]));
		});
		var foot;
		if (this.selectMode) {
			var n = this.countSel();
			foot = E('div', { 'class': 'cm-th-foot' }, [
				E('button', { 'class': 'btn cm-del-all', 'click': ui.createHandlerFn(self, 'deleteConv', k) }, [ cm.icon('trash'), _('Delete entire conversation') ]),
				E('button', { 'class': 'btn cm-del-sel' + (n ? '' : ' cm-disabled'), 'click': n ? ui.createHandlerFn(self, 'deleteSelected', k) : null }, [ cm.icon('trash'), _('Delete') + ' (' + n + ')' ])
			]);
		} else {
			var input = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': _('Message'), 'style': 'flex:1', 'keydown': function(ev) { if (ev.keyCode === 13) self.send(num, input); } });
			foot = E('div', { 'class': 'cm-th-compose' }, [
				input,
				E('button', { 'class': 'cm-send-btn', 'aria-label': _('Send'), 'click': ui.createHandlerFn(self, 'send', num, input) }, cm.icon('send'))
			]);
		}
		var body = E('div', { 'class': 'cm-th-body' }, bubbles);
		this.elBody = body;
		dom.content(this.elRight, [ head, body, foot ]);
		// сохранённую позицию (выделение в режиме удаления) восстанавливаем синхронно —
		// ползунок не прыгает; иначе автопрокрутка вниз (открытие диалога / после отправки)
		var keep = this._scrollKeep; this._scrollKeep = null;
		if (keep != null) body.scrollTop = keep;
		else window.setTimeout(function() { body.scrollTop = body.scrollHeight; }, 0);
	},

	send: function(num, input) {
		var self = this, text = input.value;
		if (!text) return;
		input.value = '';
		return cm.rpc.sendSms(num, text).then(function(r) {
			if (r && r.error) ui.addNotification(null, E('p', {}, _('Send failed') + ': ' + r.error), 'warning');
			return self.reload();
		});
	},

	// --- новый контакт ---
	renderNew: function() {
		var self = this;
		var to = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': '+7…', 'style': 'flex:1;height:32px' });
		var msg = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': _('Message'), 'style': 'flex:1', 'keydown': function(ev) { if (ev.keyCode === 13) self.sendNew(to, msg); } });
		dom.content(this.elRight, [
			E('div', { 'class': 'cm-th-head' }, [
				E('span', { 'class': 'cm-ava cm-ava-accent' }, cm.icon('pencil')),
				E('span', { 'class': 'cm-th-sub', 'style': 'flex:0 0 auto' }, _('To')),
				to
			]),
			E('div', { 'class': 'cm-th-body cm-th-newhint' }, E('div', { 'class': 'cm-newhint' }, [
				cm.icon('chat'),
				E('div', {}, _('New conversation — enter a number above and a message below'))
			])),
			E('div', { 'class': 'cm-th-compose' }, [
				msg,
				E('button', { 'class': 'cm-send-btn', 'aria-label': _('Send'), 'click': ui.createHandlerFn(self, 'sendNew', to, msg) }, cm.icon('send'))
			])
		]);
	},
	sendNew: function(to, msg) {
		var self = this;
		if (!to.value) { ui.addNotification(null, E('p', {}, _('Recipient required')), 'warning'); return; }
		if (!msg.value) return;
		return cm.rpc.sendSms(to.value, msg.value).then(function(r) {
			if (r && r.error) { ui.addNotification(null, E('p', {}, _('Send failed') + ': ' + r.error), 'warning'); return; }
			self.active = normNum(to.value);
			return self.reload();
		});
	},

	// --- удаление (режим выбора) ---
	keepScroll: function() { this._scrollKeep = this.elBody ? this.elBody.scrollTop : null; },
	enterSelect: function() { this.keepScroll(); this.selectMode = true; this.selected = {}; this.renderRight(); },
	exitSelect: function() { this.keepScroll(); this.selectMode = false; this.selected = {}; this.renderRight(); },
	toggleSel: function(id) { this.keepScroll(); if (this.selected[id]) delete this.selected[id]; else this.selected[id] = true; this.renderRight(); },
	countSel: function() { return Object.keys(this.selected).length; },
	deleteSelected: function(k) {
		var ids = Object.keys(this.selected);
		if (!ids.length) return;
		return this.doDelete(ids.join(','));
	},
	deleteConv: function(k) {
		var ids = (this.convos[k] || []).map(function(m) { return m.id; });
		return this.doDelete(ids.join(','));
	},
	doDelete: function(ids) {
		var self = this;
		return cm.rpc.deleteSms(ids).then(function(r) {
			if (r && r.error) ui.addNotification(null, E('p', {}, _('Delete failed')), 'warning');
			self.selectMode = false; self.selected = {};
			return self.reload();
		});
	},

	// --- USSD как закреплённый диалог ---
	renderUssd: function() {
		var self = this;
		var bubbles = this.ussdLog.map(function(b) {
			return E('div', { 'class': 'cm-bub-row ' + (b.dir === 'out' ? 'cm-row-out' : 'cm-row-in') },
				E('div', { 'class': 'cm-bub ' + (b.dir === 'out' ? 'cm-bub-out' : 'cm-bub-in') },
					E('div', { 'class': 'cm-bub-text' }, b.text)));
		});
		if (!this.ussdLog.length)
			bubbles = [ E('div', { 'class': 'cm-msg-empty' }, E('em', {}, _('Send a service code, e.g. *100#'))) ];
		var input = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': this.ussdActive ? _('Reply to menu') : '*100#', 'style': 'flex:1', 'keydown': function(ev) { if (ev.keyCode === 13) self.ussdSend(input); } });
		var foot = E('div', { 'class': 'cm-th-compose' }, [
			this.ussdActive ? E('button', { 'class': 'cm-icon-btn cm-danger', 'title': _('Cancel USSD'), 'click': ui.createHandlerFn(self, 'ussdCancel') }, cm.icon('x')) : '',
			input,
			E('button', { 'class': 'cm-send-btn', 'aria-label': _('Send'), 'click': ui.createHandlerFn(self, 'ussdSend', input) }, cm.icon('send'))
		]);
		dom.content(this.elRight, [
			E('div', { 'class': 'cm-th-head cm-th-ussd' }, [ cm.icon('hash'), E('div', { 'class': 'cm-th-name', 'style': 'margin-left:8px' }, _('USSD')), E('div', { 'class': 'cm-th-sub', 'style': 'margin-left:auto' }, this.ussdActive ? _('session active') : '') ]),
			E('div', { 'class': 'cm-th-body' }, bubbles),
			foot
		]);
	},
	ussdParse: function(r) {
		// {raw:"...mmcli output..."} -> текст ответа сети
		var raw = (r && r.raw) || '';
		var m = raw.match(/'([^']*)'/);   // mmcli печатает ответ в кавычках
		return (m ? m[1] : raw).replace(/\\n/g, '\n').trim() || _('(no response)');
	},
	ussdSend: function(input) {
		var self = this, code = input.value;
		if (!code) return;
		input.value = '';
		this.ussdLog.push({ dir: 'out', text: code });
		var call = this.ussdActive ? cm.rpc.ussdRespond(code) : cm.rpc.sendUssd(code);
		this.renderUssd();
		return call.then(function(r) {
			if (r && r.error) self.ussdLog.push({ dir: 'in', text: _('Error') + ': ' + r.error });
			else { self.ussdLog.push({ dir: 'in', text: self.ussdParse(r) }); self.ussdActive = true; }
			self.renderUssd();
		});
	},
	ussdCancel: function() {
		var self = this;
		return cm.rpc.ussdCancel().then(function() {
			self.ussdActive = false;
			self.ussdLog.push({ dir: 'in', text: _('Session cancelled') });
			self.renderUssd();
		});
	}
});
