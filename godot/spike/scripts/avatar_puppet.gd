## Hub avatar: procedural wheeled bot (no walk cycle — rolls look intentional).
## Godot +X = MW forward (visor / nose face +X).
class_name MWAvatarPuppet
extends Node3D

@export var entity_id: String = "avatar_0"
@export var accent: Color = Color(0.25, 0.72, 0.95)

var interp_delay := 0.05
var display_name := ""

var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _prev_time := -1.0
var _next_pos := Vector3.ZERO
var _next_yaw := 0.0
var _next_time := -1.0
var _has_state := false
var _sim_now := 0.0
var _wall_at_last_state := 0.0
var last_mw_x := 0.0
var last_mw_y := 0.0
var last_mw_yaw := 0.0
## Hub mezzanine: Godot Y offset (MW Z-up maps to Godot Y; FakeMech stays z≈0).
var height_offset := 0.0

var _wheels: Array = [] ## MeshInstance3D
var _last_render_pos := Vector3.ZERO

@onready var _label: Label3D = $NameTag


func _ready() -> void:
	"""Build wheeled bot mesh."""
	_build_bot()
	if _label != null:
		MWFonts.apply_label3d(_label)
		_label.text = display_name if display_name != "" else "Guest"
		_label.position = Vector3(0, 1.55, 0)
		_label.font_size = 28
		_label.outline_size = 4
		_label.pixel_size = 0.012


func _build_bot() -> void:
	"""Low chassis + side wheels + dome head; sits on the floor."""
	var root := Node3D.new()
	root.name = "WheelBot"
	add_child(root)
	var suit := accent
	var dark := accent.darkened(0.4)
	var light := accent.lightened(0.25)
	var tire := Color(0.12, 0.13, 0.15)
	# Chassis (low so it does not look like a floating ghost)
	_add_box(root, Vector3(0, 0.28, 0), Vector3(0.7, 0.28, 0.55), suit)
	_add_box(root, Vector3(0.05, 0.52, 0), Vector3(0.45, 0.22, 0.42), dark)
	# Nose / facing chevron on +X
	_add_box(root, Vector3(0.4, 0.32, 0), Vector3(0.12, 0.14, 0.28), Color(1.0, 0.55, 0.12), true)
	# Dome head + visor
	_add_sphere(root, Vector3(0, 0.85, 0), 0.22, light)
	_add_box(root, Vector3(0.18, 0.88, 0), Vector3(0.06, 0.1, 0.2), Color(0.08, 0.1, 0.14))
	# Antenna
	_add_box(root, Vector3(-0.05, 1.15, 0), Vector3(0.04, 0.28, 0.04), dark)
	_add_sphere(root, Vector3(-0.05, 1.32, 0), 0.05, Color(1.0, 0.4, 0.2), true)
	# Four wheels — axle along local Z (left/right); tread rolls on ground.
	for wz in [-0.32, 0.32]:
		for wx in [-0.22, 0.22]:
			var w := _add_wheel(root, Vector3(wx, 0.16, wz), 0.16, 0.1, tire)
			_wheels.append(w)


func _add_wheel(parent: Node3D, pos: Vector3, radius: float, width: float, color: Color) -> Node3D:
	"""Wheel whose axle is parent Z; CylinderMesh default Y is remapped onto that axle."""
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.position = pos
	# Tip cylinder (Y-up) onto its side so axle = parent Z.
	pivot.rotation_degrees.x = 90.0
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = width
	mi.mesh = cyl
	mi.material_override = _mat(color, false)
	pivot.add_child(mi)
	return pivot


func _add_box(
	parent: Node3D, pos: Vector3, size: Vector3, color: Color, emit: bool = false
) -> void:
	"""Add a box part."""
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = _mat(color, emit)
	parent.add_child(mi)
	mi.position = pos


func _add_sphere(
	parent: Node3D, pos: Vector3, radius: float, color: Color, emit: bool = false
) -> void:
	"""Add a sphere part."""
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	mi.material_override = _mat(color, emit)
	parent.add_child(mi)
	mi.position = pos


func _mat(color: Color, emit: bool) -> StandardMaterial3D:
	"""Shared PBR-ish material."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	mat.metallic = 0.45
	if emit:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.8
	return mat


func set_display(name_text: String, accent_hex: String = "") -> void:
	"""Update name tag."""
	display_name = name_text
	if _label != null:
		_label.text = name_text if name_text != "" else "Guest"
	if accent_hex != "":
		var c := Color(accent_hex)
		if c.a > 0.0:
			accent = c


func push_state(entity: Dictionary, t_sim: float) -> void:
	"""Buffer authority pose (MW Z-up → Godot Y-up)."""
	var pose: Variant = entity.get("base_pose", {})
	if typeof(pose) != TYPE_DICTIONARY:
		return
	var mw_x := float(pose.get("x", 0.0))
	var mw_y := float(pose.get("y", 0.0))
	var yaw := float(pose.get("yaw", 0.0))
	last_mw_x = mw_x
	last_mw_y = mw_y
	last_mw_yaw = yaw
	var godot_pos := Vector3(mw_x, height_offset, -mw_y)
	_sim_now = t_sim
	_wall_at_last_state = Time.get_ticks_msec() / 1000.0
	if not _has_state:
		_prev_pos = godot_pos
		_next_pos = godot_pos
		_prev_yaw = yaw
		_next_yaw = yaw
		_prev_time = t_sim
		_next_time = t_sim
		_has_state = true
		global_position = godot_pos
		rotation.y = yaw
		_last_render_pos = godot_pos
		return
	_prev_pos = _next_pos
	_prev_yaw = _next_yaw
	_prev_time = _next_time
	_next_pos = godot_pos
	_next_yaw = yaw
	_next_time = t_sim
	var ext: Variant = entity.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var mw: Variant = ext.get("mw", {})
		if typeof(mw) == TYPE_DICTIONARY:
			var dn := str(mw.get("display_name", ""))
			var ac := str(mw.get("accent", ""))
			if dn != "" or ac != "":
				set_display(dn if dn != "" else display_name, ac)


func _process(_delta: float) -> void:
	"""Interpolate pose; spin wheels by ground distance."""
	if not _has_state:
		return
	var wall_now := Time.get_ticks_msec() / 1000.0
	var render_t := _sim_now + (wall_now - _wall_at_last_state) - interp_delay
	var span := _next_time - _prev_time
	var alpha := 1.0 if span <= 1e-6 else clampf((render_t - _prev_time) / span, 0.0, 1.0)
	global_position = _prev_pos.lerp(_next_pos, alpha)
	rotation.y = lerp_angle(_prev_yaw, _next_yaw, alpha)
	var move := global_position - _last_render_pos
	_last_render_pos = global_position
	var dist := Vector2(move.x, move.z).length()
	if dist > 1e-5:
		var roll := dist / 0.16  ## radius ≈ 0.16
		for w in _wheels:
			if w is Node3D:
				# Pivot local +Y is the axle after the 90° tip.
				(w as Node3D).rotate_object_local(Vector3.UP, roll)
