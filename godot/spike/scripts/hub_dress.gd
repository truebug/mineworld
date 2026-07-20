## Viewer-only hub hall dress: solid enclosed hangar (docs/18).
## Procedural shell first (always visible); sparse Kenney props as accents.
extends Node3D

const ASSET_DIR := "res://assets/kenney_factory/"
const HALL_HALF_X := 20.0
const HALL_HALF_Z := 16.0
const CEILING_Y := 14.0
const WALL_T := 0.6
## Showcase mezzanine; H8 thin elevator ride (viewer Y offset in hub.gd).
const FLOOR2_Y := 5.2
const ELEV_X := 13.5
const ELEV_Z := 12.5


func _ready() -> void:
	"""Hide grey-box World meshes, then build a readable enclosed hall."""
	call_deferred("_build")


func _build() -> void:
	"""Solid floor/walls/ceiling + mild lights + a few props."""
	_hide_greybox()
	_setup_lights()
	var root := Node3D.new()
	root.name = "HangarDress"
	add_child(root)
	_place_solid_hall(root)
	_place_space_windows(root)
	_place_mezzanine(root)
	_place_props(root)
	_place_door_glows()
	print("[MW] hub dress: solid hangar %.0fx%.0f roof_y=%.1f + mezzanine + space sky" % [
		HALL_HALF_X * 2.0, HALL_HALF_Z * 2.0, CEILING_Y,
	])


func _setup_lights() -> void:
	"""Mild indoor lighting + deep-space sky outside the hall."""
	var env_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		var e: Environment = env_node.environment
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.5, 0.55, 0.65)
		e.ambient_light_energy = 0.5
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.tonemap_exposure = 0.95
		_apply_space_sky(e)
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.85, 0.9, 1.0)
		sun.light_energy = 0.45
		sun.shadow_enabled = false
	var fill := get_parent().get_node_or_null("Fill") as OmniLight3D
	if fill != null:
		fill.light_color = Color(0.75, 0.85, 1.0)
		fill.light_energy = 1.5
		fill.omni_range = 32.0
		fill.position = Vector3(0.0, 6.0, 0.0)


func _apply_space_sky(e: Environment) -> void:
	"""Install procedural starfield sky as the world backdrop."""
	var shader := load("res://shaders/hub_space_sky.gdshader") as Shader
	if shader == null:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.03, 0.08)
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var sky := Sky.new()
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_sky_contribution = 0.15


func _place_space_windows(root: Node3D) -> void:
	"""Glass ribbons above mid-wall + skylights so cosmos shows from inside."""
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.55, 0.85, 0.14)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.35
	glass.emission_enabled = true
	glass.emission = Color(0.12, 0.2, 0.4)
	glass.emission_energy_multiplier = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := _mat(Color(0.25, 0.3, 0.38), 0.6, 0.2)
	var hx := HALL_HALF_X
	var hz := HALL_HALF_Z
	var y := 9.5
	var h := 5.5
	var t := 0.1
	_box(root, "LintS", Vector3(0, CEILING_Y - 0.55, hz), Vector3(hx * 2.0, 0.5, WALL_T), frame)
	_box(root, "LintN", Vector3(0, CEILING_Y - 0.55, -hz), Vector3(hx * 2.0, 0.5, WALL_T), frame)
	_box(root, "WinS", Vector3(0, y, hz), Vector3(hx * 2.0 - 0.5, h, t), glass)
	_box(root, "WinNW", Vector3(-10, y, -hz), Vector3(14.0, h, t), glass)
	_box(root, "WinNE", Vector3(10, y, -hz), Vector3(14.0, h, t), glass)
	_box(root, "WinW", Vector3(-hx, y, 8), Vector3(t, h, 12.0), glass)
	_box(root, "WinE", Vector3(hx, y, 8), Vector3(t, h, 12.0), glass)
	var sky_glass := glass.duplicate() as StandardMaterial3D
	sky_glass.albedo_color = Color(0.2, 0.35, 0.65, 0.1)
	_box(root, "SkyL", Vector3(-7, CEILING_Y - 0.05, 0), Vector3(8.0, 0.06, 18.0), sky_glass)
	_box(root, "SkyR", Vector3(7, CEILING_Y - 0.05, 0), Vector3(8.0, 0.06, 18.0), sky_glass)


func _place_solid_hall(root: Node3D) -> void:
	"""One solid box room: floor, 4 walls with door gaps, ceiling rim + skylights."""
	var floor_mat := _mat(Color(0.42, 0.46, 0.52), 0.7, 0.08)
	var wall_low := _mat(Color(0.78, 0.82, 0.86), 0.65, 0.05)
	var wall_hi := _mat(Color(0.32, 0.55, 0.62), 0.7, 0.05)
	var ceil_mat := _mat(Color(0.35, 0.4, 0.48), 0.75, 0.1)
	# Floor
	_box(root, "Deck", Vector3(0, -0.06, 0), Vector3(HALL_HALF_X * 2.0, 0.12, HALL_HALF_Z * 2.0), floor_mat)
	# Floor cross (subtle, non-emissive)
	_box(root, "LaneX", Vector3(0, 0.01, 0), Vector3(1.0, 0.02, HALL_HALF_Z * 1.5), _mat(Color(0.3, 0.48, 0.78), 0.55, 0.0))
	_box(root, "LaneZ", Vector3(0, 0.01, 0), Vector3(HALL_HALF_X * 1.5, 0.02, 1.0), _mat(Color(0.78, 0.5, 0.28), 0.55, 0.0))
	# Walls: lower band + upper band (door gaps at E/W z≈0 and N x≈0)
	var split := 3.8
	_wall_ring(root, "WallLow", wall_low, 0.0, split)
	_wall_ring(root, "WallHi", wall_hi, split, 2.6)  ## ends ~6.4m; glass ribbon above to ceiling
	# Ceiling rim with two open skylight bays (stars visible looking up)
	var y_c := CEILING_Y
	var span_x := HALL_HALF_X * 2.0 + 1.0
	var span_z := HALL_HALF_Z * 2.0 + 1.0
	_box(root, "CeilN", Vector3(0, y_c, -hz_edge(span_z)), Vector3(span_x, 0.4, 4.0), ceil_mat)
	_box(root, "CeilS", Vector3(0, y_c, hz_edge(span_z)), Vector3(span_x, 0.4, 4.0), ceil_mat)
	_box(root, "CeilW", Vector3(-hx_edge(span_x), y_c, 0), Vector3(4.0, 0.4, span_z - 8.0), ceil_mat)
	_box(root, "CeilE", Vector3(hx_edge(span_x), y_c, 0), Vector3(4.0, 0.4, span_z - 8.0), ceil_mat)
	_box(root, "CeilMid", Vector3(0, y_c, 0), Vector3(3.0, 0.35, span_z - 8.0), ceil_mat)
	# Soft LED strips under ceiling beams
	var led := _mat(Color(0.85, 0.9, 1.0), 0.4, 0.0)
	led.emission_enabled = true
	led.emission = Color(0.7, 0.8, 1.0)
	led.emission_energy_multiplier = 0.85
	for sx in [-10.0, 0.0, 10.0]:
		_box(root, "Led", Vector3(sx, CEILING_Y - 0.35, 0), Vector3(0.9, 0.06, HALL_HALF_Z * 1.5), led)


func hx_edge(span_x: float) -> float:
	"""Half-span helper for ceiling rim X."""
	return span_x * 0.5 - 2.0


func hz_edge(span_z: float) -> float:
	"""Half-span helper for ceiling rim Z."""
	return span_z * 0.5 - 2.0


func _wall_ring(root: Node3D, prefix: String, mat: Material, y0: float, h: float) -> void:
	"""Perimeter walls with door bays; y0 = bottom, h = height."""
	var y_mid := y0 + h * 0.5
	var hx := HALL_HALF_X
	var hz := HALL_HALF_Z
	var t := WALL_T
	var door := 3.2
	# South full
	_box(root, prefix + "S", Vector3(0, y_mid, hz), Vector3(hx * 2.0 + t, h, t), mat)
	# North split around door
	var n_span := hx - door * 0.5
	_box(root, prefix + "NW", Vector3(-(hx + door) * 0.5, y_mid, -hz), Vector3(n_span, h, t), mat)
	_box(root, prefix + "NE", Vector3((hx + door) * 0.5, y_mid, -hz), Vector3(n_span, h, t), mat)
	# West / East split around doors
	var e_span := hz - door * 0.5
	_box(root, prefix + "WS", Vector3(-hx, y_mid, -(hz + door) * 0.5), Vector3(t, h, e_span), mat)
	_box(root, prefix + "WN", Vector3(-hx, y_mid, (hz + door) * 0.5), Vector3(t, h, e_span), mat)
	_box(root, prefix + "ES", Vector3(hx, y_mid, -(hz + door) * 0.5), Vector3(t, h, e_span), mat)
	_box(root, prefix + "EN", Vector3(hx, y_mid, (hz + door) * 0.5), Vector3(t, h, e_span), mat)


func _box(parent: Node3D, box_name: String, pos: Vector3, size: Vector3, mat: Material) -> void:
	"""Add a solid box mesh."""
	var mi := MeshInstance3D.new()
	mi.name = box_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func _mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	"""Simple opaque material."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _place_mezzanine(root: Node3D) -> void:
	"""Half-floor lounge + static elevator shaft (preview only)."""
	var deck := _mat(Color(0.38, 0.42, 0.48), 0.65, 0.12)
	var beam := _mat(Color(0.28, 0.32, 0.38), 0.7, 0.2)
	var rail := _mat(Color(0.55, 0.6, 0.68), 0.45, 0.35)
	var accent := _mat(Color(0.35, 0.55, 0.75), 0.5, 0.15)
	accent.emission_enabled = true
	accent.emission = Color(0.25, 0.45, 0.7)
	accent.emission_energy_multiplier = 0.6
	# South half deck (open edge faces −Z / hall center). Split around elevator shaft.
	var edge_z := 1.2
	var deck_z1 := edge_z
	var deck_z0 := HALL_HALF_Z - 0.7
	var deck_mid_z := (deck_z0 + deck_z1) * 0.5
	var deck_depth := deck_z0 - deck_z1
	var shaft_w := 3.4
	# Main slab west of elevator
	_box(
		root, "L2West",
		Vector3((ELEV_X - shaft_w * 0.5 - HALL_HALF_X) * 0.5 + 0.4, FLOOR2_Y, deck_mid_z),
		Vector3(ELEV_X - shaft_w * 0.5 + HALL_HALF_X - 0.8, 0.18, deck_depth),
		deck,
	)
	# Slab east of elevator (narrow strip to wall)
	var east_w := HALL_HALF_X - (ELEV_X + shaft_w * 0.5) - 0.5
	if east_w > 0.5:
		_box(
			root, "L2East",
			Vector3(ELEV_X + shaft_w * 0.5 + east_w * 0.5, FLOOR2_Y, deck_mid_z),
			Vector3(east_w, 0.18, deck_depth),
			deck,
		)
	# Slab south of elevator (between shaft and south wall)
	var south_d := deck_z0 - (ELEV_Z + shaft_w * 0.5)
	if south_d > 0.4:
		_box(
			root, "L2South",
			Vector3(ELEV_X, FLOOR2_Y, ELEV_Z + shaft_w * 0.5 + south_d * 0.5),
			Vector3(shaft_w + 0.2, 0.18, south_d),
			deck,
		)
	# Slab north of elevator (landing bridge toward open edge)
	var north_d := (ELEV_Z - shaft_w * 0.5) - deck_z1
	if north_d > 0.4:
		_box(
			root, "L2Landing",
			Vector3(ELEV_X, FLOOR2_Y, deck_z1 + north_d * 0.5),
			Vector3(shaft_w + 1.2, 0.18, north_d),
			deck,
		)
	# Open-edge beam + railing
	_box(root, "L2Beam", Vector3(0, FLOOR2_Y - 0.25, edge_z), Vector3(HALL_HALF_X * 2.0 - 1.0, 0.35, 0.35), beam)
	_box(root, "L2Rail", Vector3(0, FLOOR2_Y + 0.55, edge_z), Vector3(HALL_HALF_X * 2.0 - 1.5, 0.08, 0.08), rail)
	for x in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]:
		_box(root, "L2Post", Vector3(x, FLOOR2_Y + 0.28, edge_z), Vector3(0.08, 0.55, 0.08), rail)
	# Support columns under open edge
	for x in [-12.0, -4.0, 4.0, 12.0]:
		_box(root, "L2Col", Vector3(x, FLOOR2_Y * 0.5, edge_z + 0.4), Vector3(0.45, FLOOR2_Y, 0.45), beam)
	# Soft under-glow strip
	_box(root, "L2Led", Vector3(0, FLOOR2_Y - 0.12, edge_z + 0.2), Vector3(HALL_HALF_X * 1.6, 0.05, 0.12), accent)
	# Sparse upstairs lounge props
	_box(root, "L2Rug", Vector3(-6, FLOOR2_Y + 0.1, 8), Vector3(5.0, 0.04, 3.0), _mat(Color(0.32, 0.28, 0.4), 0.9, 0.0))
	_box(root, "L2Seat", Vector3(-6, FLOOR2_Y + 0.35, 8.6), Vector3(2.4, 0.35, 0.7), _mat(Color(0.4, 0.3, 0.22), 0.8, 0.0))
	_box(root, "L2Plant", Vector3(6, FLOOR2_Y + 0.4, 10), Vector3(0.6, 0.7, 0.6), _mat(Color(0.3, 0.5, 0.32), 0.85, 0.0))
	var tag := Label3D.new()
	tag.text = "L2 · Lounge"
	tag.font_size = 48
	tag.outline_size = 8
	tag.pixel_size = 0.012
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.75, 0.88, 1.0)
	root.add_child(tag)
	tag.position = Vector3(-6, FLOOR2_Y + 1.6, 7)
	_place_elevator(root)


func _place_elevator(root: Node3D) -> void:
	"""Glass elevator shaft + cab; ride via Hub F (thin teleport / Y offset)."""
	var frame := _mat(Color(0.22, 0.26, 0.32), 0.55, 0.35)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.45, 0.7, 0.95, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.4
	glass.emission_enabled = true
	glass.emission = Color(0.2, 0.45, 0.7)
	glass.emission_energy_multiplier = 0.5
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cab := _mat(Color(0.5, 0.55, 0.6), 0.5, 0.2)
	var h := CEILING_Y - 0.4
	var y_mid := h * 0.5
	var w := 3.2
	# Shaft: back (S), left (E), right (W); front (−Z) open with glass doors
	_box(root, "ElevS", Vector3(ELEV_X, y_mid, ELEV_Z + w * 0.5), Vector3(w + 0.2, h, 0.18), frame)
	_box(root, "ElevE", Vector3(ELEV_X + w * 0.5, y_mid, ELEV_Z), Vector3(0.18, h, w), frame)
	_box(root, "ElevW", Vector3(ELEV_X - w * 0.5, y_mid, ELEV_Z), Vector3(0.18, h, w), frame)
	# Glass door leaves on open face (−Z)
	_box(root, "ElevDoorL", Vector3(ELEV_X - 0.75, 1.6, ELEV_Z - w * 0.5), Vector3(1.3, 3.0, 0.06), glass)
	_box(root, "ElevDoorR", Vector3(ELEV_X + 0.75, 1.6, ELEV_Z - w * 0.5), Vector3(1.3, 3.0, 0.06), glass)
	# Cab floor + ceiling (parked at L1)
	_box(root, "ElevCabFloor", Vector3(ELEV_X, 0.08, ELEV_Z), Vector3(w - 0.35, 0.12, w - 0.35), cab)
	_box(root, "ElevCabCeil", Vector3(ELEV_X, 3.1, ELEV_Z), Vector3(w - 0.35, 0.1, w - 0.35), cab)
	# Door frame lintel
	_box(root, "ElevLint", Vector3(ELEV_X, 3.25, ELEV_Z - w * 0.5), Vector3(w + 0.15, 0.25, 0.2), frame)
	# Upper door ghost (L2 opening)
	_box(root, "ElevDoorL2", Vector3(ELEV_X, FLOOR2_Y + 1.5, ELEV_Z - w * 0.5), Vector3(2.6, 2.6, 0.05), glass)
	var led := _mat(Color(0.4, 0.85, 1.0), 0.4, 0.0)
	led.emission_enabled = true
	led.emission = Color(0.3, 0.75, 1.0)
	led.emission_energy_multiplier = 1.2
	_box(root, "ElevLed", Vector3(ELEV_X, 3.55, ELEV_Z - w * 0.5 - 0.05), Vector3(1.8, 0.08, 0.08), led)
	var label := Label3D.new()
	label.text = "Elevator · F to ride"
	label.font_size = 40
	label.outline_size = 6
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.55, 0.9, 1.0)
	root.add_child(label)
	label.position = Vector3(ELEV_X, 4.0, ELEV_Z - w * 0.5 - 0.4)


func _place_props(root: Node3D) -> void:
	"""Sparse Kenney accents near walls — center stays clear."""
	var hx := HALL_HALF_X
	var hz := HALL_HALF_Z
	var props: Array = [
		{"a": "screen-panel-wide.glb", "x": hx - 1.2, "z": 6.0, "yaw": -90.0, "s": 1.1},
		{"a": "screen-panel-wide.glb", "x": -hx + 1.2, "z": 6.0, "yaw": 90.0, "s": 1.1},
		# SE corner reserved for elevator showcase — no machine there
		{"a": "machine-fortified.glb", "x": -hx + 2.0, "z": hz - 2.0, "yaw": 180.0},
		{"a": "cone.glb", "x": 5.0, "z": -hz + 1.5, "yaw": 0.0},
		{"a": "cone.glb", "x": -5.0, "z": -hz + 1.5, "yaw": 0.0},
		{"a": "box-large.glb", "x": hx - 2.5, "z": -hz + 2.5, "yaw": 10.0},
		{"a": "warning-orange.glb", "x": hx - 1.5, "z": -5.0, "yaw": 0.0},
	]
	for item in props:
		_spawn(
			root,
			str(item["a"]),
			float(item["x"]),
			float(item["z"]),
			float(item["yaw"]),
			float(item.get("s", 1.0)),
		)


func _spawn(parent: Node3D, asset: String, x: float, z: float, yaw_deg: float, s: float) -> void:
	"""Instance a factory glb if present."""
	var path := ASSET_DIR + asset
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	parent.add_child(node)
	node.position = Vector3(x, 0.0, z)
	node.rotation_degrees.y = yaw_deg
	if s != 1.0:
		node.scale = Vector3(s, s, s)


func _hide_greybox() -> void:
	"""Hide primitive Floor/Walls; keep door markers."""
	var world := get_parent().get_node_or_null("World") as Node3D
	if world == null:
		return
	for child_name in ["Floor", "WallN", "WallS", "WallW", "WallE"]:
		var n := world.get_node_or_null(child_name) as Node3D
		if n != null:
			n.visible = false
	for child_name in ["DoorWorkshop", "DoorCity", "DoorStubC", "DoorStubD", "DoorStubE"]:
		var door := world.get_node_or_null(child_name)
		if door is MeshInstance3D:
			(door as MeshInstance3D).mesh = null
			door.visible = true
	_ensure_marker(world, "DoorWorkshop", Vector3(HALL_HALF_X - 1.5, 1.6, 0.0), "A - Workshop", Color(1.0, 0.7, 0.3))
	_ensure_marker(world, "DoorCity", Vector3(-HALL_HALF_X + 1.5, 1.6, 0.0), "B - Training", Color(0.4, 0.85, 1.0))
	_ensure_marker(world, "DoorStubC", Vector3(0.0, 1.6, -HALL_HALF_Z + 1.5), "C - Design (soon)", Color(0.75, 0.8, 0.85))
	_ensure_marker(world, "DoorStubD", Vector3(-6.0, 1.6, -HALL_HALF_Z + 1.5), "D - Missions (soon)", Color(0.65, 0.7, 0.75))
	_ensure_marker(world, "DoorStubE", Vector3(6.0, 1.6, -HALL_HALF_Z + 1.5), "E - Arena (soon)", Color(0.65, 0.7, 0.75))


func _ensure_marker(world: Node3D, marker_name: String, pos: Vector3, text: String, col: Color) -> void:
	"""Door route label."""
	var n := world.get_node_or_null(marker_name) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = marker_name
		world.add_child(n)
	n.position = pos
	var label := n.get_node_or_null("DoorLabel") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "DoorLabel"
		n.add_child(label)
		label.position = Vector3(0, 2.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 56
		label.outline_size = 8
		label.pixel_size = 0.01
	label.text = text
	label.modulate = col


func _place_door_glows() -> void:
	"""Neon portal slabs in door bays."""
	var world := get_parent().get_node_or_null("World") as Node3D
	if world == null:
		return
	_glow_at(world, Vector3(HALL_HALF_X - 0.35, 1.6, 0.0), Color(1.0, 0.45, 0.1), Vector3(0.12, 3.0, 2.8))
	_glow_at(world, Vector3(-HALL_HALF_X + 0.35, 1.6, 0.0), Color(0.2, 0.65, 1.0), Vector3(0.12, 3.0, 2.8))
	_glow_at(world, Vector3(0.0, 1.6, -HALL_HALF_Z + 0.35), Color(0.75, 0.85, 0.9), Vector3(2.4, 2.6, 0.12))
	_glow_at(world, Vector3(-6.0, 1.6, -HALL_HALF_Z + 0.35), Color(0.55, 0.6, 0.65), Vector3(2.0, 2.4, 0.1))
	_glow_at(world, Vector3(6.0, 1.6, -HALL_HALF_Z + 0.35), Color(0.55, 0.6, 0.65), Vector3(2.0, 2.4, 0.1))


func _glow_at(parent: Node3D, pos: Vector3, color: Color, size: Vector3) -> void:
	"""Emissive portal marker."""
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
