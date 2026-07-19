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
	"""Desktop: top-left shrink panel. Web: hide Godot HUD (DOM overlay instead)."""
	if _is_web:
		var hud := get_node_or_null("Hud") as CanvasLayer
		if hud != null:
			hud.visible = false
		return
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


func _push_web_hud(text: String) -> void:
	"""Web-only: update static #mw-hud in index.html (avoids Godot Control clip)."""
	var payload := JSON.stringify(text)
	JavaScriptBridge.eval(
		"(function(t){var el=document.getElementById('mw-hud');"
		+ "if(el){el.textContent=t;}})(%s);" % payload,
		true
	)


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
	"""Create/update puppets for each mech entity_id in the scene list."""
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		if str(entity.get("kind", "mech")) != "mech":
			continue
		var eid := str(entity.get("entity_id", ""))
		if eid == "":
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
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
		"objective_failed":
			_mission_done = true
			_status_line = "FAIL · %s" % payload.get("objective_id", "?")
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
		if _web_key("KeyW") or _web_key("ArrowUp"):
			vx += MOVE_SPEED
		if _web_key("KeyS") or _web_key("ArrowDown"):
			vx -= MOVE_SPEED
		if _web_key("KeyQ"):
			vy += MOVE_SPEED
		if _web_key("KeyE"):
			vy -= MOVE_SPEED
		if _web_key("KeyA") or _web_key("ArrowLeft"):
			yaw_rate += TURN_SPEED
		if _web_key("KeyD") or _web_key("ArrowRight"):
			yaw_rate -= TURN_SPEED
	else:
		if _key_down(KEY_W) or _key_down(KEY_UP):
			vx += MOVE_SPEED
		if _key_down(KEY_S) or _key_down(KEY_DOWN):
			vx -= MOVE_SPEED
		if _key_down(KEY_Q):
			vy += MOVE_SPEED
		if _key_down(KEY_E):
			vy -= MOVE_SPEED
		if _key_down(KEY_A) or _key_down(KEY_LEFT):
			yaw_rate += TURN_SPEED
		if _key_down(KEY_D) or _key_down(KEY_RIGHT):
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
	text += "\nRMB/MMB orbit | wheel zoom"
	if _is_web:
		_push_web_hud(text)
	elif hud_label != null:
		hud_label.text = text
