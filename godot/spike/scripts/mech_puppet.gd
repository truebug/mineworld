## Visual puppet for a gateway-driven entity.
## Buffers the last two base_pose samples and interpolates between them,
## delayed by one state interval (standard entity interpolation).
## F3/F5: Body mesh matches active mech URDF (DiffBot planar skin).
## Team look: tint chassis + billboard tag by entity_id (A/B).
class_name MWMechPuppet
extends Node3D

## Must be @export so Web/macOS export packs the scene override.
@export var entity_id: String = "mech_player"
var interp_delay := 0.05

## entity_id → chassis albedo (demo room A/B).
const TEAM_COLORS := {
	"mech_player": Color(0.22, 0.62, 0.95),
	"mech_player_b": Color(0.95, 0.48, 0.18),
}
const TEAM_TAGS := {
	"mech_player": "A",
	"mech_player_b": "B",
}

## third_party/diffbot/diffbot.urdf geometry (MW Z-up meters, ×10 skin). Keep in sync.
const URDF_CHASSIS := Vector3(1.0, 1.0, 0.5)
const URDF_WHEEL_R := 0.15
const URDF_WHEEL_LEN := 0.2
const URDF_WHEEL_POS := [
	Vector3(0.0, -0.5, -0.25),
	Vector3(0.0, 0.5, -0.25),
]
const URDF_CASTER_R := 0.15
const URDF_CASTER_POS := [
	Vector3(0.35, 0.0, -0.25),
	Vector3(-0.35, 0.0, -0.25),
]
const WHEEL_COLOR := Color(0.0, 0.0, 0.0)
const CASTER_COLOR := Color(1.0, 1.0, 1.0)

var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _prev_time := -1.0
var _next_pos := Vector3.ZERO
var _next_yaw := 0.0
var _next_time := -1.0
var _has_state := false
var _sim_now := 0.0
var _wall_at_last_state := 0.0
## Last authority pose (MW frame) for HUD/debug.
var last_mw_x := 0.0
var last_mw_y := 0.0
var last_mw_yaw := 0.0
var _cart_built := false


func _ready() -> void:
	ensure_planar_cart_visual()
	apply_team_look()


func _mw_to_local(p: Vector3) -> Vector3:
	"""Map MW/URDF Z-up point into Godot local (Y-up) on this puppet."""
	return Vector3(p.x, p.z, -p.y)


func _mw_size_to_local(s: Vector3) -> Vector3:
	"""Map MW full-edge box size (x,y,z) → Godot BoxMesh size (x,y,z)."""
	return Vector3(s.x, s.z, s.y)


func ensure_planar_cart_visual() -> void:
	"""Build/replace Body to match planar_cart.urdf (idempotent)."""
	if _cart_built and get_node_or_null("Body/Chassis") != null:
		return
	var old := get_node_or_null("Body")
	if old != null:
		remove_child(old)
		old.free()
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)

	var chassis := MeshInstance3D.new()
	chassis.name = "Chassis"
	var box := BoxMesh.new()
	box.size = _mw_size_to_local(URDF_CHASSIS)
	chassis.mesh = box
	chassis.set_meta("team_tint", true)
	body.add_child(chassis)

	var ci := 0
	for cp in URDF_CASTER_POS:
		var caster := MeshInstance3D.new()
		caster.name = "Caster_%d" % ci
		var sphere := SphereMesh.new()
		sphere.radius = URDF_CASTER_R
		sphere.height = URDF_CASTER_R * 2.0
		caster.mesh = sphere
		caster.position = _mw_to_local(cp)
		_tint_mesh(caster, CASTER_COLOR)
		body.add_child(caster)
		ci += 1

	var i := 0
	for wp in URDF_WHEEL_POS:
		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel_%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = URDF_WHEEL_R
		cyl.bottom_radius = URDF_WHEEL_R
		cyl.height = URDF_WHEEL_LEN
		wheel.mesh = cyl
		wheel.position = _mw_to_local(wp)
		# Cylinder default axis = Godot Y; lay flat so axis ≈ MW ±Y (Godot ±Z).
		wheel.rotation_degrees = Vector3(90, 0, 0)
		_tint_mesh(wheel, WHEEL_COLOR)
		body.add_child(wheel)
		i += 1

	_cart_built = true


func apply_team_look() -> void:
	"""Tint chassis mesh and show A/B billboard from entity_id."""
	ensure_planar_cart_visual()
	var color: Color = TEAM_COLORS.get(entity_id, Color(0.65, 0.65, 0.68))
	var chassis := get_node_or_null("Body/Chassis") as MeshInstance3D
	if chassis != null:
		_tint_mesh(chassis, color)
	else:
		var body_root := get_node_or_null("Body")
		if body_root is MeshInstance3D:
			_tint_mesh(body_root as MeshInstance3D, color)
		elif body_root != null:
			for child in body_root.find_children("*", "MeshInstance3D", true, false):
				if child.has_meta("team_tint"):
					_tint_mesh(child as MeshInstance3D, color)
	var tag := get_node_or_null("TeamTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "TeamTag"
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 72
		tag.outline_size = 10
		tag.outline_modulate = Color(0, 0, 0, 0.85)
		tag.position = Vector3(0.0, 1.15, 0.0)
		tag.pixel_size = 0.012
		add_child(tag)
	tag.text = str(TEAM_TAGS.get(entity_id, "?"))
	tag.modulate = color


func _tint_mesh(mesh_inst: MeshInstance3D, color: Color) -> void:
	"""Apply a simple albedo override."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.55
	mat.metallic = 0.15
	mesh_inst.material_override = mat


func apply_state(entity: Dictionary, t_sim: float) -> void:
	"""Push a new authority sample; t_sim must be monotonic for interpolation."""
	var pose: Dictionary = entity.get("base_pose", {})
	last_mw_x = float(pose.get("x", 0.0))
	last_mw_y = float(pose.get("y", 0.0))
	last_mw_yaw = float(pose.get("yaw", 0.0))
	# Fallback if t_sim missing/zero but pose is moving — avoid span<=0 freeze.
	if t_sim <= 0.0 and _next_time >= 0.0:
		t_sim = _next_time + interp_delay
	_sim_now = t_sim
	_wall_at_last_state = Time.get_ticks_msec() / 1000.0
	_prev_pos = _next_pos
	_prev_yaw = _next_yaw
	_prev_time = _next_time
	_next_pos = Vector3(last_mw_x, float(pose.get("z", 0.0)), -last_mw_y)
	_next_yaw = last_mw_yaw
	_next_time = t_sim
	if not _has_state:
		_has_state = true
		_prev_pos = _next_pos
		_prev_yaw = _next_yaw
		_prev_time = t_sim - interp_delay
		position = _next_pos
		rotation.y = _next_yaw


func _process(_delta: float) -> void:
	if not _has_state or _prev_time < 0.0:
		return
	var span := _next_time - _prev_time
	if span <= 0.0:
		# Degenerate timestamps: snap to latest authority pose.
		position = _next_pos
		rotation.y = _next_yaw
		return
	var render_time := _sim_clock() - interp_delay
	var alpha := clampf((render_time - _prev_time) / span, 0.0, 1.0)
	position = _prev_pos.lerp(_next_pos, alpha)
	rotation.y = _prev_yaw + (_next_yaw - _prev_yaw) * alpha


func _sim_clock() -> float:
	# Extrapolate forward from the last known sim time using wall clock,
	# so interpolation keeps moving between 20 Hz updates.
	return _sim_now + (Time.get_ticks_msec() / 1000.0 - _wall_at_last_state)
