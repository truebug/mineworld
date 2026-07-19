## Follow-orbit camera for teleoperation.
## Tracks the mech position; user orbits with RMB/MMB drag and zooms with
## the wheel. Arrow keys pan the look-at on the ground plane; C recenters.
## Yaw/pitch stay in world frame (mech rotation never spins the camera).
extends Node3D

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

@onready var camera: Camera3D = $Camera3D
var _target: Node3D = null
## World-space offset of the look-at point from the mech (y ignored).
var look_offset := Vector3.ZERO


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_update_camera()


func set_target(node: Node3D) -> void:
	"""Follow a different mech (e.g. assigned controlled_entity_id)."""
	_target = node
	_update_camera()


func reset_look_offset() -> void:
	"""Snap look-at back onto the followed mech."""
	look_offset = Vector3.ZERO
	_update_camera()


func pan_axes(right: float, forward: float, delta: float) -> void:
	"""Pan on the ground plane in camera-relative axes (from keys / web bridge)."""
	if right == 0.0 and forward == 0.0:
		return
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
			distance = maxf(min_distance, distance - zoom_step)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance + zoom_step)
			_update_camera()
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			yaw -= event.relative.x * orbit_sensitivity
			pitch = clampf(pitch - event.relative.y * orbit_sensitivity, -1.45, -0.05)
			_update_camera()


func _process(delta: float) -> void:
	# Desktop arrow pan (Web: main.gd calls pan_axes from document keys).
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
	global_position = _target.global_position + look_offset
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	camera.global_position = global_position + rot * Vector3(0.0, 0.0, distance)
	camera.look_at(global_position, Vector3.UP)
