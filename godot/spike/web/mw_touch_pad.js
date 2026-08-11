/* MineWorld Web — dual virtual sticks + Gamepad direct bind.
 *
 * Why laser-on-stick worked before:
 *   Pico 2D Browser often treats physical sticks as ONE shared cursor.
 *   Hover virtual stick → stick moves cursor → pointer events → WASD.
 *   That cannot map L-stick→left pad and R-stick→right pad independently.
 *
 * Goal:
 *   If Gamepad API exposes axes → left stick = move, right stick = turn (no laser).
 *   Else fallback: laser + ↑↓←→ / F (and hover-drag sticks).
 */
(function () {
	if (window._mwTouchPad) return;
	window._mwTouchPad = true;
	window._mw_keys = window._mw_keys || Object.create(null);
	/* Gamepad polling runs as long as the script is loaded — independent of
	 * whether the virtual pad UI is shown. A desktop user with a real
	 * gamepad (pad UI hidden by default) must still get left-stick move. */
	window._MW_TOUCH_PAD_LOADED = true;

	var MOVE_CODES = ["KeyW", "KeyA", "KeyS", "KeyD"];
	var DEAD = 0.28;
	var GP_DEAD = 0.32;
	var gpUnlocked = false;
	var gpLive = false;
	var stickPtrL = null;
	var stickPtrR = null;
	var stickR = 58;
	var dirHeld = Object.create(null);
	var gpTurn = { q: false, e: false };
	var lastGpLog = 0;

	function qs(name) {
		try {
			return new URLSearchParams(location.search).get(name) || "";
		} catch (e) {
			return "";
		}
	}

	function coarsePointer() {
		try {
			if (window.matchMedia && matchMedia("(pointer: coarse)").matches) return true;
		} catch (e) { /* ignore */ }
		try {
			return /Pico|PICO|Android|Mobile|Quest|XR/i.test(navigator.userAgent || "");
		} catch (e2) { /* ignore */ }
		return false;
	}

	function wantPad() {
		var t = qs("touch").toLowerCase();
		if (t === "0" || t === "false" || t === "off") return false;
		if (t === "1" || t === "true" || t === "on") return true;
		try {
			var ls = localStorage.getItem("mw-touch-pad");
			if (ls === "0") return false;
			if (ls === "1") return true;
		} catch (e2) { /* ignore */ }
		/* Auto-enable only for real coarse-pointer/touch devices.
		 * Do NOT trust navigator.maxTouchPoints>0 alone (touchscreen laptops)
		 * or navigator.xr alone (desktop Chrome exposes WebXR without a headset):
		 * both would show the pad on a plain desktop browser and kill the mouse. */
		return coarsePointer();
	}

	function setKey(code, down) {
		window._mw_keys[code] = !!down;
	}

	function clearMove() {
		MOVE_CODES.forEach(function (c) {
			setKey(c, false);
		});
	}

	function stickInvertOn() {
		var inv = qs("stickInvert").toLowerCase();
		return inv !== "0" && inv !== "false" && inv !== "off";
	}

	function applyMoveStick(nx, ny) {
		if (stickInvertOn()) {
			nx = -nx;
			ny = -ny;
		}
		clearMove();
		if (ny < -DEAD) setKey("KeyW", true);
		if (ny > DEAD) setKey("KeyS", true);
		if (nx < -DEAD) setKey("KeyA", true);
		if (nx > DEAD) setKey("KeyD", true);
	}

	function applyTurnStick(nx) {
		if (stickInvertOn()) nx = -nx;
		var wantQ = nx < -DEAD;
		var wantE = nx > DEAD;
		if (wantQ !== gpTurn.q) {
			gpTurn.q = wantQ;
			setKey("KeyQ", wantQ);
		}
		if (wantE !== gpTurn.e) {
			gpTurn.e = wantE;
			setKey("KeyE", wantE);
		}
	}

	var root = document.createElement("div");
	root.id = "mw-touch-pad";
	/* Default chrome: two sticks + F/手柄 only. Dirs/QE/jump live under「更多」
	 * so we don't cover Hub chat / leaderboard / minimap in the corners. */
	root.innerHTML =
		'<button type="button" class="mw-tp-hide" id="mw-tp-hide">隐藏</button>' +
		'<button type="button" class="mw-tp-show" id="mw-tp-show">虚拟键</button>' +
		'<div class="mw-tp-banner" id="mw-tp-banner">左走 · 右转向 · 中 F</div>' +
		'<div class="mw-tp-stage">' +
		'<div class="mw-tp-stick" id="mw-tp-stick-l" data-role="move" aria-label="移动">' +
		'<div class="mw-tp-knob" id="mw-tp-knob-l"></div></div>' +
		'<div class="mw-tp-dock">' +
		'<button type="button" class="mw-tp-btn mw-tp-f" data-code="KeyF" data-hold="0">F 互动</button>' +
		'<button type="button" class="mw-tp-btn mw-tp-gp" id="mw-tp-enable-gp">启用双手柄</button>' +
		'<button type="button" class="mw-tp-btn mw-tp-more-btn" id="mw-tp-more-btn">更多</button>' +
		"</div>" +
		'<div class="mw-tp-stick" id="mw-tp-stick-r" data-role="turn" aria-label="转向">' +
		'<div class="mw-tp-knob" id="mw-tp-knob-r"></div></div>' +
		"</div>" +
		'<div class="mw-tp-more" id="mw-tp-more">' +
		'<div class="mw-tp-dirs">' +
		'<button type="button" class="mw-tp-dir" data-code="KeyW" data-hold="1">↑</button>' +
		'<div class="mw-tp-dir-row">' +
		'<button type="button" class="mw-tp-dir" data-code="KeyA" data-hold="1">←</button>' +
		'<button type="button" class="mw-tp-dir" data-code="KeyS" data-hold="1">↓</button>' +
		'<button type="button" class="mw-tp-dir" data-code="KeyD" data-hold="1">→</button>' +
		"</div></div>" +
		'<div class="mw-tp-extra">' +
		'<button type="button" class="mw-tp-btn" data-code="KeyQ" data-hold="1">Q 左</button>' +
		'<button type="button" class="mw-tp-btn" data-code="KeyE" data-hold="1">E 右</button>' +
		'<button type="button" class="mw-tp-btn" data-code="Space" data-hold="0">跳</button>' +
		"</div></div>";

	var style = document.createElement("style");
	style.textContent =
		/* Above Hub HTML HUD (chat/lb z=…646); below only visitor shell when open. */
		"#mw-touch-pad{display:none;position:fixed;inset:0;pointer-events:none;z-index:2147483647;" +
		"font:600 14px ui-sans-serif,system-ui,sans-serif;user-select:none;-webkit-user-select:none;}" +
		"#mw-touch-pad.mw-tp-on{display:block;}" +
		"#mw-touch-pad.mw-tp-on.mw-tp-collapsed .mw-tp-stage," +
		"#mw-touch-pad.mw-tp-on.mw-tp-collapsed .mw-tp-more," +
		"#mw-touch-pad.mw-tp-on.mw-tp-collapsed .mw-tp-banner," +
		"#mw-touch-pad.mw-tp-on.mw-tp-collapsed .mw-tp-hide{display:none;}" +
		"#mw-touch-pad .mw-tp-show{display:none;pointer-events:auto;position:absolute;left:50%;bottom:18px;" +
		"transform:translateX(-50%);padding:10px 14px;border-radius:10px;border:1px solid rgba(109,176,255,0.55);" +
		"background:rgba(12,40,80,0.55);color:#fff;font:700 14px sans-serif;}" +
		"#mw-touch-pad.mw-tp-on.mw-tp-collapsed .mw-tp-show{display:block;}" +
		"#mw-touch-pad .mw-tp-hide{pointer-events:auto;position:absolute;left:50%;top:10px;transform:translateX(-50%);" +
		"padding:5px 10px;border-radius:8px;border:1px solid rgba(120,140,160,0.35);background:rgba(0,0,0,0.28);" +
		"color:rgba(220,230,240,0.85);font:600 11px sans-serif;}" +
		"#mw-touch-pad .mw-tp-banner{pointer-events:none;position:absolute;left:50%;top:40px;transform:translateX(-50%);" +
		"max-width:min(360px,70vw);padding:4px 10px;border-radius:8px;background:rgba(0,0,0,0.28);color:rgba(235,245,255,0.9);" +
		"font-size:11px;text-align:center;}" +
		"#mw-touch-pad.mw-tp-gp-live .mw-tp-banner{background:rgba(20,70,130,0.35);}" +
		"#mw-touch-pad .mw-tp-stage{position:absolute;inset:0;pointer-events:none;}" +
		/* Vertical center, flush left/right edges. */
		"#mw-touch-pad #mw-tp-stick-l,#mw-touch-pad #mw-tp-stick-r{pointer-events:auto;position:absolute;top:50%;" +
		"width:160px;height:160px;margin-top:-80px;border-radius:50%;background:rgba(8,14,24,0.18);" +
		"border:2px solid rgba(200,220,255,0.45);touch-action:none;}" +
		"#mw-touch-pad #mw-tp-stick-l{left:max(8px,env(safe-area-inset-left));}" +
		"#mw-touch-pad #mw-tp-stick-r{right:max(8px,env(safe-area-inset-right));}" +
		"#mw-touch-pad .mw-tp-knob{position:absolute;left:50%;top:50%;width:60px;height:60px;margin:-30px 0 0 -30px;" +
		"border-radius:50%;background:rgba(61,139,253,0.45);border:2px solid rgba(255,255,255,0.4);}" +
		"#mw-touch-pad .mw-tp-dock{pointer-events:none;position:absolute;left:50%;bottom:max(20px,env(safe-area-inset-bottom));" +
		"transform:translateX(-50%);display:flex;flex-direction:column;align-items:center;gap:8px;min-width:112px;}" +
		"#mw-touch-pad .mw-tp-dir,#mw-touch-pad .mw-tp-btn{pointer-events:auto;touch-action:none;cursor:pointer;" +
		"border:1px solid rgba(170,200,240,0.32);background:rgba(8,12,20,0.28);color:#e8eefc;border-radius:12px;}" +
		"#mw-touch-pad .mw-tp-btn{min-height:40px;padding:6px 10px;font:700 13px sans-serif;}" +
		"#mw-touch-pad .mw-tp-f{min-width:112px;min-height:54px;font-size:16px;background:rgba(20,70,140,0.5);}" +
		"#mw-touch-pad .mw-tp-gp{min-width:112px;background:rgba(12,90,48,0.42);font-size:12px;}" +
		"#mw-touch-pad .mw-tp-more-btn{min-width:112px;font-size:12px;background:rgba(0,0,0,0.28);}" +
		"#mw-touch-pad .mw-tp-more{display:none;pointer-events:none;position:absolute;left:50%;bottom:max(160px,22vh);" +
		"transform:translateX(-50%);width:min(420px,72vw);padding:8px;border-radius:14px;background:rgba(0,0,0,0.32);" +
		"justify-content:center;align-items:center;gap:14px;}" +
		"#mw-touch-pad.mw-tp-more-open .mw-tp-more{display:flex;}" +
		"#mw-touch-pad .mw-tp-dirs{pointer-events:none;display:flex;flex-direction:column;align-items:center;gap:4px;}" +
		"#mw-touch-pad .mw-tp-dir-row{display:flex;gap:4px;}" +
		"#mw-touch-pad .mw-tp-dir{width:46px;height:38px;font:700 17px/1 sans-serif;}" +
		"#mw-touch-pad .mw-tp-extra{pointer-events:none;display:flex;gap:6px;}" +
		"#mw-touch-pad .mw-tp-dir.mw-tp-down,#mw-touch-pad .mw-tp-btn.mw-tp-down{background:rgba(61,139,253,0.65);}" +
		"#mw-visitor-shell.open ~ #mw-touch-pad{visibility:hidden;}" +
		"body.mw-tp-canvas-lock #canvas{pointer-events:none !important;}";

	function setKnob(id, dx, dy) {
		var knob = document.getElementById(id);
		if (!knob) return;
		knob.style.transform = "translate(" + dx + "px," + dy + "px)";
	}

	function recomputeMoveFromDirs() {
		if (dirHeld.KeyW || dirHeld.KeyA || dirHeld.KeyS || dirHeld.KeyD) {
			setKey("KeyW", !!dirHeld.KeyW);
			setKey("KeyA", !!dirHeld.KeyA);
			setKey("KeyS", !!dirHeld.KeyS);
			setKey("KeyD", !!dirHeld.KeyD);
		}
	}

	function syncCanvasLock() {
		var shown =
			root.classList.contains("mw-tp-on") &&
			!root.classList.contains("mw-tp-collapsed");
		/* Lock the canvas ONLY on coarse-pointer devices; a fine mouse must
		 * keep driving the canvas even when the pad is shown (?touch=1 desktop). */
		var lock = shown && coarsePointer();
		window._MW_CANVAS_LOCKED = lock;
		document.body.classList.toggle("mw-tp-canvas-lock", lock);
	}

	function setBanner(text, gpOk) {
		var banner = document.getElementById("mw-tp-banner");
		if (!banner) return;
		banner.textContent = text;
		root.classList.toggle("mw-tp-gp-live", !!gpOk);
	}

	function mount() {
		if (!document.body) return;
		if (!style.parentNode) document.head.appendChild(style);
		/* Last in body: win stacking vs Hub chat (z …646). */
		document.body.appendChild(root);
		root.classList.add("mw-tp-on");
		if (wantPad()) root.classList.remove("mw-tp-collapsed");
		else root.classList.add("mw-tp-collapsed");
		syncCanvasLock();
	}

	function bindHoldButton(el) {
		var code = el.getAttribute("data-code");
		if (!code) return;
		var hold = el.getAttribute("data-hold") === "1";
		var ptr = null;
		function down(ev) {
			if (ptr != null) return;
			ptr = ev.pointerId;
			el.classList.add("mw-tp-down");
			if (code === "KeyW" || code === "KeyA" || code === "KeyS" || code === "KeyD") {
				dirHeld[code] = true;
				recomputeMoveFromDirs();
			} else setKey(code, true);
			try {
				el.setPointerCapture(ev.pointerId);
			} catch (e) { /* ignore */ }
			ev.preventDefault();
			ev.stopPropagation();
		}
		function up(ev) {
			if (ptr != null && ev.pointerId !== ptr) return;
			ptr = null;
			el.classList.remove("mw-tp-down");
			if (code === "KeyW" || code === "KeyA" || code === "KeyS" || code === "KeyD") {
				dirHeld[code] = false;
				recomputeMoveFromDirs();
				if (!dirHeld.KeyW && !dirHeld.KeyA && !dirHeld.KeyS && !dirHeld.KeyD) clearMove();
			} else setKey(code, false);
			ev.preventDefault();
			ev.stopPropagation();
		}
		el.addEventListener("pointerdown", down);
		el.addEventListener("pointerup", up);
		el.addEventListener("pointercancel", up);
		if (!hold) {
			el.addEventListener("pointerdown", function () {
				setKey(code, true);
				setTimeout(function () {
					if (ptr == null) setKey(code, false);
				}, 100);
			});
		}
	}

	function bindStickEl(stickId, knobId, role) {
		var stick = document.getElementById(stickId);
		if (!stick) return;
		var isMove = role === "move";
		function onDown(ev) {
			if (isMove) {
				if (stickPtrL != null) return;
				stickPtrL = ev.pointerId;
			} else {
				if (stickPtrR != null) return;
				stickPtrR = ev.pointerId;
			}
			try {
				stick.setPointerCapture(ev.pointerId);
			} catch (e) { /* ignore */ }
			onMove(ev);
			ev.preventDefault();
			ev.stopPropagation();
		}
		function onMove(ev) {
			var mine = isMove ? stickPtrL : stickPtrR;
			if (ev.pointerId !== mine) return;
			var rect = stick.getBoundingClientRect();
			var cx = rect.left + rect.width / 2;
			var cy = rect.top + rect.height / 2;
			var dx = ev.clientX - cx;
			var dy = ev.clientY - cy;
			var len = Math.sqrt(dx * dx + dy * dy) || 1;
			if (len > stickR) {
				dx = (dx / len) * stickR;
				dy = (dy / len) * stickR;
			}
			setKnob(knobId, dx, dy);
			var anyDir = dirHeld.KeyW || dirHeld.KeyA || dirHeld.KeyS || dirHeld.KeyD;
			if (isMove) {
				if (!anyDir && !gpLive) applyMoveStick(dx / stickR, dy / stickR);
			} else if (!gpLive) {
				applyTurnStick(dx / stickR);
			}
			ev.preventDefault();
		}
		function onUp(ev) {
			var mine = isMove ? stickPtrL : stickPtrR;
			if (ev.pointerId !== mine) return;
			if (isMove) stickPtrL = null;
			else stickPtrR = null;
			setKnob(knobId, 0, 0);
			if (isMove) {
				var anyDir = dirHeld.KeyW || dirHeld.KeyA || dirHeld.KeyS || dirHeld.KeyD;
				if (!anyDir && !gpLive) clearMove();
			} else if (!gpLive) {
				applyTurnStick(0);
			}
			ev.preventDefault();
		}
		stick.addEventListener("pointerdown", onDown);
		stick.addEventListener("pointermove", onMove);
		stick.addEventListener("pointerup", onUp);
		stick.addEventListener("pointercancel", onUp);
	}

	function readPad() {
		if (!navigator.getGamepads) return null;
		var pads = navigator.getGamepads();
		if (!pads) return null;
		for (var i = 0; i < pads.length; i++) {
			if (pads[i]) return pads[i];
		}
		return null;
	}

	function pollGamepad() {
		if (!window._MW_TOUCH_PAD_LOADED) return;
		var p = readPad();
		if (!p) {
			if (gpLive) {
				gpLive = false;
				setBanner(
					"未读到 Gamepad · 请点「启用双手柄」；或激光点住左/右虚拟摇杆再推实体摇杆",
					false
				);
			}
			return;
		}
		var ax = p.axes || [];
		var lx = ax.length > 0 ? Number(ax[0]) || 0 : 0;
		var ly = ax.length > 1 ? Number(ax[1]) || 0 : 0;
		var rx = ax.length > 2 ? Number(ax[2]) || 0 : 0;
		var ry = ax.length > 3 ? Number(ax[3]) || 0 : 0;
		/* Some Pico layouts put right stick on axes 2/5 or only 2/3. */
		if (ax.length >= 5 && Math.abs(ax[2]) < 0.05 && Math.abs(ax[3]) < 0.05) {
			if (Math.abs(ax[4]) > 0.05 || Math.abs(ax[5]) > 0.05) {
				rx = Number(ax[4]) || 0;
				ry = Number(ax[5]) || 0;
			}
		}
		var moving =
			Math.abs(lx) > GP_DEAD ||
			Math.abs(ly) > GP_DEAD ||
			Math.abs(rx) > GP_DEAD ||
			Math.abs(ry) > GP_DEAD;
		if (!gpUnlocked && !moving) return;

		gpLive = true;
		gpUnlocked = true;
		var anyDir = dirHeld.KeyW || dirHeld.KeyA || dirHeld.KeyS || dirHeld.KeyD;
		if (!anyDir && stickPtrL == null) {
			if (Math.abs(lx) > GP_DEAD || Math.abs(ly) > GP_DEAD) {
				applyMoveStick(lx, ly);
				setKnob("mw-tp-knob-l", lx * stickR, ly * stickR);
			} else {
				clearMove();
				setKnob("mw-tp-knob-l", 0, 0);
			}
		}
		if (stickPtrR == null) {
			if (Math.abs(rx) > GP_DEAD) {
				applyTurnStick(rx);
				setKnob("mw-tp-knob-r", rx * stickR, 0);
			} else {
				applyTurnStick(0);
				setKnob("mw-tp-knob-r", 0, 0);
			}
		}
		var btns = p.buttons || [];
		var fDown =
			(btns[0] && (btns[0].pressed || btns[0].value > 0.5)) ||
			(btns[2] && (btns[2].pressed || btns[2].value > 0.5)) ||
			(btns[7] && (btns[7].pressed || btns[7].value > 0.5));
		setKey("KeyF", !!fDown);

		var now = Date.now();
		if (now - lastGpLog > 2000) {
			lastGpLog = now;
			setBanner(
				"Gamepad 已接 · 左摇杆走 · 右摇杆转 · 无需激光（id=" +
					String(p.id || "").slice(0, 28) +
					"）",
				true
			);
			console.log("[MW] gamepad", p.id, "axes", ax.length, ax);
		}
	}

	function unlockGamepad(ev) {
		gpUnlocked = true;
		/* User gesture: some browsers only then populate getGamepads(). */
		var p = readPad();
		setBanner(
			p
				? "已尝试启用 · 请推左右摇杆测试（绿条变蓝=成功）"
				: "未检测到 Gamepad API · 仍可用激光点虚拟摇杆 / ↑↓←→",
			!!p
		);
		console.log("[MW] unlockGamepad", p && p.id, navigator.getGamepads && navigator.getGamepads());
		if (ev) {
			ev.preventDefault();
			ev.stopPropagation();
		}
	}

	function boot() {
		mount();
		root.querySelectorAll(".mw-tp-dir, .mw-tp-btn").forEach(bindHoldButton);
		bindStickEl("mw-tp-stick-l", "mw-tp-knob-l", "move");
		bindStickEl("mw-tp-stick-r", "mw-tp-knob-r", "turn");
		var en = document.getElementById("mw-tp-enable-gp");
		if (en) en.addEventListener("pointerdown", unlockGamepad);
		var moreBtn = document.getElementById("mw-tp-more-btn");
		if (moreBtn) {
			moreBtn.addEventListener("click", function (ev) {
				root.classList.toggle("mw-tp-more-open");
				moreBtn.textContent = root.classList.contains("mw-tp-more-open")
					? "收起"
					: "更多";
				ev.preventDefault();
			});
		}
		window.addEventListener("gamepadconnected", function (e) {
			gpUnlocked = true;
			setBanner("手柄已连接 · 左走右转", true);
			console.log("[MW] gamepadconnected", e.gamepad && e.gamepad.id);
		});
		var hideBtn = document.getElementById("mw-tp-hide");
		var showBtn = document.getElementById("mw-tp-show");
		if (hideBtn) {
			hideBtn.addEventListener("click", function (ev) {
				root.classList.add("mw-tp-collapsed");
				root.classList.remove("mw-tp-more-open");
				try {
					localStorage.setItem("mw-touch-pad", "0");
				} catch (e) { /* ignore */ }
				clearMove();
				syncCanvasLock();
				ev.preventDefault();
			});
		}
		if (showBtn) {
			showBtn.addEventListener("click", function (ev) {
				try {
					localStorage.setItem("mw-touch-pad", "1");
				} catch (e) { /* ignore */ }
				root.classList.remove("mw-tp-collapsed");
				syncCanvasLock();
				ev.preventDefault();
			});
		}
		new MutationObserver(syncCanvasLock).observe(document.body, {
			attributes: true,
			attributeFilter: ["class"],
		});
		window.addEventListener("blur", function () {
			clearMove();
			["KeyQ", "KeyE", "KeyF", "Space"].forEach(function (c) {
				setKey(c, false);
			});
			dirHeld = Object.create(null);
			setKnob("mw-tp-knob-l", 0, 0);
			setKnob("mw-tp-knob-r", 0, 0);
			stickPtrL = stickPtrR = null;
		});
		function loop() {
			pollGamepad();
			requestAnimationFrame(loop);
		}
		requestAnimationFrame(loop);
		setBanner("左走 · 右转向 · 中 F（可点启用双手柄）", false);
		console.log("[MW] dual-stick pad · raised above HUD · gamepad preferred");
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", boot);
	} else {
		boot();
	}
})();
