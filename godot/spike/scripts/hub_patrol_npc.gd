## Local FakeMech-free patrol walker (Hub atmosphere only; not on Gateway).
## Walks a loop; dwells at each stop with a soft speech bubble.
extends Node3D

const NPC_SCALE := 0.36
const BLOCKY_DIR := "res://assets/kenney_blocky/"
const ARRIVE_DIST := 0.35
const DWELL_S := 2.6

@export var move_speed := 1.35
var waypoints: Array = [] ## Vector3
var _wp_i := 0
var _anim: AnimationPlayer = null
var _speed_smooth := 0.0
var _dwell_left := 0.0
var _bubble: Node3D = null
var _rng := RandomNumberGenerator.new()


func setup(asset: String, path: Array, accent: Color, lines: Array = [], start_offset: float = 0.0) -> void:
	"""Build mesh + waypoint loop; optional chat lines shown while dwelling."""
	_rng.randomize()
	waypoints = path.duplicate()
	if waypoints.is_empty():
		waypoints = [global_position]
	global_position = waypoints[0]
	if not _spawn_blocky(asset):
		_fallback(accent)
	else:
		call_deferred("_plant_feet")
	if not lines.is_empty():
		_bubble = preload("res://scripts/hub_speech_bubble.gd").new()
		_bubble.name = "SpeechBubble"
		add_child(_bubble)
		_bubble.position = Vector3(0, 1.85, 0)
		_bubble.set("dwell_only", true)
		_bubble.set("hold_s", 3.4)
		_bubble.call("setup", lines, accent.lightened(0.25), start_offset)
		_bubble.call("set_dwell_active", false)
	# Brief pause at spawn so plaza is not empty-walkers-only.
	_dwell_left = 1.2 + _rng.randf() * 1.4
	_play("idle")
	if _bubble != null:
		_bubble.call("set_dwell_active", true)


func _spawn_blocky(asset: String) -> bool:
	"""Instance Kenney Blocky for patrol."""
	var path := BLOCKY_DIR + asset
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var wrap := Node3D.new()
	wrap.name = "Mesh"
	wrap.rotation_degrees.y = 90.0
	add_child(wrap)
	var node := packed.instantiate() as Node3D
	wrap.add_child(node)
	node.scale = Vector3(NPC_SCALE, NPC_SCALE, NPC_SCALE)
	_anim = _find_anim(node)
	if _anim != null:
		_anim.active = true
		_play("walk")
	return true


func _find_anim(n: Node) -> AnimationPlayer:
	"""First AnimationPlayer under mesh."""
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null


func _play(want: String) -> void:
	"""Play clip if present."""
	if _anim == null:
		return
	for n in _anim.get_animation_list():
		if str(n) == want or str(n).ends_with("/" + want):
			if _anim.current_animation != str(n):
				_anim.play(str(n), 0.12)
			return


func _fallback(accent: Color) -> void:
	"""Box figure if GLB missing."""
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.9, 0.3)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mi.material_override = mat
	mi.position = Vector3(0, 0.45, 0)
	add_child(mi)


func _plant_feet() -> void:
	"""Drop mesh so feet sit on y=0."""
	var mesh := get_node_or_null("Mesh") as Node3D
	if mesh == null:
		return
	var min_y := 1e9
	for mi in _collect_meshes(mesh):
		var aabb: AABB = mi.get_aabb()
		for c in [
			aabb.position,
			Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
			Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
			Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
		]:
			min_y = minf(min_y, (mi.global_transform * c).y)
	if min_y < 1e8:
		mesh.global_position.y -= min_y


func _collect_meshes(n: Node) -> Array:
	"""MeshInstance3D list."""
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _process(delta: float) -> void:
	"""Dwell at stops (bubble on), then walk to next waypoint."""
	if waypoints.size() < 2:
		_play("idle")
		return
	if _dwell_left > 0.0:
		_dwell_left = maxf(0.0, _dwell_left - delta)
		_speed_smooth = lerpf(_speed_smooth, 0.0, 0.25)
		_play("idle")
		if _bubble != null:
			_bubble.call("set_dwell_active", true)
		if _dwell_left <= 0.0 and _bubble != null:
			_bubble.call("set_dwell_active", false)
		return
	var target: Vector3 = waypoints[_wp_i]
	target.y = global_position.y
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < ARRIVE_DIST:
		_wp_i = (_wp_i + 1) % waypoints.size()
		_dwell_left = DWELL_S + _rng.randf() * 1.8
		_play("idle")
		if _bubble != null:
			_bubble.call("set_dwell_active", true)
		return
	var step := minf(move_speed * delta, dist)
	var dir := to / dist
	global_position += dir * step
	rotation.y = atan2(-dir.z, dir.x)
	_speed_smooth = lerpf(_speed_smooth, move_speed, 0.2)
	_play("walk")
	if _bubble != null:
		_bubble.call("set_dwell_active", false)
