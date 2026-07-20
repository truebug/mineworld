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
const FLOOR_PADS: Array = [
	{"x": 8.0, "z": 0.0}, {"x": 12.0, "z": 0.0}, {"x": 16.0, "z": 0.0}, {"x": 20.0, "z": 0.0},
	{"x": 8.0, "z": 4.0}, {"x": 12.0, "z": -4.0}, {"x": 18.0, "z": 4.0}, {"x": 22.0, "z": -4.0},
	{"x": 26.0, "z": 0.0}, {"x": 26.0, "z": 4.0}, {"x": 26.0, "z": -4.0},
]


func _place_all() -> void:
	"""Place floor pads + props; keep concrete Ground as base (viewer_only)."""
	var floor_n := _place_floor_pads()
	var n := 0
	for item in PLACEMENTS:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var name := str(d.get("asset", ""))
		if _spawn_asset(name, float(d.get("x", 0.0)), float(d.get("z", 0.0)), float(d.get("yaw", 0.0)), float(d.get("s", 1.0)), n):
			n += 1
	print("[MW] workshop dress floor_pads=%d props=%d (viewer_only)" % [floor_n, n])


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
