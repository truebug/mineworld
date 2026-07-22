## Viewer-only factory dress for demo_workshop (Kenney Factory Kit subset).
## Places props along walls / work areas; does NOT hide or modify Authority meshes.
extends Node3D

const ASSET_DIR := "res://assets/kenney_factory/"
const FLOOR_ASSET := "floor-large.glb"
const FLOOR_Y := 0.01

## Godot placement: (x, z) with Y-up; MW (x,y) → Godot (x, 0, -y).
## Keep center corridor (z≈0) clear for spawn → crate → bin.
const PLACEMENTS: Array = [
	# North wall strip (Godot +Z / MW −Y)
	{"asset": "structure-tall.glb", "x": 6.0, "z": 10.5, "yaw": 0.0, "s": 1.0},
	{"asset": "structure-medium.glb", "x": 10.0, "z": 10.5, "yaw": 0.0, "s": 1.0},
	{"asset": "machine.glb", "x": 14.0, "z": 10.2, "yaw": 180.0, "s": 1.0},
	{"asset": "machine-fortified.glb", "x": 18.0, "z": 10.2, "yaw": 180.0, "s": 1.0},
	{"asset": "structure-window.glb", "x": 22.0, "z": 10.5, "yaw": 0.0, "s": 1.0},
	{"asset": "structure-high.glb", "x": 26.0, "z": 10.5, "yaw": 0.0, "s": 1.0},
	# South wall strip (Godot −Z / MW +Y)
	{"asset": "conveyor-long.glb", "x": 8.0, "z": -10.5, "yaw": 90.0, "s": 1.0},
	{"asset": "conveyor.glb", "x": 12.0, "z": -10.5, "yaw": 90.0, "s": 1.0},
	{"asset": "conveyor-long.glb", "x": 16.0, "z": -10.5, "yaw": 90.0, "s": 1.0},
	{"asset": "box-large.glb", "x": 20.0, "z": -10.2, "yaw": 15.0, "s": 1.0},
	{"asset": "box-wide.glb", "x": 22.5, "z": -10.2, "yaw": -10.0, "s": 1.0},
	{"asset": "structure-yellow-medium.glb", "x": 26.0, "z": -10.5, "yaw": 180.0, "s": 1.0},
	# West inner (near spawn, leave driving lane)
	{"asset": "structure-corner-outer.glb", "x": 1.8, "z": 8.0, "yaw": 0.0, "s": 1.0},
	{"asset": "structure-corner-outer.glb", "x": 1.8, "z": -8.0, "yaw": 90.0, "s": 1.0},
	{"asset": "door-wide-closed.glb", "x": 1.6, "z": 0.0, "yaw": 90.0, "s": 1.0},
	{"asset": "screen-panel-wide.glb", "x": 2.2, "z": 4.0, "yaw": 90.0, "s": 1.0},
	{"asset": "cone.glb", "x": 3.0, "z": 3.0, "yaw": 0.0, "s": 1.0},
	{"asset": "warning-orange.glb", "x": 3.0, "z": -3.0, "yaw": 0.0, "s": 1.0},
	# Workbench bay (authority workbench at Godot 15,8)
	{"asset": "structure-doorway.glb", "x": 12.0, "z": 8.5, "yaw": 0.0, "s": 1.0},
	{"asset": "pipe-large-valve.glb", "x": 17.5, "z": 9.0, "yaw": -90.0, "s": 1.0},
	{"asset": "pipe-large.glb", "x": 19.0, "z": 9.0, "yaw": 0.0, "s": 1.0},
	{"asset": "pipe-large-bend.glb", "x": 20.5, "z": 9.0, "yaw": 90.0, "s": 1.0},
	{"asset": "crane.glb", "x": 15.0, "z": 6.5, "yaw": 0.0, "s": 1.0},
	# Bin / stow area (Godot x≈26)
	{"asset": "hopper-square.glb", "x": 24.5, "z": 2.5, "yaw": 0.0, "s": 1.0},
	{"asset": "hopper-round.glb", "x": 24.5, "z": -2.5, "yaw": 0.0, "s": 1.0},
	{"asset": "box-small.glb", "x": 27.5, "z": 1.5, "yaw": 20.0, "s": 1.0},
	{"asset": "box-small.glb", "x": 27.5, "z": -1.2, "yaw": -25.0, "s": 1.0},
	{"asset": "box-large.glb", "x": 28.0, "z": 3.5, "yaw": 5.0, "s": 1.0},
	{"asset": "structure-wall.glb", "x": 28.5, "z": 0.0, "yaw": 90.0, "s": 1.0},
]


func _ready() -> void:
	"""Spawn factory props under this Decor node."""
	call_deferred("_place_all")


## Sparse floor pads (keep concrete Ground visible; full Kenney tile wash looks flat/purple).
## Corridor z≈0 left clear for neon path (spawn → crate → bin).
const FLOOR_PADS: Array = [
	{"x": 8.0, "z": 4.0}, {"x": 12.0, "z": -4.0}, {"x": 18.0, "z": 4.0}, {"x": 22.0, "z": -4.0},
	{"x": 26.0, "z": 4.0}, {"x": 26.0, "z": -4.0},
]

## Fake nav glow path in Godot XZ (MW spawn → block → place pad). Viewer-only.
const PATH_WAYPOINTS: Array = [
	Vector2(4.0, 0.0),
	Vector2(7.0, -1.5),
	Vector2(15.0, 8.0),
]
const PATH_Y := 0.03
const PATH_WIDTH := 0.38
const PATH_SEG_LEN := 1.15
const PATH_GAP := 0.28


func _place_all() -> void:
	"""Place floor pads + neon path + place pad + props; keep concrete Ground as base."""
	var floor_n := _place_floor_pads()
	var path_n := _place_neon_path()
	_place_place_pad()
	var n := 0
	for item in PLACEMENTS:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var name := str(d.get("asset", ""))
		if _spawn_asset(name, float(d.get("x", 0.0)), float(d.get("z", 0.0)), float(d.get("yaw", 0.0)), float(d.get("s", 1.0)), n):
			n += 1
	print("[MW] workshop dress floor_pads=%d path_segs=%d props=%d (viewer_only)" % [floor_n, path_n, n])


func _place_place_pad() -> void:
	"""Viewer-only orange AABB hint for trigger_place (MW y→Godot −z)."""
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.45, 0.12, 0.35)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.6, 0.04, 1.6)
	var mi := MeshInstance3D.new()
	mi.name = "PlacePad"
	mi.mesh = mesh
	mi.material_override = mat
	# MW trigger_place center ~(15, -8, 1.16) → Godot (15, 1.16, 8)
	mi.position = Vector3(15.0, 1.02, 8.0)
	add_child(mi)
	var label := Label3D.new()
	label.name = "PlacePadLabel"
	label.text = "放置区"
	label.font_size = 48
	label.modulate = Color(1.0, 0.85, 0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(15.0, 1.55, 8.0)
	MWFonts.apply_label3d(label)
	add_child(label)


func _place_neon_path() -> int:
	"""Build dashed emissive floor strips along PATH_WAYPOINTS (fake nav, no physics)."""
	var mat := _make_neon_mat()
	var soft := _make_neon_soft_mat()
	var root := Node3D.new()
	root.name = "NeonPath"
	add_child(root)
	var count := 0
	for i in range(PATH_WAYPOINTS.size() - 1):
		var a: Vector2 = PATH_WAYPOINTS[i]
		var b: Vector2 = PATH_WAYPOINTS[i + 1]
		count += _place_path_segment(root, a, b, mat, soft, count)
	# Soft omni markers so Web Compatibility still gets a hint of glow.
	_place_path_omnis(root)
	return count


func _make_neon_mat() -> StandardMaterial3D:
	"""Bright orange emissive strip material."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.12, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 2.4
	mat.roughness = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_neon_soft_mat() -> StandardMaterial3D:
	"""Wider soft halo under the strip."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.05, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.02)
	mat.emission_energy_multiplier = 1.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _place_path_segment(
	parent: Node3D, a: Vector2, b: Vector2, mat: StandardMaterial3D, soft: StandardMaterial3D, start_idx: int
) -> int:
	"""Lay dashed boxes from a→b on the floor."""
	var delta := b - a
	var length := delta.length()
	if length < 0.05:
		return 0
	var dir := delta / length
	# BoxMesh local +X along path; Godot Yaw = atan2(-z, x) for Vector2(x,z).
	var yaw := atan2(-dir.y, dir.x)
	var placed := 0
	var t := 0.0
	while t + PATH_SEG_LEN * 0.35 < length:
		var seg := minf(PATH_SEG_LEN, length - t)
		var mid := a + dir * (t + seg * 0.5)
		var mi := MeshInstance3D.new()
		mi.name = "PathSeg_%d" % (start_idx + placed)
		var box := BoxMesh.new()
		box.size = Vector3(seg, 0.02, PATH_WIDTH)
		box.material = mat
		mi.mesh = box
		mi.position = Vector3(mid.x, PATH_Y, mid.y)
		mi.rotation.y = yaw
		parent.add_child(mi)
		var halo := MeshInstance3D.new()
		halo.name = "PathHalo_%d" % (start_idx + placed)
		var soft_box := BoxMesh.new()
		soft_box.size = Vector3(seg * 1.05, 0.01, PATH_WIDTH * 2.2)
		soft_box.material = soft
		halo.mesh = soft_box
		halo.position = Vector3(mid.x, PATH_Y - 0.01, mid.y)
		halo.rotation.y = yaw
		parent.add_child(halo)
		placed += 1
		t += seg + PATH_GAP
	return placed


func _place_path_omnis(parent: Node3D) -> void:
	"""Sparse warm omnis along the corridor for Compatibility renderer."""
	for x in [6.0, 12.0, 18.0, 24.0]:
		var light := OmniLight3D.new()
		light.name = "PathOmni_%.0f" % x
		light.position = Vector3(x, 1.2, 0.0)
		light.light_color = Color(1.0, 0.55, 0.15)
		light.light_energy = 0.35
		light.omni_range = 4.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		parent.add_child(light)


func _place_floor_pads() -> int:
	"""Drop a few Kenney floor-large pads on the concrete ground."""
	var path := ASSET_DIR + FLOOR_ASSET
	if not ResourceLoader.exists(path):
		push_warning("[MW] workshop floor missing %s" % path)
		return 0
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return 0
	var count := 0
	for item in FLOOR_PADS:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var node := packed.instantiate() as Node3D
		if node == null:
			return count
		node.name = "FloorPad_%d" % count
		node.position = Vector3(float(d.get("x", 0.0)), FLOOR_Y, float(d.get("z", 0.0)))
		add_child(node)
		count += 1
	return count


func _spawn_asset(asset_name: String, x: float, z: float, yaw_deg: float, s: float, idx: int) -> bool:
	"""Instance one dress prop at Godot (x,0,z)."""
	var path := ASSET_DIR + asset_name
	if not ResourceLoader.exists(path):
		push_warning("[MW] workshop dress missing %s" % path)
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("[MW] workshop dress failed load %s" % path)
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	node.name = "Dress_%d_%s" % [idx, asset_name.get_basename()]
	var yaw_rad := deg_to_rad(yaw_deg)
	node.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, yaw_rad, 0.0)).scaled(Vector3(s, s, s)),
		Vector3(x, 0.0, z)
	)
	add_child(node)
	return true
