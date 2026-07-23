## Hub avatar: Kenney Blocky humanoid (idle / walk / sprint).
## Godot +X = MW forward (mesh yaw offset aligns GLB face to +X).
## Gateway FakeMech unchanged — locomotion anims are visual-only.
class_name MWAvatarPuppet
extends Node3D

const BLOCKY_DIR := "res://assets/kenney_blocky/"
const BLOCKY_SCALE := 0.36
## Kenney face is typically −Z; rotate so facing matches puppet +X.
const MESH_YAW_DEG := 90.0
const SPEED_IDLE := 0.25
const SPEED_SPRINT := 3.2  # above hub MOVE_SPEED 2.8: normal locomotion shows walk
const ANIM_BLEND := 0.15
## E9: public-net feel — cap catch-up / extrap so remotes don't "fly".
const MAX_GROUND_SPEED := 4.0
const MAX_EXTRAP_S := 0.28
const EXTRAP_HOLD_S := 0.45  # stale stream: stop extrapolating, hold authority pose
const SNAP_DIST := 3.5

@export var entity_id: String = "avatar_0"
@export var accent: Color = Color(0.25, 0.72, 0.95)

var interp_delay := 0.05
var display_name := ""
## Own avatar: short body-frame prediction between authority samples.
var local_predict := false

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
## Hub-only visual hop on top of height_offset (Space; not in FakeMech).
var _hop_y := 0.0
var _hop_vy := 0.0
const HOP_SPEED := 5.0
const HOP_GRAVITY := 16.0
## Must match hub.gd / hub_dress FLOOR2_Y.
const HUB_FLOOR2_Y := 8.5

var _last_render_pos := Vector3.ZERO
var _speed_smooth := 0.0
var _skin_letter := ""
var _mesh_root: Node3D = null
var _anim: AnimationPlayer = null
var _anim_playing := ""
var _cmd_vx := 0.0
var _cmd_vy := 0.0
var _cmd_yaw_rate := 0.0

@onready var _label: Label3D = $NameTag


func _ready() -> void:
	"""Instance Blocky skin and name tag."""
	_ensure_skin(true)
	if _label != null:
		MWFonts.apply_label3d(_label)
		_label.text = display_name if display_name != "" else "Guest"
		_label.position = Vector3(0, 1.4, 0)
		_label.font_size = 28
		_label.outline_size = 4
		_label.pixel_size = 0.012
		_label.modulate = accent


func _ensure_skin(force: bool = false) -> void:
	"""Load character-a..d from accent / entity_id; rebuild when letter changes."""
	var letter := _pick_skin_letter()
	if not force and letter == _skin_letter and _mesh_root != null:
		return
	_skin_letter = letter
	if _mesh_root != null:
		var old := _mesh_root
		_mesh_root = null
		_anim = null
		_anim_playing = ""
		if old.get_parent() == self:
			remove_child(old)
		old.free()
	var path := "%scharacter-%s.glb" % [BLOCKY_DIR, letter]
	if not ResourceLoader.exists(path):
		_build_fallback()
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_build_fallback()
		return
	var wrap := Node3D.new()
	wrap.name = "Blocky"
	add_child(wrap)
	# Keep NameTag as sibling drawn above; mesh under wrap.
	move_child(wrap, 0)
	wrap.rotation_degrees.y = MESH_YAW_DEG
	var node := packed.instantiate() as Node3D
	wrap.add_child(node)
	node.name = "Mesh"
	node.scale = Vector3(BLOCKY_SCALE, BLOCKY_SCALE, BLOCKY_SCALE)
	_mesh_root = wrap
	_anim = _find_anim_player(node)
	if _anim != null:
		_anim.active = true
		for loco in ["idle", "walk", "sprint"]:
			var loco_clip := _resolve_anim(loco)
			if loco_clip != "":
				_anim.get_animation(loco_clip).loop_mode = Animation.LOOP_LINEAR
		_play_anim("idle")
	call_deferred("_plant_feet")


func _pick_skin_letter() -> String:
	"""Map accent hue → a..d; desaturated accents fall back to entity slot."""
	var letters := ["a", "b", "c", "d"]
	var idx := 0
	if accent.s >= 0.12:
		idx = int(floor(accent.h * 4.0)) % 4
	else:
		idx = absi(hash(entity_id)) % 4
	return letters[idx]


func _find_anim_player(n: Node) -> AnimationPlayer:
	"""First AnimationPlayer in the GLB tree."""
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _resolve_anim(want: String) -> String:
	"""Match clip name with or without AnimationLibrary prefix."""
	if _anim == null:
		return ""
	for n in _anim.get_animation_list():
		if str(n) == want or str(n).ends_with("/" + want):
			return str(n)
	return ""


func _play_anim(want: String) -> void:
	"""Cross-fade to idle/walk/sprint when available."""
	if _anim == null:
		return
	var clip := _resolve_anim(want)
	if clip == "":
		return
	if clip == _anim_playing and _anim.is_playing():
		return
	_anim.play(clip, ANIM_BLEND)
	_anim_playing = clip


func _plant_feet() -> void:
	"""Shift mesh so lowest vertex sits on local y=0 (floating pivots)."""
	if _mesh_root == null:
		return
	var mesh := _mesh_root.get_node_or_null("Mesh") as Node3D
	if mesh == null:
		return
	var min_y := 1e9
	for mi in _all_meshes(mesh):
		var aabb: AABB = mi.get_aabb()
		var p := aabb.position
		var e := aabb.end
		var corners := [
			Vector3(p.x, p.y, p.z), Vector3(p.x, p.y, e.z),
			Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z),
			Vector3(p.x, e.y, p.z), Vector3(p.x, e.y, e.z),
			Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z),
		]
		for c in corners:
			var w: Vector3 = mi.global_transform * c
			min_y = minf(min_y, w.y)
	if min_y < 1e8:
		# Keep world feet on floor while puppet may sit at height_offset.
		var floor_y := global_position.y
		mesh.global_position.y += floor_y - min_y


func _all_meshes(n: Node) -> Array:
	"""Collect MeshInstance3D descendants."""
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _build_fallback() -> void:
	"""Procedural stand-in if GLB missing (e.g. incomplete export)."""
	var root := Node3D.new()
	root.name = "Blocky"
	add_child(root)
	move_child(root, 0)
	_mesh_root = root
	var dark := accent.darkened(0.35)
	_add_box(root, Vector3(0, 0.45, 0), Vector3(0.35, 0.55, 0.22), accent)
	_add_box(root, Vector3(0, 0.9, 0), Vector3(0.26, 0.26, 0.26), accent.lightened(0.15))
	_add_box(root, Vector3(0.1, 0.2, 0), Vector3(0.12, 0.35, 0.12), dark)
	_add_box(root, Vector3(-0.1, 0.2, 0), Vector3(0.12, 0.35, 0.12), dark)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	"""Fallback body part."""
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func set_display(name_text: String, accent_hex: String = "") -> void:
	"""Update name tag; Hub short codes look like «Nick · #A1B2»."""
	display_name = name_text
	if _label != null:
		_label.text = name_text if name_text != "" else "Guest"
		_label.font_size = 42 if name_text.find(" · #") >= 0 else 48
	if accent_hex != "":
		var c := Color(accent_hex)
		if c.a > 0.0:
			accent = c
			if _label != null:
				_label.modulate = accent
			_ensure_skin(false)


func set_local_cmd(vx: float, vy: float, yaw_rate: float) -> void:
	"""Cache last velocity cmd for local_predict (body frame, MW)."""
	_cmd_vx = vx
	_cmd_vy = vy
	_cmd_yaw_rate = yaw_rate


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
		_apply_profile_ext(entity)
		return
	# Large authority jumps (join / soft-push stack): snap, don't lerp across the map.
	var jump := Vector2(godot_pos.x - _next_pos.x, godot_pos.z - _next_pos.z).length()
	if jump > SNAP_DIST:
		_prev_pos = godot_pos
		_next_pos = godot_pos
		_prev_yaw = yaw
		_next_yaw = yaw
		_prev_time = t_sim
		_next_time = t_sim
		global_position = godot_pos
		rotation.y = yaw
		_last_render_pos = godot_pos
		_apply_profile_ext(entity)
		return
	# Own avatar: soft-correct toward authority so prediction does not rubber-band hard.
	if local_predict:
		var err := Vector2(godot_pos.x - global_position.x, godot_pos.z - global_position.z)
		if err.length() < SNAP_DIST:
			_prev_pos = global_position
			_prev_yaw = rotation.y
			_prev_time = t_sim - maxf(interp_delay, 0.04)
			_next_pos = godot_pos
			_next_yaw = yaw
			_next_time = t_sim
			_apply_profile_ext(entity)
			return
	_prev_pos = _next_pos
	_prev_yaw = _next_yaw
	_prev_time = _next_time
	_next_pos = godot_pos
	_next_yaw = yaw
	_next_time = t_sim
	_apply_profile_ext(entity)


func _apply_profile_ext(entity: Dictionary) -> void:
	"""Optional display_name / accent / hub_floor from extensions.mw."""
	var ext: Variant = entity.get("extensions", {})
	if typeof(ext) != TYPE_DICTIONARY:
		return
	var mw: Variant = ext.get("mw", {})
	if typeof(mw) != TYPE_DICTIONARY:
		return
	var dn := str(mw.get("display_name", ""))
	var ac := str(mw.get("accent", ""))
	if dn != "" or ac != "":
		set_display(dn if dn != "" else display_name, ac)
	if mw.has("hub_floor"):
		_apply_hub_floor_from_net(int(mw.get("hub_floor", 1)))
	if mw.has("hop_y"):
		_apply_hop_from_net(float(mw.get("hop_y", 0.0)))


func _apply_hub_floor_from_net(floor: int) -> void:
	"""Sync mezzanine height from authority (Hub FakeMech stays planar)."""
	var want := HUB_FLOOR2_Y if floor == 2 else 0.0
	if absf(want - height_offset) < 0.01:
		return
	height_offset = want
	reset_hub_hop()
	var y := _feet_y()
	global_position.y = y
	_prev_pos.y = y
	_next_pos.y = y
	_last_render_pos.y = y


func try_hub_hop() -> bool:
	"""Hub Space jump — visual Y only; grounded check."""
	if _hop_y > 0.02 or _hop_vy > 0.05:
		return false
	_hop_vy = HOP_SPEED
	return true


func reset_hub_hop() -> void:
	"""Cancel in-air hop (elevator / floor change)."""
	_hop_y = 0.0
	_hop_vy = 0.0


func get_hub_hop_y() -> float:
	"""Current visual hop height for cmd piggyback."""
	return _hop_y


func _feet_y() -> float:
	"""Floor deck + hop offset."""
	return height_offset + _hop_y


func _integrate_hop(dt: float) -> void:
	"""Integrate hub hop parabola (own avatar only; remotes use net hop_y)."""
	if not local_predict:
		return
	if _hop_vy == 0.0 and _hop_y == 0.0:
		return
	_hop_vy -= HOP_GRAVITY * dt
	_hop_y += _hop_vy * dt
	if _hop_y <= 0.0:
		_hop_y = 0.0
		_hop_vy = 0.0


func _apply_hop_from_net(y: float) -> void:
	"""Remote hop height from authority (cm-ish; FakeMech planar)."""
	if local_predict:
		return
	var want := clampf(y, 0.0, 4.0)
	if absf(want - _hop_y) < 0.005:
		return
	_hop_y = want
	_hop_vy = 0.0


func _process(delta: float) -> void:
	"""Interpolate / rate-limited extrap; optional local predict for self."""
	if not _has_state:
		return
	var dt := maxf(delta, 1e-4)
	_integrate_hop(dt)
	if local_predict:
		_step_local_predict(dt)
	var wall_now := Time.get_ticks_msec() / 1000.0
	var render_t := _sim_now + (wall_now - _wall_at_last_state) - interp_delay
	var span := _next_time - _prev_time
	var target := _next_pos
	var target_yaw := _next_yaw
	if span > 1e-6:
		var alpha := (render_t - _prev_time) / span
		# Stale stream (delta compression drops stationary entities): the
		# (next-prev)/span velocity is soft-correct residue, not motion —
		# extrapolating it caused the 1.25 s authority-keyframe pendulum.
		var state_age := wall_now - _wall_at_last_state
		if alpha <= 1.0:
			target = _prev_pos.lerp(_next_pos, clampf(alpha, 0.0, 1.0))
			target_yaw = lerp_angle(_prev_yaw, _next_yaw, clampf(alpha, 0.0, 1.0))
		elif local_predict or state_age > EXTRAP_HOLD_S:
			# Own avatar: prediction drives motion; hold authority anchor.
			# Any puppet: stream stale > window → hold last authority pose.
			target = _next_pos
			target_yaw = _next_yaw
		else:
			var sample_vel := (_next_pos - _prev_pos) / span
			var spd := Vector2(sample_vel.x, sample_vel.z).length()
			if spd > MAX_GROUND_SPEED and spd > 1e-6:
				sample_vel *= MAX_GROUND_SPEED / spd
			var past := minf((alpha - 1.0) * span, MAX_EXTRAP_S)
			target = _next_pos + sample_vel * past
			target_yaw = _next_yaw
	target.y = _feet_y()
	# Per-frame catch-up cap (remotes); own predict already stepped.
	if not local_predict:
		var delta_pos := target - global_position
		var flat := Vector2(delta_pos.x, delta_pos.z)
		var flat_len := flat.length()
		if flat_len > SNAP_DIST:
			global_position = target
		else:
			var max_step := MAX_GROUND_SPEED * dt * 1.35
			if flat_len > max_step and flat_len > 1e-6:
				flat *= max_step / flat_len
				global_position.x += flat.x
				global_position.z += flat.y
				global_position.y = target.y
			else:
				global_position = target
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(dt * 12.0, 0.0, 1.0))
	else:
		# Soft pull toward interpolated authority while predicting.
		global_position = global_position.lerp(target, clampf(dt * 8.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(dt * 10.0, 0.0, 1.0))
	var move := global_position - _last_render_pos
	_last_render_pos = global_position
	var dist := Vector2(move.x, move.z).length()
	_speed_smooth = lerpf(_speed_smooth, dist / dt, 0.28)
	if _speed_smooth < SPEED_IDLE:
		_play_anim("idle")
	elif _speed_smooth >= SPEED_SPRINT:
		_play_anim("sprint")
	else:
		_play_anim("walk")


func _step_local_predict(dt: float) -> void:
	"""Integrate last cmd in FakeMech body frame (visual only)."""
	var yaw := rotation.y
	var c := cos(yaw)
	var s := sin(yaw)
	var d_mw_x := (c * _cmd_vx - s * _cmd_vy) * dt
	var d_mw_y := (s * _cmd_vx + c * _cmd_vy) * dt
	global_position.x += d_mw_x
	global_position.z -= d_mw_y
	global_position.y = _feet_y()
	rotation.y += _cmd_yaw_rate * dt
	last_mw_x = global_position.x
	last_mw_y = -global_position.z
	last_mw_yaw = rotation.y
