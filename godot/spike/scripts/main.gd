## MineWorld Godot spike — session shell.
## Connects to the Python gateway, joins a level, takes/releases control,
## drives a capsule puppet with WASD/QE (authority stays server-side).
## T: take_control · R: release_control · HUD shows objective outcome.
extends Node3D

const MOVE_SPEED := 1.0
const TURN_SPEED := 1.0
const CMD_HZ := 20.0

@export var level_id := "tutorial_01"

# Untyped on purpose: global class_name registration needs an editor scan
# (.godot/global_script_class_cache.cfg), which a fresh headless run lacks.
@onready var ws = $WsClient
@onready var mech = $MechPlayer
@onready var hud_label: Label = $Hud/PanelContainer/MarginContainer/Label

var _session_id := ""
var _hello: Dictionary = {}
var _last_error := ""
var _cmd_timer := 0.0
var _last_log_tick := -1
var _controlled := false
var _mission_done := false
var _status_line := ""


func _ready() -> void:
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	ws.connect_to_gateway()
	_update_hud()


func _on_hello(payload: Dictionary) -> void:
	_hello = payload
	_session_id = ws.session_id
	print("[MW] hello session=%s payload=%s" % [_session_id, payload])
	ws.join(level_id, "godot_spike")
	_update_hud()


func _on_scene(payload: Dictionary) -> void:
	print("[MW] scene level=%s entities=%d" % [payload.get("level_id", ""), (payload.get("entities", []) as Array).size()])
	_controlled = false
	_mission_done = false
	_status_line = ""
	ws.send_cmd({"action": "take_control", "entity_id": "mech_player"})


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
				ws.send_cmd({"action": "release_control", "entity_id": "mech_player"})
		"objective_failed":
			_mission_done = true
			_status_line = "FAIL · %s" % payload.get("objective_id", "?")
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": "mech_player"})
	_update_hud()


func _on_gateway_error(payload: Dictionary) -> void:
	_last_error = "%s: %s" % [payload.get("code", "?"), payload.get("message", "")]
	push_warning("[MW] gateway error: %s" % payload)
	_update_hud()


func _on_link_state(_connected: bool) -> void:
	_update_hud()


func _on_state(tick: int, t_sim: float, payload: Dictionary) -> void:
	for entity in payload.get("entities", []):
		if str(entity.get("entity_id", "")) == mech.entity_id:
			mech.apply_state(entity, t_sim)
	if tick - _last_log_tick >= 20:
		_last_log_tick = tick
		print("[MW] state tick=%d pos=(%.2f, %.2f) yaw=%.2f" % [tick, mech.position.x, mech.position.z, mech.rotation.y])
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


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if ws.session_id == "":
		return
	match event.keycode:
		KEY_T:
			if not _controlled and not _mission_done:
				ws.send_cmd({"action": "take_control", "entity_id": "mech_player"})
		KEY_R:
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": "mech_player"})


func _send_velocity_cmd() -> void:
	var vx := Input.get_axis("move_back", "move_forward") * MOVE_SPEED
	# Body frame (Z-up, forward +X): +vy = strafe left, +yaw_rate = CCW.
	var vy := Input.get_axis("strafe_left", "strafe_right") * -MOVE_SPEED
	var yaw_rate := Input.get_axis("turn_cw", "turn_ccw") * TURN_SPEED
	ws.send_cmd({
		"entity_id": "mech_player",
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
	var text := "MineWorld Spike\n"
	text += "link: %s | control: %s\n" % [state_name, "ON" if _controlled else "OFF"]
	if _status_line != "":
		text += "%s\n" % _status_line
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
		text += "pos=(%.2f, %.2f) yaw=%.2f\n" % [mech.position.x, mech.position.z, mech.rotation.y]
	if _last_error != "":
		text += "\n! gateway error: %s" % _last_error
	text += "\nWS move | QE strafe | AD turn | T take | R release"
	text += "\nRMB/MMB orbit | wheel zoom"
	hud_label.text = text
