## Follow-orbit camera for teleoperation.
## Tracks the mech position; user orbits with RMB/MMB drag and zooms with
## the wheel. Yaw/pitch stay in world frame (mech rotation never spins the
## camera), so the view is stable while the mech turns.
extends Node3D

@export var target_path: NodePath
@export var distance := 13.0
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var pitch := -0.6 ## radians; negative = looking down
@export var yaw := 0.5
@export var zoom_step := 1.0
@export var orbit_sensitivity := 0.01

@onready var camera: Camera3D = $Camera3D
var _target: Node3D = null


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_update_camera()


func set_target(node: Node3D) -> void:
	"""Follow a different mech (e.g. assigned controlled_entity_id)."""
	_target = node
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
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


func _process(_delta: float) -> void:
	if _target == null:
		return
	global_position = _target.global_position
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	camera.global_position = global_position + rot * Vector3(0.0, 0.0, distance)
	camera.look_at(global_position, Vector3.UP)
