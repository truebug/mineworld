## Runtime city-block dress for demo_city.
## Loads block_layout.json (from scripts/gen_demo_city_block.py), instances
## KayKit buildings as viewer_only, hides brown Authority wall meshes
## (MuJoCo air walls come from the contract footprints), and places the
## green finish zone + ground plane from the same layout.
extends Node3D

const LAYOUT_PATH := "res://assets/kaykit_city/block_layout.json"
const ASSET_DIR := "res://assets/kaykit_city/"


func _ready() -> void:
	"""Apply layout after the scene tree is ready."""
	call_deferred("_apply_layout")


func _apply_layout() -> void:
	"""Load JSON layout and rebuild Decor + markers."""
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("[MW] missing %s — run scripts/gen_demo_city_block.py" % LAYOUT_PATH)
		return
	var raw := FileAccess.get_file_as_string(LAYOUT_PATH)
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[MW] bad block_layout.json")
		return
	_hide_authority_walls()
	_place_buildings(data)
	_place_markers(data)
	print(
		"[MW] city block dress seed=%s buildings=%d"
		% [data.get("seed", "?"), (data.get("buildings", []) as Array).size()]
	)


func _hide_authority_walls() -> void:
	"""Air walls: keep FinishZone visible, hide all other Authority meshes."""
	var authority := get_node_or_null("../Authority") as Node3D
	if authority == null:
		return
	for child in authority.get_children():
		if child.name == "FinishZone":
			continue
		if child is VisualInstance3D:
			(child as VisualInstance3D).visible = false


func _place_buildings(data: Dictionary) -> void:
	"""Clear City children and instance KayKit buildings from layout."""
	var city := get_node_or_null("City") as Node3D
	if city == null:
		city = Node3D.new()
		city.name = "City"
		add_child(city)
	for child in city.get_children():
		child.queue_free()
	for entry in data.get("buildings", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var asset := str(entry.get("asset", ""))
		if asset == "":
			continue
		var path := ASSET_DIR + asset
		if not ResourceLoader.exists(path):
			push_warning("[MW] missing asset %s" % path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var node := packed.instantiate() as Node3D
		node.name = str(entry.get("id", "bldg"))
		var scale_v := float(entry.get("scale", 2.0))
		var yaw := float(entry.get("yaw", 0.0))
		# MW (x,y) → Godot (x, 0, -y); yaw around Godot Y.
		var gx := float(entry.get("x", 0.0))
		var gy := float(entry.get("y", 0.0))
		node.position = Vector3(gx, 0.0, -gy)
		node.rotation = Vector3(0.0, yaw, 0.0)
		node.scale = Vector3(scale_v, scale_v, scale_v)
		city.add_child(node)


func _place_markers(data: Dictionary) -> void:
	"""Move finish zone, optional flag, and ground to match generated bounds."""
	var fin: Variant = data.get("finish", {})
	if typeof(fin) == TYPE_DICTIONARY:
		var fx := float(fin.get("x", 0.0))
		var fy := float(fin.get("y", 0.0))
		var zone := get_node_or_null("../Authority/FinishZone") as Node3D
		if zone != null:
			zone.position = Vector3(fx, 1.0, -fy)
		var flag := get_node_or_null("FinishFlag") as Node3D
		if flag != null:
			flag.position = Vector3(fx + 0.3, 0.5, -fy - 0.4)
	var ground_info: Variant = data.get("ground", {})
	if typeof(ground_info) == TYPE_DICTIONARY:
		var ground := get_node_or_null("../Ground") as MeshInstance3D
		if ground != null and ground.mesh is PlaneMesh:
			var pm := ground.mesh as PlaneMesh
			pm.size = Vector2(float(ground_info.get("sx", 40.0)), float(ground_info.get("sy", 40.0)))
			ground.position = Vector3(
				float(ground_info.get("cx", 0.0)),
				0.0,
				-float(ground_info.get("cy", 0.0)),
			)
