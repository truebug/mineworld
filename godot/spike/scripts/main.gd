## MineWorld Godot spike — session shell.
## Connects to the Python gateway, joins a level, takes/releases control,
## drives capsule puppets with WASD/QE (authority stays server-side).
##
## Multiplayer (W3): join with room_id (export or window.MINEWORLD_ROOM);
## empty = private room. Scene assigns controlled_entity_id; extra mechs
## are duplicated from MechPlayer.
##
## Web keyboard: single-thread export + document listeners via JavaScriptBridge
## (eval/window._mw_keys readback is unreliable; InputMap often fails in browser).
extends Node3D

const MOVE_SPEED := 1.0
const TURN_SPEED := 1.0
const CMD_HZ := 20.0
const _WEB_BLOCK_CODES := {
	"KeyW": true, "KeyA": true, "KeyS": true, "KeyD": true,
	"KeyQ": true, "KeyE": true, "KeyT": true, "KeyR": true,
	"KeyV": true, "KeyC": true,
	"ArrowUp": true, "ArrowDown": true, "ArrowLeft": true, "ArrowRight": true,
	"Space": true,
}

@export var level_id := "demo_workshop"
@export var gateway_url := "ws://127.0.0.1:8765"
## Empty = private room (gateway uses session_id). Set "demo" for shared room.
@export var room_id := ""

@onready var ws = $WsClient
@onready var mech = $MechPlayer
@onready var camera_rig = $CameraRig
@onready var hud_label: Label = _resolve_hud_label()

var _session_id := ""
var _hello: Dictionary = {}
var _last_error := ""
var _cmd_timer := 0.0
var _last_log_tick := -1
var _controlled := false
var _mission_done := false
var _status_line := ""
var _is_web := false
## Must keep refs or JS callbacks are garbage-collected.
var _web_key_cb
var _web_blur_cb
## KeyboardEvent.code → pressed (web)
var _held_codes: Dictionary = {}
var _held: Dictionary = {}
var _web_key_logged := false
## entity_id → MWMechPuppet
var _puppets: Dictionary = {}
var _controlled_entity_id := "mech_player"
var _joined_room_id := ""
var _banner_layer: CanvasLayer
var _banner_title: Label
var _banner_sub: Label
var _sfx: AudioStreamPlayer
## D8: offline frame replay (?replay=<session_id>); skips gateway.
var _replay_session := ""
var _replay_frames: Array = []
var _replay_playing := false
var _replay_speed := 1.0
var _replay_t := 0.0
var _replay_idx := 0
var _replay_status := ""
## V1c: held arm/gripper setpoints (desktop sliders / web MW_JOINT_TARGETS).
var _joint_targets: Dictionary = {
	"arm_yaw": 0.0,
	"arm_shoulder": 0.0,
	"arm_elbow": 0.0,
	"gripper": 0.0,
}
var _joint_panel: CanvasLayer
## Platform / local profile for score wiring (align hub.gd).
var _profile: Dictionary = {}
const _JOINT_SPECS := [
	{"id": "arm_yaw", "label": "yaw", "min": -2.8, "max": 2.8, "step": 0.02},
	{"id": "arm_shoulder", "label": "shoulder", "min": -1.4, "max": 1.6, "step": 0.02},
	{"id": "arm_elbow", "label": "elbow", "min": -2.4, "max": 0.2, "step": 0.02},
	{"id": "gripper", "label": "gripper", "min": 0.0, "max": 0.05, "step": 0.001},
]


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_profile = _load_profile()
	MWTransition.notify_arrived()
	_replay_session = _resolve_replay_id()
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	if ws.has_signal("link_phase_changed"):
		ws.link_phase_changed.connect(_on_link_phase)
	mech.entity_id = "mech_player"
	_puppets["mech_player"] = mech
	var mech_b := get_node_or_null("MechPlayerB")
	if mech_b != null:
		_puppets["mech_player_b"] = mech_b
	_ensure_mission_banner()
	_ensure_hud_layout()
	_ensure_joint_sliders()
	call_deferred("_ensure_hud_layout")
	if not get_viewport().size_changed.is_connected(_ensure_hud_layout):
		get_viewport().size_changed.connect(_ensure_hud_layout)
	if _is_web:
		_install_web_keyboard_bridge()
		_sync_web_city_seed_ui()
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(true);}",
			true
		)
	if camera_rig != null and camera_rig.has_signal("view_mode_changed"):
		camera_rig.view_mode_changed.connect(_on_camera_view_changed)
	if _replay_session != "":
		_start_replay_mode()
		return
	ws.connect_to_gateway(_resolve_gateway_url())
	_update_hud()


func _sync_web_city_seed_ui() -> void:
	"""Show city seed/Regen chrome only for demo_city."""
	if not _is_web:
		return
	var show := "true" if level_id == "demo_city" else "false"
	JavaScriptBridge.eval(
		"(function(show){var e=document.getElementById('mw-seed');if(!e){return;}"
		+ "e.classList.toggle('mw-show',!!show);})(%s);" % show,
		true
	)


func _resolve_replay_id() -> String:
	"""Web: ?replay=<session_id> for D8 offline playback."""
	if not _is_web:
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('replay')||''}catch(e){return ''}})()",
		true
	))


func _start_replay_mode() -> void:
	"""Fetch frames.jsonl and drive puppets without Gateway."""
	_replay_status = "loading frames…"
	_update_hud()
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	if origin == "":
		_replay_status = "replay: no origin"
		_update_hud()
		return
	var http := HTTPRequest.new()
	http.name = "ReplayHttp"
	add_child(http)
	http.request_completed.connect(_on_replay_http.bind(http))
	var url := "%s/api/recordings/%s/frames" % [origin, _replay_session.uri_encode()]
	var err := http.request(url)
	if err != OK:
		_replay_status = "replay HTTP err %s" % err
		http.queue_free()
		_update_hud()


func _on_replay_http(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	"""Parse JSONL frames and start playback."""
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_replay_status = "replay load fail %s/%s" % [result, response_code]
		_update_hud()
		return
	var lines := body.get_string_from_utf8().split("\n", false)
	_replay_frames.clear()
	for line in lines:
		if str(line).strip_edges() == "":
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			_replay_frames.append(parsed)
	if _replay_frames.is_empty():
		_replay_status = "replay: empty frames"
		_update_hud()
		return
	# Seed puppets from first frame entities.
	var first: Dictionary = _replay_frames[0]
	var state: Variant = first.get("state", {})
	if typeof(state) == TYPE_DICTIONARY:
		_ensure_puppets((state as Dictionary).get("entities", []) as Array)
	_replay_playing = true
	_replay_t = 0.0
	_replay_idx = 0
	_replay_status = "REPLAY · %s · %d frames · Space pause" % [
		_replay_session.substr(0, 8), _replay_frames.size()
	]
	var own := _own_mech()
	if camera_rig != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(own)
	_apply_replay_frame(0)
	_update_hud()


func _apply_replay_frame(idx: int) -> void:
	"""Apply one recorded frame to puppets."""
	if idx < 0 or idx >= _replay_frames.size():
		return
	var frame: Dictionary = _replay_frames[idx]
	var t_sim := float(frame.get("t_sim", 0.0))
	var state: Variant = frame.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return
	for entity in (state as Dictionary).get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if eid == "":
			continue
		if not _puppets.has(eid):
			_ensure_puppets([entity])
		if not _puppets.has(eid):
			continue
		var puppet = _puppets[eid]
		if puppet.has_method("apply_state"):
			puppet.apply_state(entity, t_sim)
	_replay_idx = idx
	_update_hud(-1, t_sim)


func _process_replay(delta: float) -> void:
	"""Advance offline replay clock and apply nearest frame."""
	if _is_web and camera_rig != null and camera_rig.has_method("pan_axes"):
		var pan_r := 0.0
		var pan_f := 0.0
		if _web_key("ArrowRight"):
			pan_r += 1.0
		if _web_key("ArrowLeft"):
			pan_r -= 1.0
		if _web_key("ArrowUp"):
			pan_f += 1.0
		if _web_key("ArrowDown"):
			pan_f -= 1.0
		camera_rig.pan_axes(pan_r, pan_f, delta)
	if not _replay_playing or _replay_frames.is_empty():
		return
	_replay_t += delta * _replay_speed
	var last: Dictionary = _replay_frames[_replay_frames.size() - 1]
	var t_max := float(last.get("t_sim", 0.0))
	if _replay_t >= t_max:
		_replay_t = t_max
		_replay_playing = false
		_replay_status = "REPLAY done · Space restart · Esc back"
	while _replay_idx + 1 < _replay_frames.size():
		var nxt: Dictionary = _replay_frames[_replay_idx + 1]
		if float(nxt.get("t_sim", 0.0)) > _replay_t:
			break
		_replay_idx += 1
	_apply_replay_frame(_replay_idx)


func _toggle_replay_pause() -> void:
	"""Space: pause/resume or restart when finished."""
	if _replay_frames.is_empty():
		return
	var last: Dictionary = _replay_frames[_replay_frames.size() - 1]
	var t_max := float(last.get("t_sim", 0.0))
	if _replay_t >= t_max and not _replay_playing:
		_replay_t = 0.0
		_replay_idx = 0
		_replay_playing = true
		_replay_status = "REPLAY · %s · %d frames" % [
			_replay_session.substr(0, 8), _replay_frames.size()
		]
		_apply_replay_frame(0)
		return
	_replay_playing = not _replay_playing
	_replay_status = (
		"REPLAY paused" if not _replay_playing else "REPLAY playing"
	)
	_update_hud()

func _resolve_hud_label() -> Label:
	"""Resolve Label under Hud (Margin/... or legacy PanelContainer/...)."""
	for path in [
		"Hud/Margin/PanelContainer/MarginContainer/Label",
		"Hud/Root/PanelContainer/MarginContainer/Label",
		"Hud/PanelContainer/MarginContainer/Label",
	]:
		var n := get_node_or_null(path)
		if n != null:
			return n as Label
	return $Hud/PanelContainer/MarginContainer/Label as Label


func _ensure_hud_layout() -> void:
	"""Desktop: top-left shrink panel. Web: remove Godot Hud (DOM #mw-hud only)."""
	var hud := get_node_or_null("Hud") as CanvasLayer
	if _is_web:
		# Free Godot Control HUD entirely — visible=false still left a clipped panel on Web.
		if hud != null:
			hud.queue_free()
		return
	if hud != null:
		hud.visible = true
	var margin := get_node_or_null("Hud/Margin") as MarginContainer
	if margin != null:
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := get_node_or_null("Hud/Margin/PanelContainer") as PanelContainer
	if panel == null:
		panel = get_node_or_null("Hud/Root/PanelContainer") as PanelContainer
	if panel == null:
		panel = get_node_or_null("Hud/PanelContainer") as PanelContainer
	if panel == null:
		return
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(480, 0)


func _ensure_mission_banner() -> void:
	"""Build a centered SUCCESS/FAIL banner (desktop CanvasLayer; web uses DOM)."""
	if _banner_layer != null:
		return
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "MissionBanner"
	_banner_layer.layer = 100
	_banner_layer.visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = Label.new()
	_banner_title.text = "SUCCESS"
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 96)
	_banner_title.add_theme_color_override("font_color", Color(0.36, 1.0, 0.54))
	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 20)
	_banner_sub.add_theme_color_override("font_color", Color(0.95, 0.96, 0.97))
	col.add_child(_banner_title)
	col.add_child(_banner_sub)
	center.add_child(col)
	root.add_child(dim)
	root.add_child(center)
	_banner_layer.add_child(root)
	add_child(_banner_layer)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "MissionSfx"
	add_child(_sfx)


func _push_web_hud(text: String) -> void:
	"""Web-only: push HUD text via shell.html MW_SET_HUD (click-to-collapse)."""
	var payload := JSON.stringify(text)
	JavaScriptBridge.eval(
		"(function(t){"
		+ "if(typeof window.MW_SET_HUD==='function'){window.MW_SET_HUD(t);return;}"
		+ "var el=document.getElementById('mw-hud');"
		+ "if(!el){el=document.createElement('pre');el.id='mw-hud';document.body.appendChild(el);}"
		+ "el.textContent=t;"
		+ "})(%s);" % payload,
		true
	)


func _show_mission_result(ok: bool, detail: String, points: int = 0) -> void:
	"""Show big SUCCESS/FAIL + short beep (desktop Label / web DOM)."""
	var title := "SUCCESS" if ok else "FAIL"
	var sub := detail if detail != "" else ("reach zone OK" if ok else "objective failed")
	if ok and points > 0:
		sub = "%s · +%d pts" % [sub, points]
	if _is_web:
		var payload := JSON.stringify({
			"ok": ok,
			"title": title,
			"sub": sub,
			"points": points,
			"me_href": "/portal/me.html",
		})
		JavaScriptBridge.eval(
			"(function(p){var el=document.getElementById('mw-success');"
			+ "if(!el){return;}el.classList.toggle('fail',!p.ok);"
			+ "el.classList.add('show');"
			+ "var t=el.querySelector('.mw-title');if(t){t.textContent=p.title;}"
			+ "var s=el.querySelector('.mw-sub');if(s){s.textContent=p.sub;}"
			+ "var a=el.querySelector('.mw-me');if(a){"
			+ "if(p.ok&&p.points>0){a.style.display='inline';a.href=p.me_href||'/portal/me.html';}"
			+ "else{a.style.display='none';}}"
			+ "try{var Ctx=window.AudioContext||window.webkitAudioContext;var c=new Ctx();"
			+ "var o=c.createOscillator();var g=c.createGain();"
			+ "o.type='sine';o.frequency.value=p.ok?880:220;"
			+ "g.gain.setValueAtTime(0.18,c.currentTime);"
			+ "g.gain.exponentialRampToValueAtTime(0.001,c.currentTime+0.45);"
			+ "o.connect(g);g.connect(c.destination);o.start();o.stop(c.currentTime+0.45);}"
			+ "catch(e){}})(%s);" % payload,
			true
		)
		return
	if _banner_title != null:
		_banner_title.text = title
		_banner_title.add_theme_color_override(
			"font_color",
			Color(0.36, 1.0, 0.54) if ok else Color(1.0, 0.42, 0.42),
		)
	if _banner_sub != null:
		_banner_sub.text = sub
	if _banner_layer != null:
		_banner_layer.visible = true
	_play_mission_beep(ok)


func _play_mission_beep(ok: bool) -> void:
	"""Play a short generated beep without shipping audio assets."""
	if _sfx == null:
		return
	var sample_hz := 22050
	var duration := 0.4
	var n := int(sample_hz * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var freq := 880.0 if ok else 220.0
	for i in n:
		var t := float(i) / float(sample_hz)
		var env := maxf(0.0, 1.0 - t / duration)
		var sample := int(sin(t * TAU * freq) * 0.28 * env * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_hz
	stream.data = data
	_sfx.stream = stream
	_sfx.play()


func _install_web_keyboard_bridge() -> void:
	"""Bind document keydown/keyup on the page (single-thread Web only)."""
	_web_key_cb = JavaScriptBridge.create_callback(_on_dom_key_event)
	_web_blur_cb = JavaScriptBridge.create_callback(_on_dom_blur)
	var document = JavaScriptBridge.get_interface("document")
	var window_obj = JavaScriptBridge.get_interface("window")
	if document == null or window_obj == null:
		push_warning("[MW] JavaScriptBridge document/window missing")
		return
	document.addEventListener("keydown", _web_key_cb)
	document.addEventListener("keyup", _web_key_cb)
	window_obj.addEventListener("blur", _web_blur_cb)
	print("[MW] key bridge: document listeners registered")


func _on_dom_key_event(args: Array) -> void:
	"""DOM keydown/keyup → update _held_codes. args[0] is the KeyboardEvent."""
	if args.is_empty():
		return
	var event = args[0]
	var code := str(event.code)
	var down := str(event.type) == "keydown"
	_held_codes[code] = down
	if not _web_key_logged and down:
		_web_key_logged = true
		print("[MW] first key from document: ", code)
	if down and not bool(event.repeat) and camera_rig != null and camera_rig.has_method("handle_code"):
		camera_rig.handle_code(code, true)
	if _WEB_BLOCK_CODES.has(code):
		event.preventDefault()
	if down and not bool(event.repeat):
		match code:
			"KeyT":
				if not _controlled and not _mission_done and ws.session_id != "":
					ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})
			"KeyR":
				if _controlled and ws.session_id != "":
					ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
			"Space":
				if _replay_session != "":
					_toggle_replay_pause()
			"Escape":
				_leave_to_hub()


func _leave_to_hub() -> void:
	"""Esc → Hub; strip ?replay=/?room= so Hub does not re-route or join play rooms."""
	# Stop cmds + drop play room before scene swap (avoids stale WS / sticky keys).
	if ws != null:
		ws.close_link()
	if _is_web:
		JavaScriptBridge.eval(
			"(function(){try{"
			+ "if(typeof window.MW_CLEAR_MISSION==='function'){window.MW_CLEAR_MISSION();}"
			+ "var el=document.getElementById('mw-success');"
			+ "if(el){el.classList.remove('show','fail');}"
			+ "window._mw_keys=Object.create(null);"
			+ "var u=new URL(location.href);"
			+ "u.searchParams.delete('replay');"
			+ "u.searchParams.delete('room');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);"
			+ "}catch(e){}})()",
			true
		)
	_held.clear()
	_held_codes.clear()
	MWTransition.go("res://demo_hub.tscn", "Hub", "#8a93a3")


func _on_camera_view_changed(label: String) -> void:
	"""Show camera mode on HUD when V cycles (CameraRig SSOT)."""
	_status_line = "相机 · Camera: %s（V 切换 · C 回正）" % label
	_update_hud()


func _sync_first_person_mesh() -> void:
	"""Hide own chassis in FP so the camera is not inside the hull."""
	var own := _own_mech()
	if own == null:
		return
	var fp := false
	if camera_rig != null and camera_rig.has_method("is_first_person"):
		fp = bool(camera_rig.is_first_person())
	own.visible = not fp


func _on_dom_blur(_args: Array) -> void:
	"""Clear held keys when the browser tab loses focus."""
	_held_codes.clear()


func _web_key(code: String) -> bool:
	"""True if this KeyboardEvent.code is held."""
	return bool(_held_codes.get(code, false))


func _resolve_gateway_url() -> String:
	"""Prefer window.MINEWORLD_GATEWAY on Web; else exported gateway_url."""
	if _is_web:
		var from_js := str(JavaScriptBridge.eval("window.MINEWORLD_GATEWAY || ''", true))
		if from_js != "":
			return from_js
	return gateway_url


func _resolve_room_id() -> String:
	"""Web: ?room= → window.MINEWORLD_ROOM → sessionStorage; else @export room_id.

	Do not rely on `window.MINEWORLD_ROOM=...; location.reload()` — reload clears
	window vars. Prefer http://host/?room=demo for e2e.
	"""
	if _is_web:
		var from_q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('room')||''}catch(e){return ''}})()",
			true
		))
		if from_q != "":
			return from_q
		var from_js := str(JavaScriptBridge.eval(
			"window.MINEWORLD_ROOM || sessionStorage.getItem('MINEWORLD_ROOM') || ''",
			true
		))
		if from_js != "":
			return from_js
	return room_id


func _own_mech() -> Node3D:
	"""Puppet for the assigned controlled entity."""
	if _puppets.has(_controlled_entity_id):
		return _puppets[_controlled_entity_id]
	return mech


func _load_profile() -> Dictionary:
	"""Load platform/local profile for join + score (same sources as hub)."""
	if OS.has_feature("web"):
		var raw := str(JavaScriptBridge.eval(
			"(function(){try{return JSON.stringify(window.MW_GET_PROFILE?window.MW_GET_PROFILE():null)}catch(e){return 'null'}})()",
			true
		))
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	var path := "user://mw_profile.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed2: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed2) == TYPE_DICTIONARY:
				return parsed2
	return {
		"id": "local-%s" % str(Time.get_unix_time_from_system()).replace(".", ""),
		"nickname": "Guest",
		"accent": "#4aa3ff",
	}


func _on_hello(payload: Dictionary) -> void:
	_hello = payload
	_session_id = ws.session_id
	_joined_room_id = _resolve_room_id()
	print("[MW] hello session=%s room=%s payload=%s" % [_session_id, _joined_room_id, payload])
	var nick := str(_profile.get("nickname", "godot_spike"))
	if nick == "":
		nick = "godot_spike"
	var mw := {
		"profile": {
			"id": str(_profile.get("id", "")),
			"nickname": nick,
			"accent": str(_profile.get("accent", "#4aa3ff")),
		}
	}
	var space_id := _resolve_space_id()
	if space_id != "":
		mw["space_id"] = space_id
		mw["route_kind"] = "pms_space"
	ws.join(level_id, nick, _joined_room_id, {"mw": mw})
	_update_hud()


func _resolve_space_id() -> String:
	"""E3: optional ?space_id= attribution for recordings / scores."""
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('space_id')||''}catch(e){return ''}})()",
		true
	)).strip_edges()


func _on_scene(payload: Dictionary) -> void:
	print("[MW] scene level=%s entities=%d" % [payload.get("level_id", ""), (payload.get("entities", []) as Array).size()])
	_controlled = false
	_mission_done = false
	_status_line = ""
	var ext: Dictionary = payload.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var mw: Variant = ext.get("mw", {})
		if typeof(mw) == TYPE_DICTIONARY:
			if str(mw.get("controlled_entity_id", "")) != "":
				_controlled_entity_id = str(mw.get("controlled_entity_id"))
			if str(mw.get("room_id", "")) != "":
				_joined_room_id = str(mw.get("room_id"))
	_ensure_puppets(payload.get("entities", []) as Array)
	var own := _own_mech()
	if camera_rig != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(own)
	ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})


func _ensure_puppets(entities: Array) -> void:
	"""Create/update puppets for mechs and dynamic_props in the scene list."""
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var kind := str(entity.get("kind", "mech"))
		var eid := str(entity.get("entity_id", ""))
		if eid == "":
			continue
		if kind == "dynamic_prop":
			_ensure_prop_puppet(eid, entity.get("size", null))
			continue
		if kind != "mech":
			continue
		if not _puppets.has(eid):
			var copy: Node3D = mech.duplicate()
			copy.name = "Mech_%s" % eid
			copy.set("entity_id", eid)
			add_child(copy)
			_puppets[eid] = copy
			print("[MW] spawned puppet entity_id=%s" % eid)
		var puppet = _puppets[eid]
		puppet.set("entity_id", eid)
		if puppet.has_method("apply_team_look"):
			puppet.apply_team_look()
	# Keep template entity_id in sync when we were assigned mech_player_b.
	if _puppets.has(_controlled_entity_id):
		var p = _puppets[_controlled_entity_id]
		p.set("entity_id", _controlled_entity_id)
		if p.has_method("apply_team_look"):
			p.apply_team_look()


func _ensure_prop_puppet(eid: String, size_arr: Variant = null) -> void:
	"""Spawn a pushable-box visual for dynamic_prop entity_id."""
	if _puppets.has(eid):
		return
	var prop_script: Script = load("res://scripts/prop_puppet.gd") as Script
	var node := Node3D.new()
	node.set_script(prop_script)
	node.name = "Prop_%s" % eid
	node.set("entity_id", eid)
	if typeof(size_arr) == TYPE_ARRAY and size_arr.size() >= 3:
		node.set("box_size", Vector3(float(size_arr[0]), float(size_arr[1]), float(size_arr[2])))
	add_child(node)
	_puppets[eid] = node
	print("[MW] spawned prop entity_id=%s" % eid)


func _on_event(payload: Dictionary) -> void:
	var et := str(payload.get("event_type", ""))
	print("[MW] event %s" % et)
	match et:
		"player_take_control":
			_controlled = true
		"player_release_control":
			_controlled = false
		"objective_complete":
			var detail_v: Variant = payload.get("detail", {})
			var detail: Dictionary = detail_v if typeof(detail_v) == TYPE_DICTIONARY else {}
			var kind := str(detail.get("kind", ""))
			var oid := str(payload.get("objective_id", "?"))
			# grasp_lift is a milestone — keep control for place/stow.
			if kind == "grasp_lift" or oid == "obj_lift_block":
				_status_line = MWi18n.t(
					"已夹起 · 放到工作台并张开夹爪",
					"Lifted · place on bench and open gripper"
				)
				_update_hud()
				return
			_mission_done = true
			var pts := int(detail.get("points", 0))
			if pts <= 0:
				pts = int(payload.get("points", 0))
			_status_line = MWi18n.t("通关 · %s", "SUCCESS · %s") % oid
			_show_mission_result(true, oid, pts)
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
		"objective_failed":
			_mission_done = true
			_status_line = MWi18n.t("失败 · %s", "FAIL · %s") % payload.get("objective_id", "?")
			_show_mission_result(false, str(payload.get("objective_id", "objective")))
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
	_update_hud()


func _on_gateway_error(payload: Dictionary) -> void:
	_last_error = "%s: %s" % [payload.get("code", "?"), payload.get("message", "")]
	push_warning("[MW] gateway error: %s" % payload)
	_update_hud()


func _on_link_state(connected: bool) -> void:
	if not connected and _status_line == "":
		_status_line = "Disconnected · reconnecting…"
	elif connected and _status_line.begins_with("Disconnected"):
		_status_line = "Reconnected · waiting for scene…"
	_update_hud()


func _on_link_phase(phase: String) -> void:
	"""UX3: surface connect/reconnect in play HUD (shared WsClient)."""
	match phase:
		"connecting":
			_status_line = "Connecting to gateway…"
		"reconnecting":
			_status_line = "Disconnected · reconnecting…"
		"connected":
			if _status_line.begins_with("Disconnected") or _status_line.begins_with("Connecting"):
				_status_line = "Connected"
		"disconnected":
			_status_line = "Offline — start gateway: echo_server.py"
	_update_hud()


func _on_state(tick: int, t_sim: float, payload: Dictionary) -> void:
	for entity in payload.get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if eid == "" or not _puppets.has(eid):
			continue
		var puppet = _puppets[eid]
		if puppet.has_method("apply_state"):
			puppet.apply_state(entity, t_sim)
	var own = _own_mech()
	if tick - _last_log_tick >= 20:
		_last_log_tick = tick
		var held_w := _web_key("KeyW") if _is_web else _key_down(KEY_W)
		var mw_x := float(own.get("last_mw_x")) if "last_mw_x" in own else 0.0
		var mw_y := float(own.get("last_mw_y")) if "last_mw_y" in own else 0.0
		print(
			"[MW] state tick=%d t_sim=%.3f srv=(%.2f, %.2f) pos=(%.2f, %.2f) heldW=%s ctrl=%s entity=%s"
			% [
				tick, t_sim, mw_x, mw_y,
				own.position.x, own.position.z, held_w, _controlled, _controlled_entity_id,
			]
		)
	_update_hud(tick, t_sim)


func _process(delta: float) -> void:
	if _replay_session != "":
		_process_replay(delta)
		return
	# Web: arrow keys pan camera (document bridge). Desktop: camera_rig reads Input.
	if _is_web and camera_rig != null and camera_rig.has_method("pan_axes"):
		var pan_r := 0.0
		var pan_f := 0.0
		if _web_key("ArrowRight"):
			pan_r += 1.0
		if _web_key("ArrowLeft"):
			pan_r -= 1.0
		if _web_key("ArrowUp"):
			pan_f += 1.0
		if _web_key("ArrowDown"):
			pan_f -= 1.0
		camera_rig.pan_axes(pan_r, pan_f, delta)
	_sync_first_person_mesh()
	if ws.session_id == "":
		return
	if not _controlled or _mission_done:
		return
	_cmd_timer += delta
	if _cmd_timer >= 1.0 / CMD_HZ:
		_cmd_timer = 0.0
		_send_velocity_cmd()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not _is_web:
		_set_held(event.keycode, event.pressed)
		_set_held(event.physical_keycode, event.pressed)
		if event.pressed and not event.echo:
			var code: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
			if code == KEY_ESCAPE:
				_leave_to_hub()
				return
			if code == KEY_SPACE and _replay_session != "":
				_toggle_replay_pause()
				return
			if ws.session_id == "":
				return
			match code:
				KEY_T:
					if not _controlled and not _mission_done:
						ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})
				KEY_R:
					if _controlled:
						ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})


func _set_held(code: int, pressed: bool) -> void:
	"""Record key down/up; ignore KEY_NONE."""
	if code == KEY_NONE:
		return
	_held[code] = pressed


func _key_down(code: int) -> bool:
	"""True if this keycode is currently held (desktop)."""
	return bool(_held.get(code, false))


func _ensure_joint_sliders() -> void:
	"""Desktop: bottom-left HSliders for arm/gripper (V1c). Web uses DOM #mw-joints."""
	if _is_web or _joint_panel != null:
		return
	_joint_panel = CanvasLayer.new()
	_joint_panel.name = "JointSliders"
	_joint_panel.layer = 12
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.offset_left = 12
	root.offset_bottom = -12
	root.offset_right = 280
	root.offset_top = -160
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var col := VBoxContainer.new()
	var title := Label.new()
	title.text = "Arm / gripper"
	col.add_child(title)
	for spec in _JOINT_SPECS:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = str(spec["label"])
		lab.custom_minimum_size = Vector2(72, 0)
		var slider := HSlider.new()
		slider.name = "Slider_%s" % spec["id"]
		slider.min_value = float(spec["min"])
		slider.max_value = float(spec["max"])
		slider.step = float(spec["step"])
		slider.value = float(_joint_targets.get(spec["id"], 0.0))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(120, 0)
		var jid := str(spec["id"])
		slider.value_changed.connect(func(v: float) -> void: _joint_targets[jid] = v)
		row.add_child(lab)
		row.add_child(slider)
		col.add_child(row)
	margin.add_child(col)
	panel.add_child(margin)
	root.add_child(panel)
	_joint_panel.add_child(root)
	add_child(_joint_panel)


func _read_joint_targets() -> Dictionary:
	"""Current joint setpoints from web DOM or desktop sliders."""
	if _is_web:
		var raw := str(JavaScriptBridge.eval(
			"JSON.stringify(window.MW_JOINT_TARGETS||{})"
		))
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var out: Dictionary = {}
			for spec in _JOINT_SPECS:
				var jid := str(spec["id"])
				out[jid] = float((parsed as Dictionary).get(jid, _joint_targets.get(jid, 0.0)))
			_joint_targets = out
			return out
	return _joint_targets.duplicate()


func _send_velocity_cmd() -> void:
	var vx := 0.0
	var vy := 0.0
	var yaw_rate := 0.0
	if _is_web:
		if _web_key("KeyW"):
			vx += MOVE_SPEED
		if _web_key("KeyS"):
			vx -= MOVE_SPEED
		if _web_key("KeyQ"):
			vy += MOVE_SPEED
		if _web_key("KeyE"):
			vy -= MOVE_SPEED
		if _web_key("KeyA"):
			yaw_rate += TURN_SPEED
		if _web_key("KeyD"):
			yaw_rate -= TURN_SPEED
	else:
		if _key_down(KEY_W):
			vx += MOVE_SPEED
		if _key_down(KEY_S):
			vx -= MOVE_SPEED
		if _key_down(KEY_Q):
			vy += MOVE_SPEED
		if _key_down(KEY_E):
			vy -= MOVE_SPEED
		if _key_down(KEY_A):
			yaw_rate += TURN_SPEED
		if _key_down(KEY_D):
			yaw_rate -= TURN_SPEED
		if vx == 0.0 and vy == 0.0 and yaw_rate == 0.0:
			vx = Input.get_axis("move_back", "move_forward") * MOVE_SPEED
			vy = Input.get_axis("strafe_left", "strafe_right") * -MOVE_SPEED
			yaw_rate = Input.get_axis("turn_cw", "turn_ccw") * TURN_SPEED
	if vx != 0.0 or vy != 0.0 or yaw_rate != 0.0:
		print("[MW] cmd vx=%.1f vy=%.1f yaw_rate=%.1f entity=%s" % [vx, vy, yaw_rate, _controlled_entity_id])
	var payload := {
		"entity_id": _controlled_entity_id,
		"control_mode": "velocity",
		"vx": vx,
		"vy": vy,
		"yaw_rate": yaw_rate,
		"joint_targets": _read_joint_targets(),
	}
	ws.send_cmd(payload)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ws.close_link()


func _update_hud(tick: int = -1, t_sim: float = 0.0) -> void:
	var own = _own_mech()
	if _replay_session != "":
		var text := "MineWorld · REPLAY\n"
		text += "%s\n" % _replay_status
		text += "session: %s\n" % _replay_session
		if tick >= 0 or t_sim > 0.0:
			text += "t_sim=%.2f frame=%d/%d\n" % [
				t_sim if t_sim > 0.0 else _replay_t,
				_replay_idx + 1,
				_replay_frames.size(),
			]
			text += "pos=(%.2f, %.2f) yaw=%.2f\n" % [
				own.position.x, own.position.z, own.rotation.y,
			]
		text += "\nSpace pause/restart | arrows pan | C center | Recordings ←"
		if _is_web:
			_push_web_hud(text)
		elif hud_label != null:
			hud_label.text = text
		return
	var state_name := "disconnected"
	if ws.session_id != "":
		state_name = "linked"
	var text := "MineWorld · %s\n" % level_id
	text += "link: %s | control: %s | entity: %s\n" % [
		state_name, "ON" if _controlled else "OFF", _controlled_entity_id,
	]
	text += "room: %s\n" % (_joined_room_id if _joined_room_id != "" else "(private)")
	var space_id := _resolve_space_id()
	if space_id != "":
		text += "space_id: %s · route: pms_space\n" % space_id
	if _is_web:
		text += "input: document→godot | heldW=%s\n" % _web_key("KeyW")
	if _status_line != "":
		text += "%s\n" % _status_line
	if _mission_done:
		text += "MISSION COMPLETE — reach zone OK\n"
	if _hello:
		text += "protocol: %s | dt=%.2f sim=%dHz state=%dHz\n" % [
			_hello.get("protocol_version", "?"),
			float(_hello.get("dt", 0.0)),
			int(_hello.get("sim_hz", 0)),
			int(_hello.get("state_hz", 0)),
		]
		text += "frame: %s | features: %s\n" % [_hello.get("frame", "?"), _hello.get("features", [])]
	if tick >= 0:
		text += "tick=%d t_sim=%.2f\n" % [tick, t_sim]
		text += "pos=(%.2f, %.2f) yaw=%.2f\n" % [own.position.x, own.position.z, own.rotation.y]
	if _last_error != "":
		text += "\n! gateway error: %s" % _last_error
	text += "\nWASD 移动 | QE 转向 | T 接管 | R 释放 | 左下角臂爪滑条"
	text += "\nV 相机 环绕/第一人称/跟随 | RMB/MMB 视角 | 滚轮缩放 | 方向键平移 | C 回正"
	text += "\n跟随模式：松开鼠标 → 视角回弹"
	if _is_web:
		text += "\n录制 → 右上角链接"
	if _is_web:
		text += "\n历史: /recordings.html"
	if _is_web:
		_push_web_hud(text)
	elif hud_label != null:
		hud_label.text = text
