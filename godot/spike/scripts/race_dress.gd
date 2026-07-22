## Viewer dress for demo_race — loads res://data/race_layout.json (gen_demo_race_track.py).
## Physics walls are MuJoCo; hills are cosmetic only (planar DiffBot).
extends Node3D

const LAYOUT_PATH := "res://data/race_layout.json"


func _ready() -> void:
	"""Build asphalt ribbon, barriers, checkpoints, finish from layout."""
	var layout := _load_layout()
	if layout.is_empty():
		push_warning("[MW] race dress: missing %s" % LAYOUT_PATH)
		return
	_add_ground(layout)
	_add_height_ribbons(layout)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.32, 0.36, 0.42)
	wall_mat.roughness = 0.82
	var walls: Array = layout.get("walls", [])
	for w in walls:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var pose: Variant = w.get("pose", {})
		var size: Variant = w.get("size", [])
		if typeof(pose) != TYPE_DICTIONARY or typeof(size) != TYPE_ARRAY or size.size() < 3:
			continue
		var yaw := float(pose.get("yaw", 0.0))
		var mx := float(pose.get("x", 0.0))
		var my := float(pose.get("y", 0.0))
		var mz := float(pose.get("z", 0.75))
		var sx := float(size[0])
		var sy := float(size[1])
		var sz := float(size[2])
		_add_box(
			str(w.get("id", "wall")),
			Vector3(mx, mz, -my),
			Vector3(sx, sz, sy),
			wall_mat,
			yaw
		)
	_add_triggers(layout)
	print(
		"[MW] race dress walls=%d lap≈%sm"
		% [walls.size(), layout.get("lap_m", "?")]
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


func _add_ground(layout: Dictionary) -> void:
	"""Large dark pad covering the circuit bounds."""
	var mi := MeshInstance3D.new()
	mi.name = "Asphalt"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240, 160)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.12, 0.14)
	mat.roughness = 0.96
	mesh.material = mat
	mi.mesh = mesh
	mi.position = Vector3(0, 0.005, 0)
	add_child(mi)


func _add_height_ribbons(layout: Dictionary) -> void:
	"""Cosmetic undulating road strip along centerline (viewer_only)."""
	var heights: Array = layout.get("viewer_heights", [])
	if heights.size() < 3:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.19, 0.22)
	mat.roughness = 0.9
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
			Vector3(length + 0.2, maxf(mh, 0.15), 9.5),
			mat,
			yaw
		)


func _add_triggers(layout: Dictionary) -> void:
	"""Translucent CP / finish volumes."""
	var finish_mat := StandardMaterial3D.new()
	finish_mat.albedo_color = Color(0.2, 0.9, 0.4, 0.35)
	finish_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cp_mat := StandardMaterial3D.new()
	cp_mat.albedo_color = Color(0.95, 0.75, 0.2, 0.3)
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
		_add_box(tid, Vector3(cx, 1.0, -cy), Vector3(sx, 2.0, sy), mat, 0.0)


func _add_box(node_name: String, pos: Vector3, size: Vector3, mat: Material, yaw_mw: float) -> void:
	"""One viewer-only box; yaw_mw is MW yaw about Z → Godot Y."""
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw_mw
	add_child(mi)
