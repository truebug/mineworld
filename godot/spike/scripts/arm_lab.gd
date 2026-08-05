## HW-1: desktop KBM teleop lab for hw_fake SO-101 arm (ADR-004).
## Keys: 1-6 select joint · ,/. or Left/Right nudge target · H home · Space enable toggle.
## Mouse click on bench → shoulder_pan aims at clicked point (simple aim, no IK yet).
extends Node3D

const CMD_HZ := 20.0
const NUDGE_RAD := 0.05
## SO-101 public params — mirror of gateway/hw_machines.py (open params only).
const JOINTS := [
	{"id": "shoulder_pan", "label": "pan", "min": -1.92, "max": 1.92, "home": 0.0},
	{"id": "shoulder_lift", "label": "lift", "min": -1.75, "max": 1.75, "home": 0.3},
	{"id": "elbow_flex", "label": "elbow", "min": -1.69, "max": 1.69, "home": -1.2},
	{"id": "wrist_flex", "label": "wrist", "min": -1.66, "max": 1.66, "home": 0.9},
	{"id": "wrist_roll", "label": "roll", "min": -2.74, "max": 2.74, "home": 0.0},
	{"id": "gripper", "label": "grip", "min": -0.17, "max": 1.75, "home": 0.4},
]

@export var level_id := "demo_arm_lab"
@export var gateway_url := "ws://127.0.0.1:8765"
@export var room_id := ""

@onready var ws = $WsClient
@onready var camera_rig: Node3D = $CameraRig
@onready var hud_label: Label = $Hud/Margin/PanelContainer/MarginContainer/Label

var _is_web := false
var _controlled := false
var _joined := false
var _selected := 0
var _targets: Dictionary = {}
var _present: Dictionary = {}
var _enabled := false
var _send_accum := 0.0
var _dirty := false
var _link_state := "…"

## Programmatic arm visual: base + 3 links + gripper (angles from present).
var _link_shoulder: Node3D
var _link_elbow: Node3D
var _link_wrist: Node3D
var _grip_l: Node3D
var _grip_r: Node3D


func _ready() -> void:
	_is_web = OS.has_feature("web")
	for j in JOINTS:
		_targets[j["id"]] = float(j["home"])
		_present[j["id"]] = float(j["home"])
	_build_arm_visual()
	if _is_web:
		if not MWWebInput.web_key_event.is_connected(_on_web_key_event):
			MWWebInput.web_key_event.connect(_on_web_key_event)
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(true,false,true);}",
			true
		)
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(func(ok: bool) -> void: _link_state = "ON" if ok else "OFF")
	ws.connect_to_gateway(_resolve_gateway_url())
	MWTransition.notify_arrived()
	_update_hud()
	print("[MW] arm lab ready (hw_fake so101)")


func _resolve_gateway_url() -> String:
	if _is_web:
		var from_js := str(JavaScriptBridge.eval("window.MINEWORLD_GATEWAY || ''", true))
		if from_js != "":
			return from_js
	return gateway_url


func _on_hello(_payload: Dictionary) -> void:
	ws.join(level_id, "arm-pilot", room_id)


func _on_scene(payload: Dictionary) -> void:
	_joined = true
	ws.send_cmd({"action": "take_control", "entity_id": "arm_0"})
	var mw := (payload.get("extensions") as Dictionary).get("mw", {}) as Dictionary
	print("[MW] arm lab joined room=%s" % str(mw.get("room_id", "")))


func _on_state(_tick: int, _t_sim: float, payload: Dictionary) -> void:
	for ent in payload.get("entities", []) as Array:
		var e := ent as Dictionary
		if str(e.get("entity_id")) != "arm_0":
			continue
		var joints := e.get("joints", {}) as Dictionary
		for k in joints:
			_present[str(k)] = float(joints[k])
		var mw := (e.get("extensions") as Dictionary).get("mw", {}) as Dictionary
		_enabled = bool(mw.get("hw_enabled", _enabled))
	_apply_arm_visual()
	_update_hud()


func _on_gateway_error(payload: Dictionary) -> void:
	print("[MW] gateway error: %s" % str(payload.get("code")))


func _process(delta: float) -> void:
	_send_accum += delta
	if _send_accum >= 1.0 / CMD_HZ:
		_send_accum = 0.0
		if _dirty and _joined:
			_dirty = false
			ws.send_cmd({"entity_id": "arm_0", "joint_targets": _targets.duplicate()})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_on_key((event as InputEventKey).keycode)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_aim_at_click(mb.position)


func _on_web_key_event(code: String, down: bool) -> void:
	if not down:
		return
	var keymap := {
		"Digit1": KEY_1, "Digit2": KEY_2, "Digit3": KEY_3,
		"Digit4": KEY_4, "Digit5": KEY_5, "Digit6": KEY_6,
		"Comma": KEY_COMMA, "Period": KEY_PERIOD,
		"ArrowLeft": KEY_LEFT, "ArrowRight": KEY_RIGHT,
		"KeyH": KEY_H, "Space": KEY_SPACE,
	}
	if keymap.has(code):
		_on_key(int(keymap[code]))


func _on_key(keycode: int) -> void:
	match keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_selected = keycode - KEY_1
			_update_hud()
		KEY_COMMA, KEY_LEFT:
			_nudge(-NUDGE_RAD)
		KEY_PERIOD, KEY_RIGHT:
			_nudge(NUDGE_RAD)
		KEY_H:
			for j in JOINTS:
				_targets[j["id"]] = float(j["home"])
			_dirty = true
			_update_hud()
		KEY_SPACE:
			# Enable is implicit on joint_targets; Space re-sends current targets.
			_dirty = true


func _nudge(delta: float) -> void:
	var j: Dictionary = JOINTS[_selected]
	var jid := str(j["id"])
	var v: float = clamp(float(_targets[jid]) + delta, float(j["min"]), float(j["max"]))
	_targets[jid] = snappedf(v, 0.001)
	_dirty = true
	_update_hud()


func _aim_at_click(screen_pos: Vector2) -> void:
	"""Mouse click → shoulder_pan aims at the clicked bench point (no IK yet)."""
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	# Intersect bench plane y=0 (Godot Y-up; arm base at origin).
	if absf(dir.y) < 1e-4:
		return
	var t := -from.y / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	var pan := atan2(hit.x, hit.z)
	var j: Dictionary = JOINTS[0]
	_targets["shoulder_pan"] = snappedf(clampf(pan, float(j["min"]), float(j["max"])), 0.001)
	_selected = 0
	_dirty = true
	_update_hud()


## --- programmatic arm visual (3 links + 2-finger gripper) ---

func _make_link(parent: Node, pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = Vector3(0, 0, size.z * 0.5)
	holder.add_child(mi)
	return holder


func _build_arm_visual() -> void:
	var root := Node3D.new()
	root.name = "ArmVisual"
	add_child(root)
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.24, 0.08, 0.24)
	base.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.36)
	base.material_override = mat
	base.position = Vector3(0, 0.04, 0)
	root.add_child(base)
	var pan_holder := Node3D.new()
	pan_holder.name = "Pan"
	pan_holder.position = Vector3(0, 0.08, 0)
	root.add_child(pan_holder)
	# Links along local +Z; holders pitch around X.
	_link_shoulder = _make_link(pan_holder, Vector3.ZERO, Vector3(0.08, 0.08, 0.24), Color(0.85, 0.55, 0.2))
	_link_elbow = _make_link(_link_shoulder, Vector3(0, 0, 0.24), Vector3(0.06, 0.06, 0.2), Color(0.9, 0.65, 0.3))
	_link_wrist = _make_link(_link_elbow, Vector3(0, 0, 0.2), Vector3(0.05, 0.05, 0.12), Color(0.95, 0.75, 0.4))
	_grip_l = _make_link(_link_wrist, Vector3(-0.03, 0, 0.12), Vector3(0.02, 0.05, 0.08), Color(0.5, 0.5, 0.55))
	_grip_r = _make_link(_link_wrist, Vector3(0.03, 0, 0.12), Vector3(0.02, 0.05, 0.08), Color(0.5, 0.5, 0.55))
	# Keep pan holder reference for rotation.
	pan_holder.name = "PanHolder"
	set_meta("pan_holder", pan_holder.get_path())


func _apply_arm_visual() -> void:
	var pan_holder := get_node_or_null(get_meta("pan_holder", NodePath(""))) as Node3D
	if pan_holder == null:
		return
	pan_holder.rotation.y = -float(_present.get("shoulder_pan", 0.0))
	# Approximate FK for display only (authority stays gateway-side).
	_link_shoulder.rotation.x = float(_present.get("shoulder_lift", 0.3))
	_link_elbow.rotation.x = float(_present.get("elbow_flex", -1.2))
	_link_wrist.rotation.x = float(_present.get("wrist_flex", 0.9))
	pan_holder.rotation.z = float(_present.get("wrist_roll", 0.0))
	var gap: float = clampf(float(_present.get("gripper", 0.4)) * 0.05, 0.0, 0.09)
	_grip_l.position.x = -0.03 - gap
	_grip_r.position.x = 0.03 + gap


## --- HUD joint bars ---

func _bar(v: float, lo: float, hi: float, width: int = 14) -> String:
	var frac := 0.5
	if hi > lo:
		frac = clampf((v - lo) / (hi - lo), 0.0, 1.0)
	var fill := int(round(frac * width))
	return "█".repeat(fill) + "░".repeat(width - fill)


func _update_hud() -> void:
	if hud_label == null:
		return
	var lines: Array[String] = ["ARM LAB · hw_fake so101 · link %s · %s" % [_link_state, "enabled" if _enabled else "idle"], ""]
	for i in JOINTS.size():
		var j: Dictionary = JOINTS[i]
		var jid := str(j["id"])
		var cur := float(_present.get(jid, 0.0))
		var tgt := float(_targets.get(jid, 0.0))
		var sel := "▶" if i == _selected else " "
		lines.append("%s %-7s %+.2f→%+.2f %s" % [sel, str(j["label"]), cur, tgt,
			_bar(tgt, float(j["min"]), float(j["max"]))])
	lines.append("")
	lines.append("1-6 选关节 · ,/. 或 ←/→ 调目标 · H 回 HOME · 左键点台面对准")
	hud_label.text = "\n".join(lines)
