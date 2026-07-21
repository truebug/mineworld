/**
 * MineWorld CN-first i18n (localStorage.mw_lang = zh|en).
 * Usage: data-i18n="key" on elements; MW_I18N.t(key); MW_I18N.apply(); MW_I18N.mountToggle(parent).
 */
(function (global) {
	var KEY = 'mw_lang';
	var dict = {
		'boot.sub': { zh: '母港 Hangar Core', en: 'Hangar Core' },
		'boot.hint': { zh: '加载中…', en: 'Loading…' },
		'tr.skip': { zh: 'Enter / 点击跳过', en: 'Enter / click to skip' },
		'hud.connecting': { zh: 'MineWorld · 连接中…', en: 'MineWorld · connecting…' },
		'hub.pilot': { zh: '飞行员卡', en: 'Pilot card' },
		'hub.nick': { zh: '昵称', en: 'Nickname' },
		'hub.me': { zh: '我的战绩', en: 'My record' },
		'hub.admin': { zh: '管理', en: 'Admin' },
		'hub.map': { zh: '母港图 · 东A橙 · 西B蓝 · 北C · 西偏北D · 南E', en: 'Hub map · A orange · B blue · C north · D NW · E south' },
		'hub.lb': { zh: '排行榜', en: 'Leaderboard' },
		'hub.success': { zh: '通关', en: 'SUCCESS' },
		'hub.me_link': { zh: '我的战绩 →', en: 'My record →' },
		'hub.seed': { zh: '种子', en: 'seed' },
		'hub.regen': { zh: '重生', en: 'Regen' },
		'hub.random': { zh: '随机', en: 'Random' },
		'hub.joints': { zh: '臂 / 爪', en: 'Arm / gripper' },
		'land.tag': { zh: '数聚球母港', en: 'Mothership Hangar' },
		'land.lede': {
			zh: '真机甲 · 真任务 · 可训练的遥操数据。进入母港大厅，或从门后打开仿真卡片。',
			en: 'True mechs. Real tasks. Teleop data that trains. Enter the hangar — or open a simulation card beyond the doors.'
		},
		'land.signin': { zh: '登录', en: 'Sign in' },
		'land.record': { zh: '飞行员档案', en: 'Pilot record' },
		'land.enter': { zh: '进入母港', en: 'Enter hangar' },
		'land.profile': { zh: '档案与排行', en: 'Profile & board' },
		'land.foot': { zh: '数聚球 · 仿真门户 · ', en: 'Databall · simulation portal · ' },
		'login.sub': { zh: '母港 · 门户', en: 'Hangar · Portal' },
		'login.player': { zh: '玩家 ID', en: 'Player ID' },
		'login.password': { zh: '密码', en: 'Password' },
		'login.submit': { zh: '登录', en: 'Sign in' },
		'login.hint': {
			zh: '本地演示：demo / demo。登录后 → 档案与排行，再进入母港。',
			en: 'Local demo: demo / demo. After sign-in → Profile & board, then Enter hangar.'
		},
		'login.landing': { zh: '首页', en: 'Landing' },
		'login.profile': { zh: '档案', en: 'Profile' }
	};

	function lang() {
		try {
			var v = localStorage.getItem(KEY);
			if (v === 'en' || v === 'zh') {
				return v;
			}
		} catch (e) { /* ignore */ }
		return 'zh';
	}

	function setLang(next) {
		var v = next === 'en' ? 'en' : 'zh';
		try {
			localStorage.setItem(KEY, v);
		} catch (e) { /* ignore */ }
		document.documentElement.lang = v === 'zh' ? 'zh-CN' : 'en';
		apply();
		try {
			global.dispatchEvent(new CustomEvent('mw-lang', { detail: { lang: v } }));
		} catch (e2) { /* ignore */ }
		return v;
	}

	function t(key) {
		var row = dict[key];
		if (!row) {
			return key;
		}
		return row[lang()] || row.zh || key;
	}

	function apply(root) {
		var scope = root || document;
		var nodes = scope.querySelectorAll('[data-i18n]');
		for (var i = 0; i < nodes.length; i++) {
			var el = nodes[i];
			var k = el.getAttribute('data-i18n');
			if (!k) {
				continue;
			}
			var attr = el.getAttribute('data-i18n-attr');
			var val = t(k);
			if (attr) {
				el.setAttribute(attr, val);
			} else {
				el.textContent = val;
			}
		}
		var toggle = document.getElementById('mw-lang-toggle');
		if (toggle) {
			toggle.textContent = lang() === 'zh' ? 'EN' : '中文';
			toggle.setAttribute('aria-label', lang() === 'zh' ? 'Switch to English' : '切换到中文');
		}
	}

	function mountToggle(parent) {
		var host = parent || document.body;
		if (document.getElementById('mw-lang-toggle')) {
			apply();
			return;
		}
		var btn = document.createElement('button');
		btn.type = 'button';
		btn.id = 'mw-lang-toggle';
		btn.style.cssText =
			'position:fixed;top:12px;right:12px;z-index:2147483647;padding:6px 10px;' +
			'border:1px solid rgba(180,200,220,0.35);border-radius:4px;background:rgba(10,14,22,0.85);' +
			'color:#e6edf5;font:600 12px/1 ui-sans-serif,system-ui,sans-serif;cursor:pointer;letter-spacing:0.06em;';
		btn.addEventListener('click', function () {
			setLang(lang() === 'zh' ? 'en' : 'zh');
		});
		host.appendChild(btn);
		document.documentElement.lang = lang() === 'zh' ? 'zh-CN' : 'en';
		apply();
	}

	global.MW_I18N = {
		t: t,
		lang: lang,
		setLang: setLang,
		apply: apply,
		mountToggle: mountToggle,
		dict: dict
	};
})(typeof window !== 'undefined' ? window : this);
