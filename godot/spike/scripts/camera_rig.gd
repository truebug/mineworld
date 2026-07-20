## Follow-orbit camera for teleoperation / hub.
## Modes: orbit (wide 3rd), first-person, chase (close behind head). V cycles.
## Chase: locked to character — mouse look + zoom only (no pan).
extends Node3D

enum ViewMode { ORBIT, FIRST, CHASE }

@export var target_path: NodePath
@export var distance := 13.0
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var pitch := -0.6 ## radians; negative = looking down
@export var yaw := 0.5
@export var zoom_step := 1.0
@export var orbit_sensitivity := 0.01
@export var pan_speed := 8.0
@export var max_look_offset := 40.0
@export var view_mode: ViewMode = ViewMode.ORBIT
@export var chase_distance := 3.6
@export var min_chase_distance := 2.0
@export var max_chase_distance := 8.0

@onready var camera: Camera3D = $Camera3D
var _target: Node3D = null
## World-space offset of the look-at point from the mech (y ignored). Orbit only.
var look_offset := Vector3.ZERO
var _orbit_distance := 13.0
var _orbit_pitch := -0.6
var _orbit_yaw := 0.5
## First-person look offset relative to body forward (radians).
var _fp_yaw := 0.0
var _fp_pitch := 0.0
## Chase: mouse orbit relative to "behind head" (radians).
var _chase_yaw := 0.0
var _chase_pitch := -0.28


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_orbit_distance = distance
	_orbit_pitch = pitch
	_orbit_yaw = yaw
	_update_camera()


func set_target(node: Node3D) -> void:
	"""Follow a different mech (e.g. assigned controlled_entity_id)."""
	_target = node
	_update_camera()


func reset_look_offset() -> void:
	"""Snap look / pan / chase back to defaults for the current mode."""
	look_offset = Vector3.ZERO
	_fp_yaw = 0.0
	_fp_pitch = 0.0
	_chase_yaw = 0.0
	_chase_pitch = -0.28
	_update_camera()


func cycle_view_mode() -> String:
	"""Orbit → first-person → chase → orbit. Returns mode label."""
	match view_mode:
		ViewMode.ORBIT:
			view_mode = ViewMode.FIRST
			_fp_yaw = 0.0
			_fp_pitch = 0.0
		ViewMode.FIRST:
			view_mode = ViewMode.CHASE
			_chase_yaw = 0.0
			_chase_pitch = -0.28
			chase_distance = 3.6
		_:
			view_mode = ViewMode.ORBIT
			distance = _orbit_distance
			pitch = _orbit_pitch
			yaw = _orbit_yaw
	_update_camera()
	return view_mode_label()


func view_mode_label() -> String:
	"""Short HUD label for current mode."""
	match view_mode:
		ViewMode.FIRST:
			return "first-person"
		ViewMode.CHASE:
			return "chase (behind)"
		_:
			return "orbit"


func pan_axes(right: float, forward: float, delta: float) -> void:
	"""Arrow pan — orbit only; first-person looks; chase ignores (fixed to body)."""
	if right == 0.0 and forward == 0.0:
		return
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw -= right * 1.8 * delta
			_fp_pitch = clampf(_fp_pitch + forward * 1.2 * delta, -1.2, 1.0)
		ViewMode.CHASE:
			return
		_:
			_pan_ground(right, forward, delta)


func _pan_ground(right: float, forward: float, delta: float) -> void:
	"""Pan look_offset on the ground plane in camera-relative axes."""
	var basis := (
		camera.global_transform.basis
		if camera != null
		else Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	)
	var right_v := Vector3(basis.x.x, 0.0, basis.x.z)
	var forward_v := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if right_v.length_squared() < 1e-6:
		right_v = Vector3.RIGHT
	else:
		right_v = right_v.normalized()
	if forward_v.length_squared() < 1e-6:
		forward_v = Vector3.FORWARD
	else:
		forward_v = forward_v.normalized()
	look_offset += (right_v * right + forward_v * forward) * pan_speed * delta
	look_offset.y = 0.0
	var flat := Vector2(look_offset.x, look_offset.z)
	if flat.length() > max_look_offset:
		flat = flat.limit_length(max_look_offset)
		look_offset = Vector3(flat.x, 0.0, flat.y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C or event.physical_keycode == KEY_C:
			reset_look_offset()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_on_zoom(-1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_on_zoom(1.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_on_mouse_drag(event.relative)
			get_viewport().set_input_as_handled()


func _on_zoom(sign: float) -> void:
	"""Wheel zoom by mode."""
	match view_mode:
		ViewMode.FIRST:
			_fp_pitch = clampf(_fp_pitch - sign * 0.08, -1.2, 1.0)
		ViewMode.CHASE:
			chase_distance = clampf(
				chase_distance + sign * zoom_step * 0.45,
				min_chase_distance,
				max_chase_distance,
			)
		_:
			distance = clampf(distance + sign * zoom_step, min_distance, max_distance)
			_orbit_distance = distance
	_update_camera()


func _on_mouse_drag(relative: Vector2) -> void:
	"""RMB/MMB drag — orbit / look / chase turn (no chase pan)."""
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw -= relative.x * orbit_sensitivity
			_fp_pitch = clampf(_fp_pitch - relative.y * orbit_sensitivity, -1.2, 1.0)
		ViewMode.CHASE:
			_chase_yaw -= relative.x * orbit_sensitivity
			_chase_pitch = clampf(_chase_pitch - relative.y * orbit_sensitivity, -1.0, 0.45)
		_:
			yaw -= relative.x * orbit_sensitivity
			pitch = clampf(pitch - relative.y * orbit_sensitivity, -1.45, -0.05)
			_orbit_yaw = yaw
			_orbit_pitch = pitch
	_update_camera()


func _process(delta: float) -> void:
	"""Desktop arrow pan (Web: hub/main call pan_axes from key bridge)."""
	if not OS.has_feature("web"):
		var right := 0.0
		var forward := 0.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_RIGHT):
			right += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_LEFT):
			right -= 1.0
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_UP):
			forward += 1.0
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_DOWN):
			forward -= 1.0
		pan_axes(right, forward, delta)

	if _target == null:
		return
	if view_mode == ViewMode.FIRST or view_mode == ViewMode.CHASE:
		global_position = _target.global_position
	else:
		global_position = _target.global_position + look_offset
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	if view_mode == ViewMode.FIRST and _target != null:
		var eye := _target.global_position + Vector3(0, 1.05, 0)
		var body_yaw := _target.rotation.y
		var look_dir: Vector3 = (
			Basis(Vector3.UP, body_yaw + _fp_yaw)
			* Basis(Vector3.RIGHT, _fp_pitch)
			* Vector3(1, 0, 0)
		).normalized()
		camera.global_position = eye + look_dir * 0.2
		camera.look_at(eye + look_dir * 8.0, Vector3.UP)
		return
	if view_mode == ViewMode.CHASE and _target != null:
		# Look at upper chest / head; sit behind MW forward (+X) by default.
		var look := _target.global_position + Vector3(0, 1.15, 0)
		var body_yaw := _target.rotation.y
		# yaw=-PI/2 places orbit camera on -X when body_yaw=0 (behind +X forward).
		var orbit_yaw := body_yaw - PI * 0.5 + _chase_yaw
		var rot := Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, _chase_pitch)
		camera.global_position = look + rot * Vector3(0.0, 0.0, chase_distance)
		camera.look_at(look, Vector3.UP)
		return
	var rot2 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	camera.global_position = global_position + rot2 * Vector3(0.0, 0.0, distance)
	camera.look_at(global_position, Vector3.UP)
