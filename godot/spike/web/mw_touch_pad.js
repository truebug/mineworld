/* MineWorld Web — virtual stick + F/Q/E/Space for Pico laser / touch.
 * Writes window._mw_keys (same mirror MWWebInput polls). ?touch=1 force on,
 * ?touch=0 force off; else auto on Pico / coarse pointer / touch.
 */
(function () {
	if (window._mwTouchPad) return;
	window._mwTouchPad = true;
	window._mw_keys = window._mw_keys || Object.create(null);

	var MOVE_CODES = ["KeyW", "KeyA", "KeyS", "KeyD"];
	var DEAD = 0.28;

	function qs(name) {
		try {
			return new URLSearchParams(location.search).get(name) || "";
		} catch (e) {
			return "";
		}
	}

	function shouldEnable() {
		var t = qs("touch").toLowerCase();
		if (t === "0" || t === "false" || t === "off") return false;
		if (t === "1" || t === "true" || t === "on") return true;
		var ua = navigator.userAgent || "";
		if (/Pico|PICO|Android|Mobile/i.test(ua)) return true;
		if (navigator.maxTouchPoints > 0) return true;
		try {
			if (window.matchMedia && matchMedia("(pointer: coarse)").matches) return true;
		} catch (e2) { /* ignore */ }
		return false;
	}

	function setKey(code, down) {
		window._mw_keys[code] = !!down;
	}

	function clearMove() {
		MOVE_CODES.forEach(function (c) {
			setKey(c, false);
		});
	}

	function applyStick(nx, ny) {
		clearMove();
		if (ny < -DEAD) setKey("KeyW", true);
		if (ny > DEAD) setKey("KeyS", true);
		if (nx < -DEAD) setKey("KeyA", true);
		if (nx > DEAD) setKey("KeyD", true);
	}

	function inPlay() {
		return (
			document.body.classList.contains("mw-hub") ||
			document.body.classList.contains("mw-play")
		);
	}

	var root = document.createElement("div");
	root.id = "mw-touch-pad";
	root.setAttribute("aria-hidden", "true");
	root.innerHTML =
		'<div class="mw-tp-stick" id="mw-tp-stick">' +
		'<div class="mw-tp-knob" id="mw-tp-knob"></div>' +
		'<div class="mw-tp-hint">MOVE</div>' +
		"</div>" +
		'<div class="mw-tp-btns">' +
		'<button type="button" class="mw-tp-btn" data-code="KeyQ" data-hold="1">Q</button>' +
		'<button type="button" class="mw-tp-btn" data-code="KeyE" data-hold="1">E</button>' +
		'<button type="button" class="mw-tp-btn mw-tp-f" data-code="KeyF" data-hold="0">F</button>' +
		'<button type="button" class="mw-tp-btn" data-code="Space" data-hold="0">⤒</button>' +
		"</div>";

	var style = document.createElement("style");
	style.textContent =
		"#mw-touch-pad{" +
		"display:none;position:fixed;inset:0;pointer-events:none;z-index:2147483644;" +
		"font:600 14px ui-sans-serif,system-ui,sans-serif;user-select:none;-webkit-user-select:none;" +
		"}" +
		"body.mw-hub #mw-touch-pad.mw-tp-on,body.mw-play #mw-touch-pad.mw-tp-on{display:block;}" +
		"#mw-touch-pad .mw-tp-stick{" +
		"pointer-events:auto;position:absolute;left:max(12px,env(safe-area-inset-left));" +
		"bottom:max(16px,env(safe-area-inset-bottom));width:148px;height:148px;" +
		"border-radius:50%;background:rgba(8,12,20,0.55);border:2px solid rgba(120,160,220,0.45);" +
		"touch-action:none;" +
		"}" +
		"#mw-touch-pad .mw-tp-knob{" +
		"position:absolute;left:50%;top:50%;width:56px;height:56px;margin:-28px 0 0 -28px;" +
		"border-radius:50%;background:rgba(61,139,253,0.85);border:2px solid rgba(255,255,255,0.35);" +
		"box-shadow:0 2px 10px rgba(0,0,0,0.45);" +
		"}" +
		"#mw-touch-pad .mw-tp-hint{" +
		"position:absolute;left:0;right:0;bottom:8px;text-align:center;" +
		"font-size:11px;letter-spacing:0.08em;color:rgba(180,200,230,0.75);pointer-events:none;" +
		"}" +
		"#mw-touch-pad .mw-tp-btns{" +
		"pointer-events:none;position:absolute;right:max(12px,env(safe-area-inset-right));" +
		"bottom:max(16px,env(safe-area-inset-bottom));display:grid;" +
		"grid-template-columns:64px 64px;gap:10px;" +
		"}" +
		"#mw-touch-pad .mw-tp-btn{" +
		"pointer-events:auto;width:64px;height:64px;border-radius:16px;border:2px solid rgba(120,160,220,0.5);" +
		"background:rgba(8,12,20,0.7);color:#e8eefc;font:700 20px ui-sans-serif,system-ui,sans-serif;" +
		"touch-action:none;cursor:pointer;" +
		"}" +
		"#mw-touch-pad .mw-tp-btn:active,#mw-touch-pad .mw-tp-btn.mw-tp-down{" +
		"background:rgba(61,139,253,0.9);border-color:#8ec5ff;" +
		"}" +
		"#mw-touch-pad .mw-tp-f{grid-column:1 / span 2;width:138px;height:56px;font-size:22px;}" +
		"#mw-visitor-shell.open ~ #mw-touch-pad{display:none !important;}";

	function mount() {
		if (!document.body) return;
		if (!style.parentNode) document.head.appendChild(style);
		if (!root.parentNode) document.body.appendChild(root);
		if (shouldEnable()) root.classList.add("mw-tp-on");
		else root.classList.remove("mw-tp-on");
		root.setAttribute("aria-hidden", root.classList.contains("mw-tp-on") ? "false" : "true");
	}

	var stick = null;
	var knob = null;
	var stickPtr = null;
	var stickR = 46;

	function setKnob(dx, dy) {
		if (!knob) return;
		knob.style.transform = "translate(" + dx + "px," + dy + "px)";
	}

	function bindStick() {
		stick = document.getElementById("mw-tp-stick");
		knob = document.getElementById("mw-tp-knob");
		if (!stick) return;

		function onDown(ev) {
			if (stickPtr != null) return;
			stickPtr = ev.pointerId;
			try {
				stick.setPointerCapture(ev.pointerId);
			} catch (e) { /* ignore */ }
			onMove(ev);
			ev.preventDefault();
		}
		function onMove(ev) {
			if (ev.pointerId !== stickPtr) return;
			var rect = stick.getBoundingClientRect();
			var cx = rect.left + rect.width / 2;
			var cy = rect.top + rect.height / 2;
			var dx = ev.clientX - cx;
			var dy = ev.clientY - cy;
			var len = Math.sqrt(dx * dx + dy * dy) || 1;
			var max = stickR;
			if (len > max) {
				dx = (dx / len) * max;
				dy = (dy / len) * max;
			}
			setKnob(dx, dy);
			applyStick(dx / max, dy / max);
			ev.preventDefault();
		}
		function onUp(ev) {
			if (ev.pointerId !== stickPtr) return;
			stickPtr = null;
			setKnob(0, 0);
			clearMove();
			ev.preventDefault();
		}
		stick.addEventListener("pointerdown", onDown);
		stick.addEventListener("pointermove", onMove);
		stick.addEventListener("pointerup", onUp);
		stick.addEventListener("pointercancel", onUp);
		stick.addEventListener("lostpointercapture", function () {
			stickPtr = null;
			setKnob(0, 0);
			clearMove();
		});
	}

	function bindButtons() {
		var btns = root.querySelectorAll(".mw-tp-btn");
		btns.forEach(function (btn) {
			var code = btn.getAttribute("data-code");
			var hold = btn.getAttribute("data-hold") === "1";
			var ptr = null;
			function down(ev) {
				if (ptr != null) return;
				ptr = ev.pointerId;
				btn.classList.add("mw-tp-down");
				setKey(code, true);
				try {
					btn.setPointerCapture(ev.pointerId);
				} catch (e) { /* ignore */ }
				ev.preventDefault();
				ev.stopPropagation();
			}
			function up(ev) {
				if (ev.pointerId !== ptr) return;
				ptr = null;
				btn.classList.remove("mw-tp-down");
				setKey(code, false);
				ev.preventDefault();
				ev.stopPropagation();
			}
			btn.addEventListener("pointerdown", down);
			btn.addEventListener("pointerup", up);
			btn.addEventListener("pointercancel", up);
			btn.addEventListener("lostpointercapture", function () {
				ptr = null;
				btn.classList.remove("mw-tp-down");
				if (!hold) setKey(code, false);
				else setKey(code, false);
			});
			/* Pulse keys: ensure short press still registers even if up is fast. */
			if (!hold) {
				btn.addEventListener("pointerdown", function () {
					setKey(code, true);
					setTimeout(function () {
						if (ptr == null) setKey(code, false);
					}, 80);
				});
			}
		});
	}

	function boot() {
		mount();
		bindStick();
		bindButtons();
		/* Re-evaluate when Godot toggles hub/play chrome. */
		var obs = new MutationObserver(function () {
			mount();
		});
		obs.observe(document.body, { attributes: true, attributeFilter: ["class"] });
		window.addEventListener("blur", function () {
			clearMove();
			setKey("KeyQ", false);
			setKey("KeyE", false);
			setKey("KeyF", false);
			setKey("Space", false);
			setKnob(0, 0);
			stickPtr = null;
		});
		console.log("[MW] touch pad", shouldEnable() ? "enabled" : "standby (?touch=1 to force)");
	}

	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", boot);
	} else {
		boot();
	}
})();
