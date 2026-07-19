## Runtime city-block dress for demo_city.
## Loads block_layout.json (from scripts/gen_demo_city_block.py), instances
## KayKit buildings + roads as viewer_only, hides brown Authority wall meshes
## (MuJoCo air walls come from the contract footprints), and places the
## green finish zone + ground plane from the same layout.
## On Web, prefers live GET /api/city-block/layout so D9 regen needs no re-export.
extends Node3D

const LAYOUT_PATH := "res://assets/kaykit_city/block_layout.json"
const ASSET_DIR := "res://assets/kaykit_city/"
const LAYOUT_API := "/api/city-block/layout"


func _ready() -> void:
	"""Apply layout after the scene tree is ready."""
	call_deferred("_begin_layout")


func _begin_layout() -> void:
	"""Web: fetch live layout; desktop: read packed JSON."""
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
		if origin == "":
			_apply_from_file()
			return
		var http := HTTPRequest.new()
		http.name = "LayoutHttp"
		add_child(http)
		http.request_completed.connect(_on_layout_http.bind(http))
		var err := http.request(origin + LAYOUT_API)
		if err != OK:
			push_warning("[MW] layout HTTP request failed err=%s" % err)
			http.queue_free()
			_apply_from_file()
		return
	_apply_from_file()


func _on_layout_http(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	"""Parse API layout JSON, fall back to packed file on failure."""
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[MW] layout API %s/%s — using packed file" % [result, response_code])
		_apply_from_file()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[MW] bad layout API JSON")
		_apply_from_file()
		return
	_apply_data(data)


func _apply_from_file() -> void:
	"""Load layout from res:// block_layout.json."""
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("[MW] missing %s — run scripts/gen_demo_city_block.py" % LAYOUT_PATH)
		return
	var raw := FileAccess.get_file_as_string(LAYOUT_PATH)
	var data = JSON.parse_string(raw)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[MW] bad block_layout.json")
		return
	_apply_data(data)


func _apply_data(data: Dictionary) -> void:
	"""Rebuild Decor from a layout dict."""
	_hide_authority_walls()
	_place_buildings(data)
	_place_props(data)
	_place_roads(data)
	_place_markers(data)
	print(
		"[MW] city block dress seed=%s buildings=%d props=%d roads=%d"
		% [
			data.get("seed", "?"),
			(data.get("buildings", []) as Array).size(),
			(data.get("props", []) as Array).size(),
			(data.get("roads", []) as Array).size(),
		]
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
	var city := _ensure_group("City")
	_clear_children(city)
	for entry in data.get("buildings", []):
		_instance_asset(city, entry)


func _place_props(data: Dictionary) -> void:
	"""Instance sidewalk KayKit props (lights, benches, bushes)."""
	var props := _ensure_group("Props")
	_clear_children(props)
	for entry in data.get("props", []):
		_instance_asset(props, entry)


func _place_roads(data: Dictionary) -> void:
	"""Lay plain asphalt strips on street corridors (viewer_only)."""
	var roads := _ensure_group("Roads")
	_clear_children(roads)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.25, 1.0)
	mat.roughness = 0.92
	for entry in data.get("roads", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("kind", "strip")) != "strip":
			continue
		var mi := MeshInstance3D.new()
		mi.name = str(entry.get("id", "road"))
		var pm := PlaneMesh.new()
		pm.size = Vector2(float(entry.get("sx", 4.0)), float(entry.get("sy", 4.0)))
		pm.material = mat
		mi.mesh = pm
		# Slightly above ground to avoid z-fight; MW→Godot.
		mi.position = Vector3(
			float(entry.get("x", 0.0)),
			0.02,
			-float(entry.get("y", 0.0)),
		)
		roads.add_child(mi)


func _ensure_group(group_name: String) -> Node3D:
	"""Return or create a named child Node3D."""
	var node := get_node_or_null(group_name) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = group_name
		add_child(node)
	return node


func _clear_children(parent: Node3D) -> void:
	"""Queue-free all children of parent."""
	for child in parent.get_children():
		child.queue_free()


func _instance_asset(parent: Node3D, entry: Variant) -> void:
	"""Instance one KayKit gltf entry under parent."""
	if typeof(entry) != TYPE_DICTIONARY:
		return
	var asset := str(entry.get("asset", ""))
	if asset == "":
		return
	var path := ASSET_DIR + asset
	if not ResourceLoader.exists(path):
		push_warning("[MW] missing asset %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	node.name = str(entry.get("id", "asset"))
	var scale_v := float(entry.get("scale", 2.0))
	var yaw := float(entry.get("yaw", 0.0))
	# MW (x,y) → Godot (x, 0, -y); yaw around Godot Y.
	var gx := float(entry.get("x", 0.0))
	var gy := float(entry.get("y", 0.0))
	node.position = Vector3(gx, 0.0, -gy)
	node.rotation = Vector3(0.0, yaw, 0.0)
	node.scale = Vector3(scale_v, scale_v, scale_v)
	parent.add_child(node)


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
			var col: Variant = ground_info.get("color", null)
			if typeof(col) == TYPE_ARRAY and (col as Array).size() >= 3:
				var arr := col as Array
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(
					float(arr[0]),
					float(arr[1]),
					float(arr[2]),
					float(arr[3]) if arr.size() > 3 else 1.0,
				)
				mat.roughness = 0.95
				pm.material = mat
