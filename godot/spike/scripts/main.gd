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
	"ArrowUp": true, "ArrowDown": true, "ArrowLeft": true, "ArrowRight": true,
	"Space": true,
}

@export var level_id := "demo_city"
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


func _ready() -> void:
	_is_web = OS.has_feature("web")
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	mech.entity_id = "mech_player"
	_puppets["mech_player"] = mech
	var mech_b := get_node_or_null("MechPlayerB")
	if mech_b != null:
		_puppets["mech_player_b"] = mech_b
	_ensure_mission_banner()
	_ensure_hud_layout()
	call_deferred("_ensure_hud_layout")
	if not get_viewport().size_changed.is_connected(_ensure_hud_layout):
		get_viewport().size_changed.connect(_ensure_hud_layout)
	if _is_web:
		_install_web_keyboard_bridge()
	ws.connect_to_gateway(_resolve_gateway_url())
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
	"""Web-only: ensure #mw-hud is last child of body with inline styles (no clip)."""
	var payload := JSON.stringify(text)
	JavaScriptBridge.eval(
		"(function(t){"
		+ "var el=document.getElementById('mw-hud');"
		+ "if(!el){el=document.createElement('pre');el.id='mw-hud';}"
		+ "if(el.parentElement!==document.body){document.body.appendChild(el);}"
		+ "else{document.body.appendChild(el);}"
		+ "el.textContent=t;"
		+ "el.setAttribute('style',"
		+ "'position:fixed!important;left:16px!important;top:16px!important;"
		+ "right:auto!important;bottom:auto!important;transform:none!important;"
		+ "z-index:2147483646!important;margin:0!important;padding:12px 14px!important;"
		+ "max-width:min(520px,calc(100vw - 32px))!important;width:auto!important;"
		+ "height:auto!important;overflow:visible!important;clip:auto!important;"
		+ "clip-path:none!important;background:rgba(20,22,28,0.92)!important;"
		+ "color:#e8eaed!important;font:13px/1.4 ui-monospace,Menlo,Consolas,monospace!important;"
		+ "white-space:pre-wrap!important;word-break:break-word!important;"
		+ "border-radius:8px!important;pointer-events:none!important;"
		+ "box-shadow:0 2px 12px rgba(0,0,0,0.45)!important;border:1px solid #3d4450!important');"
		+ "})(%s);" % payload,
		true
	)


func _show_mission_result(ok: bool, detail: String) -> void:
	"""Show big SUCCESS/FAIL + short beep (desktop Label / web DOM)."""
	var title := "SUCCESS" if ok else "FAIL"
	var sub := detail if detail != "" else ("reach zone OK" if ok else "objective failed")
	if _is_web:
		var payload := JSON.stringify({"ok": ok, "title": title, "sub": sub})
		JavaScriptBridge.eval(
			"(function(p){var el=document.getElementById('mw-success');"
			+ "if(!el){return;}el.classList.toggle('fail',!p.ok);"
			+ "el.classList.add('show');"
			+ "var t=el.querySelector('.mw-title');if(t){t.textContent=p.title;}"
			+ "var s=el.querySelector('.mw-sub');if(s){s.textContent=p.sub;}"
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
	if down and code == "KeyC" and camera_rig != null and camera_rig.has_method("reset_look_offset"):
		camera_rig.reset_look_offset()
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


func _on_hello(payload: Dictionary) -> void:
	_hello = payload
	_session_id = ws.session_id
	_joined_room_id = _resolve_room_id()
	print("[MW] hello session=%s room=%s payload=%s" % [_session_id, _joined_room_id, payload])
	ws.join(level_id, "godot_spike", _joined_room_id)
	_update_hud()


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
			_ensure_prop_puppet(eid)
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


func _ensure_prop_puppet(eid: String) -> void:
	"""Spawn a pushable-box visual for dynamic_prop entity_id."""
	if _puppets.has(eid):
		return
	var prop_script: Script = load("res://scripts/prop_puppet.gd") as Script
	var node := Node3D.new()
	node.set_script(prop_script)
	node.name = "Prop_%s" % eid
	node.set("entity_id", eid)
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
			_mission_done = true
			_status_line = "SUCCESS · %s" % payload.get("objective_id", "?")
			_show_mission_result(true, str(payload.get("objective_id", "reach_finish")))
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
		"objective_failed":
			_mission_done = true
			_status_line = "FAIL · %s" % payload.get("objective_id", "?")
			_show_mission_result(false, str(payload.get("objective_id", "objective")))
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
	_update_hud()


func _on_gateway_error(payload: Dictionary) -> void:
	_last_error = "%s: %s" % [payload.get("code", "?"), payload.get("message", "")]
	push_warning("[MW] gateway error: %s" % payload)
	_update_hud()


func _on_link_state(_connected: bool) -> void:
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
		if event.pressed and not event.echo and ws.session_id != "":
			var code: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
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
	ws.send_cmd({
		"entity_id": _controlled_entity_id,
		"control_mode": "velocity",
		"vx": vx,
		"vy": vy,
		"yaw_rate": yaw_rate,
	})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ws.close_link()


func _update_hud(tick: int = -1, t_sim: float = 0.0) -> void:
	var state_name := "disconnected"
	if ws.session_id != "":
		state_name = "linked"
	var own = _own_mech()
	var text := "MineWorld · %s\n" % level_id
	text += "link: %s | control: %s | entity: %s\n" % [
		state_name, "ON" if _controlled else "OFF", _controlled_entity_id,
	]
	text += "room: %s\n" % (_joined_room_id if _joined_room_id != "" else "(private)")
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
	text += "\nWASD move | QE turn | T take | R release | goal: green finish"
	text += "\nRMB/MMB orbit | wheel zoom | arrows pan | C center"
	if _is_web:
		text += "\nRecordings → top-right link"
	if _is_web:
		text += "\nhistory: /recordings.html"
	if _is_web:
		_push_web_hud(text)
	elif hud_label != null:
		hud_label.text = text
