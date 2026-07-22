/**
 * MineWorld CN-first i18n (localStorage.mw_lang = zh|en).
 * Usage: data-i18n="key" on elements; MW_I18N.t(key); MW_I18N.apply(); MW_I18N.mountToggle(parent).
 */
(function (global) {
	var KEY = 'mw_lang';
	var dict = {
		'boot.sub': { zh: '母港', en: 'Hangar Core' },
		'boot.hint': { zh: '加载中…', en: 'Loading…' },
		'tr.skip': { zh: 'Enter / 点击跳过', en: 'Enter / click to skip' },
		'hud.connecting': { zh: 'MineWorld · 连接中…', en: 'MineWorld · connecting…' },
		'hub.pilot': { zh: '驾驶员卡', en: 'Pilot card' },
		'hub.pilot_id': { zh: '驾驶员 · ID ', en: 'Pilot · ID ' },
		'hub.you': { zh: '你', en: 'you' },
		'hub.alone': { zh: '独自', en: 'alone' },
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
		'land.tag': { zh: '机甲学院母港', en: 'Mech Academy Hangar' },
		'land.lede': {
			zh: '真机甲 · 真任务 · 可训练的遥操数据。进入母港大厅，或从门后打开仿真卡片。',
			en: 'True mechs. Real tasks. Teleop data that trains. Enter the hangar — or open a simulation card beyond the doors.'
		},
		'land.signin': { zh: '登录', en: 'Sign in' },
		'land.record': { zh: '驾驶员档案', en: 'Pilot record' },
		'land.enter': { zh: '进入母港', en: 'Enter hangar' },
		'land.profile': { zh: '档案与排行', en: 'Profile & board' },
		'land.foot': { zh: '云端机甲学院 · ', en: 'Cloud Mech Academy · ' },
		'login.sub': { zh: '母港 · 门户', en: 'Hangar · Portal' },
		'login.player': { zh: '玩家 ID', en: 'Player ID' },
		'login.password': { zh: '密码', en: 'Password' },
		'login.submit': { zh: '登录', en: 'Sign in' },
		'login.landing': { zh: '首页', en: 'Landing' },
		'login.profile': { zh: '档案', en: 'Profile' },
		'me.sub': { zh: '驾驶员档案', en: 'Pilot profile' },
		'me.enter': { zh: '进入母港', en: 'Enter hangar' },
		'me.pts': { zh: '总积分', en: 'Total points' },
		'me.runs': { zh: '计分局数', en: 'Scored runs' },
		'me.wins': { zh: '通关次数', en: 'Success' },
		'me.lb': { zh: '排行榜', en: 'Leaderboard' },
		'me.sessions': { zh: '最近对局', en: 'Recent sessions' },
		'me.th.level': { zh: '关卡', en: 'Level' },
		'me.th.pts': { zh: '分', en: 'Pts' },
		'me.th.time': { zh: '时长', en: 'Time' },
		'me.th.when': { zh: '时间', en: 'When' },
		'me.th.replay': { zh: '回放', en: 'Replay' },
		'me.landing': { zh: '← 首页', en: '← Landing' },
		'me.recordings': { zh: '录制', en: 'Recordings' },
		'me.logout': { zh: '退出登录', en: 'Sign out' },
		'me.loading': { zh: '加载中…', en: 'Loading…' },
		'me.empty_scores': { zh: '暂无计分 — 去工坊或训练场通关。', en: 'No scored runs yet — clear Workshop or Training.' },
		'me.empty_lb': { zh: '暂无积分', en: 'No scores yet' },
		'me.lb_fail': { zh: '排行榜不可用', en: 'Leaderboard unavailable' },
		'me.fail': { zh: '加载失败', en: 'Failed' },
		'me.no_rec': { zh: '无录制', en: 'no rec' },
		'admin.title': { zh: '管理 · 运维', en: 'Admin · ops' },
		'admin.key': { zh: '管理密钥', en: 'Admin key' },
		'admin.load': { zh: '加载玩家', en: 'Load players' },
		'admin.refresh': { zh: '刷新房间 / 关卡', en: 'Refresh rooms / levels' },
		'admin.save_key': { zh: '记住密钥', en: 'Remember key' },
		'admin.rooms': { zh: '在线房间（只读）', en: 'Live rooms (read-only)' },
		'admin.levels': { zh: '关卡（禁用会阻止新 join）', en: 'Levels (disable blocks new joins)' },
		'admin.create': { zh: '创建玩家', en: 'Create player' },
		'admin.create_btn': { zh: '创建', en: 'Create' },
		'admin.th.room': { zh: '房间', en: 'Room' },
		'admin.th.level': { zh: '关卡', en: 'Level' },
		'admin.th.members': { zh: '人数', en: 'Members' },
		'admin.th.tick': { zh: 'Tick', en: 'Tick' },
		'admin.th.hub': { zh: 'Hub', en: 'Hub' },
		'admin.th.status': { zh: '状态', en: 'Status' },
		'admin.th.id': { zh: 'ID', en: 'ID' },
		'admin.th.name': { zh: '名称', en: 'Name' },
		'admin.th.accent': { zh: '配色', en: 'Accent' },
		'admin.refresh_hint': { zh: '请刷新房间 / 关卡', en: 'Refresh rooms / levels' },
		'admin.load_hint': { zh: '用管理密钥加载', en: 'Load with admin key' },
		'admin.key_saved': { zh: '密钥已保存在本地。', en: 'Key saved locally.' },
		'admin.no_rooms': { zh: '无在线房间', en: 'No live rooms' },
		'admin.city_seed': { zh: '城市场景种子：用游戏壳或 POST /api/city-block。', en: 'City seed regen: use in-game shell or POST /api/city-block.' },
		'admin.sessions': { zh: '对局 ·', en: 'Sessions ·' },
		'admin.export_ok': { zh: '导出 CSV（通关）', en: 'Export CSV (success)' },
		'admin.export_all': { zh: '导出 CSV（全部）', en: 'Export CSV (all)' },
		'admin.no_rec_player': { zh: '该玩家无录制（需 header player_id）', en: 'No recordings for this player (need header player_id)' },
		'admin.hub': { zh: '母港', en: 'Hub' },
		'admin.me': { zh: '我的战绩', en: 'My record' },
		'admin.recs': { zh: '录制', en: 'Recordings' },
		'admin.err_auth': { zh: '鉴权失败或无权', en: 'Unauthorized or forbidden' },
		'admin.err_http': { zh: '请求失败', en: 'Request failed' },
		'admin.created': { zh: '已创建', en: 'Created' },
		'admin.disable': { zh: '禁用', en: 'Disable' },
		'admin.enable': { zh: '启用', en: 'Enable' },
		'admin.enabled': { zh: '启用', en: 'enabled' },
		'admin.disabled': { zh: '禁用', en: 'disabled' }
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
			/* Godot Label3D is built once — reload shell so 3D labels match. */
			if (
				document.body.classList.contains('mw-hub') ||
				document.body.classList.contains('mw-play')
			) {
				location.reload();
			}
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
