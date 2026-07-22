## Viewer dress for demo_race — Kenney Racing Kit fences replace orange box walls.
## Physics walls stay MuJoCo boxes; hills / asphalt remain procedural.
extends Node3D

const LAYOUT_PATH := "res://data/race_layout.json"
const ASSET_DIR := "res://assets/kenney_racing/"
## fenceStraight native ~1×0.5×0.03; scale ≈3 → ~3 m long × 1.5 m tall.
const FENCE_SCALE := 3.0
const FENCE_NATIVE_LEN := 1.0
## Low jersey curb in front of fence (barrierWall native 1×0.13).
const CURB_SCALE := Vector3(1.0, 2.2, 2.2)
const CURB_NATIVE_LEN := 1.0


func _ready() -> void:
	"""Build asphalt, ribbons, Kenney fences, finish flags, sparse trees."""
	var layout := _load_layout()
	if layout.is_empty():
		push_warning("[MW] race dress: missing %s" % LAYOUT_PATH)
		return
	_add_ground(layout)
	_add_height_ribbons(layout)
	_add_centerline(layout)
	var walls: Array = layout.get("walls", [])
	var fence_n := 0
	for w in walls:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		fence_n += _add_wall_fences(w)
	_add_triggers(layout)
	_add_finish_flags(layout)
	_add_trees(layout)
	print(
		"[MW] race dress walls=%d fence_pieces=%d lap≈%sm"
		% [walls.size(), fence_n, layout.get("lap_m", "?")]
	)


func _load_layout() -> Dictionary:
	"""Parse packed race layout JSON."""
	if not FileAccess.file_exists(LAYOUT_PATH):
		return {}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _layout_bounds(layout: Dictionary) -> Rect2:
	"""Axis-aligned bounds of walls in MW XY."""
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for w in layout.get("walls", []):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var pose: Variant = w.get("pose", {})
		if typeof(pose) != TYPE_DICTIONARY:
			continue
		var x := float(pose.get("x", 0.0))
		var y := float(pose.get("y", 0.0))
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
	if min_x > max_x:
		return Rect2(-50, -40, 100, 80)
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _add_ground(layout: Dictionary) -> void:
	"""Bright pad covering the circuit with margin."""
	var b := _layout_bounds(layout)
	var margin := 18.0
	var mi := MeshInstance3D.new()
	mi.name = "Asphalt"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(b.size.x + margin * 2.0, b.size.y + margin * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.27)
	mat.roughness = 0.95
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(b.position.x + b.size.x * 0.5, 0.002, -(b.position.y + b.size.y * 0.5))
	add_child(mi)


func _add_height_ribbons(layout: Dictionary) -> void:
	"""Cosmetic undulating road strip (viewer_only; DiffBot stays planar)."""
	var heights: Array = layout.get("viewer_heights", [])
	if heights.size() < 3:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.2)
	mat.roughness = 0.92
	var n := heights.size()
	for i in range(n):
		var a: Dictionary = heights[i]
		var b: Dictionary = heights[(i + 1) % n]
		var ax := float(a.get("x", 0.0))
		var ay := float(a.get("y", 0.0))
		var ah := float(a.get("h", 0.4))
		var bx := float(b.get("x", 0.0))
		var by := float(b.get("y", 0.0))
		var bh := float(b.get("h", 0.4))
		var mx := 0.5 * (ax + bx)
		var my := 0.5 * (ay + by)
		var mh := 0.5 * (ah + bh)
		var dx := bx - ax
		var dy := by - ay
		var length := Vector2(dx, dy).length()
		if length < 0.3:
			continue
		var yaw := atan2(dy, dx)
		_add_box(
			"ribbon_%d" % i,
			Vector3(mx, mh * 0.5, -my),
			Vector3(length + 0.25, maxf(mh, 0.2), 8.5),
			mat,
			yaw
		)


func _add_centerline(layout: Dictionary) -> void:
	"""Dashed white lane marks along centerline samples."""
	var heights: Array = layout.get("viewer_heights", [])
	if heights.size() < 4:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.93, 0.95)
	mat.roughness = 0.85
	var n := heights.size()
	for i in range(0, n, 2):
		var a: Dictionary = heights[i]
		var b: Dictionary = heights[(i + 1) % n]
		var ax := float(a.get("x", 0.0))
		var ay := float(a.get("y", 0.0))
		var bx := float(b.get("x", 0.0))
		var by := float(b.get("y", 0.0))
		var mx := 0.5 * (ax + bx)
		var my := 0.5 * (ay + by)
		var dx := bx - ax
		var dy := by - ay
		var length := Vector2(dx, dy).length()
		if length < 0.2:
			continue
		var yaw := atan2(dy, dx)
		_add_box(
			"stripe_%d" % i,
			Vector3(mx, 0.04, -my),
			Vector3(length * 0.55, 0.05, 0.35),
			mat,
			yaw
		)


func _add_wall_fences(w: Dictionary) -> int:
	"""Tile Kenney fenceStraight (+ jersey curb) along one MuJoCo wall segment."""
	var pose: Variant = w.get("pose", {})
	var size: Variant = w.get("size", [])
	if typeof(pose) != TYPE_DICTIONARY or typeof(size) != TYPE_ARRAY or size.size() < 3:
		return 0
	var yaw := float(pose.get("yaw", 0.0))
	var mx := float(pose.get("x", 0.0))
	var my := float(pose.get("y", 0.0))
	var length := float(size[0])
	if length < 0.4:
		return 0
	var wid := str(w.get("id", "wall"))
	var outer := wid.find("wall_out") >= 0
	var piece_len := FENCE_NATIVE_LEN * FENCE_SCALE
	var n := maxi(1, int(round(length / piece_len)))
	var actual := length / float(n)
	var sx := actual / FENCE_NATIVE_LEN
	var tx := cos(yaw)
	var ty := sin(yaw)
	var placed := 0
	for i in range(n):
		var along := (float(i) + 0.5) * actual - length * 0.5
		var px := mx + tx * along
		var py := my + ty * along
		# Fence mesh +X = length; pivot at piece start — offset half-length along tangent.
		var fx := px - tx * (actual * 0.5)
		var fy := py - ty * (actual * 0.5)
		if _spawn_asset(
			"fenceStraight.glb",
			"%s_f%d" % [wid, i],
			Vector3(fx, 0.0, -fy),
			yaw,
			Vector3(sx, FENCE_SCALE, FENCE_SCALE)
		):
			placed += 1
		# Low curb: red outside / white inside.
		var curb := "barrierRed.glb" if outer else "barrierWhite.glb"
		var csx := actual / CURB_NATIVE_LEN
		var cx0 := px - tx * (actual * 0.5)
		var cy0 := py - ty * (actual * 0.5)
		_spawn_asset(
			curb,
			"%s_c%d" % [wid, i],
			Vector3(cx0, 0.0, -cy0),
			yaw,
			Vector3(csx, CURB_SCALE.y, CURB_SCALE.z)
		)
	return placed


func _add_triggers(layout: Dictionary) -> void:
	"""Faint CP / finish volumes (authority AABB still invisible to physics)."""
	var finish_mat := StandardMaterial3D.new()
	finish_mat.albedo_color = Color(0.15, 0.95, 0.4, 0.12)
	finish_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cp_mat := StandardMaterial3D.new()
	cp_mat.albedo_color = Color(0.95, 0.8, 0.15, 0.1)
	cp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for t in layout.get("triggers", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		var mn: Variant = t.get("min", [])
		var mx: Variant = t.get("max", [])
		if typeof(mn) != TYPE_ARRAY or typeof(mx) != TYPE_ARRAY or mn.size() < 2 or mx.size() < 2:
			continue
		var cx := 0.5 * (float(mn[0]) + float(mx[0]))
		var cy := 0.5 * (float(mn[1]) + float(mx[1]))
		var sx := absf(float(mx[0]) - float(mn[0]))
		var sy := absf(float(mx[1]) - float(mn[1]))
		var tid := str(t.get("id", "trig"))
		var mat := finish_mat if tid.find("finish") >= 0 else cp_mat
		_add_box(tid, Vector3(cx, 0.9, -cy), Vector3(sx, 1.6, sy), mat, 0.0)


func _add_finish_flags(layout: Dictionary) -> void:
	"""Checker flags at finish gate."""
	for t in layout.get("triggers", []):
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if str(t.get("id", "")).find("finish") < 0:
			continue
		var mn: Variant = t.get("min", [])
		var mx: Variant = t.get("max", [])
		if typeof(mn) != TYPE_ARRAY or typeof(mx) != TYPE_ARRAY or mn.size() < 2:
			continue
		var cx := 0.5 * (float(mn[0]) + float(mx[0]))
		var cy := 0.5 * (float(mn[1]) + float(mx[1]))
		_spawn_asset(
			"flagCheckers.glb",
			"finish_flag_l",
			Vector3(cx - 4.0, 0.0, -cy),
			0.0,
			Vector3(4.0, 4.0, 4.0)
		)
		_spawn_asset(
			"flagCheckers.glb",
			"finish_flag_r",
			Vector3(cx + 4.0, 0.0, -cy),
			PI,
			Vector3(4.0, 4.0, 4.0)
		)
		return


func _add_trees(layout: Dictionary) -> void:
	"""Sparse trees outside the outer wall ring."""
	var b := _layout_bounds(layout)
	var cx := b.position.x + b.size.x * 0.5
	var cy := b.position.y + b.size.y * 0.5
	var rx := b.size.x * 0.5 + 10.0
	var ry := b.size.y * 0.5 + 10.0
	var n := 14
	for i in range(n):
		var ang := TAU * float(i) / float(n) + 0.35
		var px := cx + cos(ang) * rx
		var py := cy + sin(ang) * ry
		var asset := "treeLarge.glb" if i % 3 == 0 else "treeSmall.glb"
		var s := 3.5 if asset == "treeLarge.glb" else 3.0
		_spawn_asset(asset, "tree_%d" % i, Vector3(px, 0.0, -py), ang, Vector3(s, s, s))


func _spawn_asset(
	asset_name: String,
	node_name: String,
	pos: Vector3,
	yaw_mw: float,
	scale: Vector3
) -> bool:
	"""Instance one Kenney glb; returns false if missing."""
	var path := ASSET_DIR + asset_name
	if not ResourceLoader.exists(path):
		push_warning("[MW] race dress missing %s" % path)
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return false
	inst.name = node_name
	inst.position = pos
	inst.rotation.y = yaw_mw
	inst.scale = scale
	add_child(inst)
	return true


func _add_box(node_name: String, pos: Vector3, size: Vector3, mat: Material, yaw_mw: float) -> void:
	"""Procedural box helper (asphalt ribbons / faint triggers)."""
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw_mw
	add_child(mi)
