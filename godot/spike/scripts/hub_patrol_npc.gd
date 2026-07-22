## Local FakeMech-free patrol walker (Hub atmosphere only; not on Gateway).
extends Node3D

const NPC_SCALE := 0.36
const BLOCKY_DIR := "res://assets/kenney_blocky/"

@export var move_speed := 1.35
var waypoints: Array = [] ## Vector3
var _wp_i := 0
var _anim: AnimationPlayer = null
var _speed_smooth := 0.0


func setup(asset: String, path: Array, accent: Color) -> void:
	"""Build mesh + waypoint loop."""
	waypoints = path.duplicate()
	if waypoints.is_empty():
		waypoints = [global_position]
	global_position = waypoints[0]
	if not _spawn_blocky(asset):
		_fallback(accent)
	else:
		call_deferred("_plant_feet")


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
	"""Walk toward next waypoint; loop."""
	if waypoints.size() < 2:
		_play("idle")
		return
	var target: Vector3 = waypoints[_wp_i]
	target.y = global_position.y
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.35:
		_wp_i = (_wp_i + 1) % waypoints.size()
		return
	var step := minf(move_speed * delta, dist)
	var dir := to / dist
	global_position += dir * step
	rotation.y = atan2(-dir.z, dir.x)
	_speed_smooth = lerpf(_speed_smooth, move_speed, 0.2)
	_play("walk")
