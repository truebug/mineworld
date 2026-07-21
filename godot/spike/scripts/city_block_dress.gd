## Runtime city-block dress for demo_city.
## MuJoCo static_obstacles match KayKit lots. KayKit ON by default.
## Footprint boxes only with ?walls=1 (or opaque boxes when ?kaykit=0).
## Hides scene Authority greybox. Web: GET /api/city-block/layout (D9).
extends Node3D

const LAYOUT_PATH := "res://assets/kaykit_city/block_layout.json"
const ASSET_DIR := "res://assets/kaykit_city/"
const LAYOUT_API := "/api/city-block/layout"
## KayKit building glTF native XY ≈ 2 m (see gen_demo_city_block.MESH_XY).
const MESH_XY := 2.0


func _ready() -> void:
	"""Hide greybox immediately; apply packed layout; Web may refresh via API."""
	_hide_authority_walls()
	call_deferred("_begin_layout")


func _begin_layout() -> void:
	"""Always apply packed layout first (so Web never sticks on old Authority)."""
	_apply_from_file()
	if not OS.has_feature("web"):
		return
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	if origin == "":
		return
	var http := HTTPRequest.new()
	http.name = "LayoutHttp"
	add_child(http)
	http.request_completed.connect(_on_layout_http.bind(http))
	var err := http.request(origin + LAYOUT_API)
	if err != OK:
		push_warning("[MW] layout HTTP request failed err=%s (using packed)" % err)
		http.queue_free()


func _on_layout_http(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	"""Refresh dress from live API when available (D9 regen)."""
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_warning("[MW] layout API %s/%s — keep packed layout" % [result, response_code])
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("[MW] bad layout API JSON — keep packed layout")
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
	"""Rebuild Decor: KayKit by default; footprint boxes only with ?walls=1."""
	_hide_authority_walls()
	var kaykit := _want_kaykit()
	var show_walls := _want_walls_debug()
	if show_walls or not kaykit:
		# Opaque boxes when KayKit off (visual=physics); translucent debug if walls=1.
		_place_footprint_buildings(data, show_walls and kaykit)
	else:
		_clear_group("City")
	if kaykit:
		_place_kaykit_buildings(data)
		_place_props(data)
	else:
		_clear_group("KayKit")
		_clear_group("Props")
	_place_roads(data)
	_place_markers(data)
	print(
		"[MW] city dress seed=%s kaykit=%s walls=%s roads=%d"
		% [
			data.get("seed", "?"),
			"on" if kaykit else "off",
			"on" if show_walls else "off",
			(data.get("roads", []) as Array).size(),
		]
	)


func _want_walls_debug() -> bool:
	"""Footprint overlay; default OFF. Enable with ?walls=1."""
	return _web_flag("walls", false)


func _want_kaykit() -> bool:
	"""KayKit glTF skin; default ON. Hide with ?kaykit=0."""
	return _web_flag("kaykit", true)


func _web_flag(param: String, default_on: bool) -> bool:
	"""Read ?param=0|1 or window.MINEWORLD_* ; default_on when unset."""
	var def := "1" if default_on else "0"
	if not OS.has_feature("web"):
		for a in OS.get_cmdline_user_args():
			var s := str(a)
			if s == ("%s=0" % param) or s == ("--%s=0" % param):
				return false
			if s == ("%s=1" % param) or s == ("--%s=1" % param):
				return true
		return default_on
	var win_key := "MINEWORLD_SHOW_KAYKIT" if param == "kaykit" else "MINEWORLD_SHOW_WALLS"
	var flag := str(
		JavaScriptBridge.eval(
			(
				"(function(){try{var q=new URLSearchParams(location.search).get('%s');"
				+ "if(q==='0'||q==='false')return '0';"
				+ "if(q==='1'||q==='true')return '1';"
				+ "var w=window.%s;if(w===false||w==='0')return '0';"
				+ "if(w===true||w==='1')return '1';"
				+ "return '%s';}catch(e){return '%s'}})()"
			)
			% [param, win_key, def, def],
			true,
		)
	).strip_edges()
	return flag != "0"


func _hide_authority_walls() -> void:
	"""Hide baked greybox Authority meshes (except FinishZone)."""
	var authority := get_node_or_null("../Authority") as Node3D
	if authority == null:
		return
	for child in authority.get_children():
		if child.name == "FinishZone":
			continue
		child.visible = false
		if child is VisualInstance3D:
			(child as VisualInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _obstacle_list(data: Dictionary) -> Array:
	"""MuJoCo obstacles from layout, or synthesize from building footprints."""
	var obstacles: Array = data.get("obstacles", []) as Array
	if not obstacles.is_empty():
		return obstacles
	var out: Array = []
	for entry in data.get("buildings", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var fp: Variant = entry.get("footprint", [5.08, 5.08])
		var sx := 5.08
		var sy := 5.08
		if typeof(fp) == TYPE_ARRAY and (fp as Array).size() >= 2:
			sx = float((fp as Array)[0])
			sy = float((fp as Array)[1])
		out.append(
			{
				"id": str(entry.get("id", "bldg")),
				"size": [sx, sy, 3.5],
				"pose": {
					"x": float(entry.get("x", 0.0)),
					"y": float(entry.get("y", 0.0)),
					"z": 1.75,
					"yaw": 0.0,
				},
			}
		)
	return out


func _place_footprint_buildings(data: Dictionary, translucent: bool = false) -> void:
	"""Boxes = exact MuJoCo static_obstacles. Translucent when KayKit skin on."""
	var city := _ensure_group("City")
	_clear_children(city)
	var mat_bldg := StandardMaterial3D.new()
	if translucent:
		mat_bldg.albedo_color = Color(0.55, 0.5, 0.45, 0.32)
		mat_bldg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat_bldg.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		mat_bldg.albedo_color = Color(0.52, 0.48, 0.44, 1.0)
	mat_bldg.roughness = 0.88
	var mat_curb := StandardMaterial3D.new()
	mat_curb.albedo_color = Color(0.35, 0.38, 0.42, 1.0)
	mat_curb.roughness = 0.9
	for entry in _obstacle_list(data):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var size: Variant = entry.get("size", [])
		var pose: Variant = entry.get("pose", {})
		if typeof(size) != TYPE_ARRAY or (size as Array).size() < 3:
			continue
		if typeof(pose) != TYPE_DICTIONARY:
			continue
		var oid := str(entry.get("id", "wall"))
		var sx := float((size as Array)[0])
		var sy := float((size as Array)[1])
		var sz := float((size as Array)[2])
		var px := float((pose as Dictionary).get("x", 0.0))
		var py := float((pose as Dictionary).get("y", 0.0))
		var pz := float((pose as Dictionary).get("z", sz * 0.5))
		var yaw := float((pose as Dictionary).get("yaw", 0.0))
		var mi := MeshInstance3D.new()
		mi.name = oid
		var box := BoxMesh.new()
		# MW [sx,sy,sz] → Godot (x, y-up=z, depth=-y) → (sx, sz, sy).
		box.size = Vector3(sx, sz, sy)
		box.material = mat_curb if oid.begins_with("boundary_") else mat_bldg
		mi.mesh = box
		mi.position = Vector3(px, pz, -py)
		mi.rotation = Vector3(0.0, yaw, 0.0)
		city.add_child(mi)


func _place_kaykit_buildings(data: Dictionary) -> void:
	"""KayKit meshes stretched to fill MuJoCo footprints (visual ≈ physics)."""
	var kay := _ensure_group("KayKit")
	_clear_children(kay)
	for entry in data.get("buildings", []):
		_instance_asset(kay, entry, true)


func _place_props(data: Dictionary) -> void:
	"""Instance sidewalk KayKit props (lights, benches, bushes)."""
	var props := _ensure_group("Props")
	_clear_children(props)
	for entry in data.get("props", []):
		_instance_asset(props, entry, false)


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


func _clear_group(group_name: String) -> void:
	"""Clear children of a named group if it exists."""
	var node := get_node_or_null(group_name) as Node3D
	if node != null:
		_clear_children(node)


func _clear_children(parent: Node3D) -> void:
	"""Queue-free all children of parent."""
	for child in parent.get_children():
		child.queue_free()


func _instance_asset(parent: Node3D, entry: Variant, fill_footprint: bool = false) -> void:
	"""Instance one KayKit gltf; buildings stretch XZ to footprint when fill_footprint."""
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
	var sx_s := scale_v
	var sy_s := scale_v
	var sz_s := scale_v
	if fill_footprint:
		var sc := _building_scale_xz(entry)
		sx_s = sc.x
		sy_s = sc.y
		sz_s = sc.z
	var yaw := float(entry.get("yaw", 0.0))
	var gx := float(entry.get("x", 0.0))
	var gy := float(entry.get("y", 0.0))
	node.position = Vector3(gx, 0.0, -gy)
	node.rotation = Vector3(0.0, yaw, 0.0)
	node.scale = Vector3(sx_s, sy_s, sz_s)
	parent.add_child(node)


func _building_scale_xz(entry: Dictionary) -> Vector3:
	"""Godot (sx, height, sz) so mesh fills MW footprint [sx,sy] under local yaw."""
	var fpx := MESH_XY
	var fpy := MESH_XY
	var fp: Variant = entry.get("footprint", null)
	if typeof(fp) == TYPE_ARRAY and (fp as Array).size() >= 2:
		fpx = float((fp as Array)[0])
		fpy = float((fp as Array)[1])
	elif entry.has("scale_x") and entry.has("scale_z"):
		return Vector3(
			float(entry.get("scale_x")),
			float(entry.get("scale", minf(float(entry.get("scale_x")), float(entry.get("scale_z"))))),
			float(entry.get("scale_z")),
		)
	var sx_s := fpx / MESH_XY
	var sz_s := fpy / MESH_XY
	# Local scale then yaw: ±90° swaps world X/Z — pre-swap so AABB stays footprint.
	var ynorm := fposmod(float(entry.get("yaw", 0.0)), TAU)
	var swap := (ynorm > PI * 0.25 and ynorm < PI * 0.75) or (
		ynorm > PI * 1.25 and ynorm < PI * 1.75
	)
	if swap:
		var tmp := sx_s
		sx_s = sz_s
		sz_s = tmp
	var h := minf(sx_s, sz_s)
	return Vector3(sx_s, h, sz_s)


func _place_markers(data: Dictionary) -> void:
	"""Move finish zone, optional flag, and ground to match generated bounds."""
	var fin: Variant = data.get("finish", {})
	if typeof(fin) == TYPE_DICTIONARY:
		var fx := float(fin.get("x", 0.0))
		var fy := float(fin.get("y", 0.0))
		var zone := get_node_or_null("../Authority/FinishZone") as Node3D
		if zone != null:
			zone.position = Vector3(fx, 1.0, -fy)
			zone.visible = true
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
