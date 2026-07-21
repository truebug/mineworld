## Viewer-only hub hall dress: solid enclosed hangar (docs/18).
## Procedural shell first (always visible); sparse Kenney props as accents.
extends Node3D

const ASSET_DIR := "res://assets/kenney_factory/"
## Hangar Core · mothership scale (docs/24).
const HALL_HALF_X := 24.0
const HALL_HALF_Z := 20.0
const CEILING_Y := 22.0
const WALL_T := 0.6
## Showcase mezzanine; H8 thin elevator ride (viewer Y offset in hub.gd).
const FLOOR2_Y := 8.5
const ELEV_X := 16.0
const ELEV_Z := 15.0
## Exterior apron half-extents (walkable + future modules).
const APRON_HALF_X := 36.0
const APRON_HALF_Z := 30.0


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
	_place_apron(root)
	_place_space_windows(root)
	_place_mezzanine(root)
	_place_room_shells(root)
	_place_props(root)
	_place_door_glows()
	_place_wing_labels(root)
	print("[MW] hub dress: mothership hangar %.0fx%.0f roof_y=%.1f L2=%.1f apron=%.0fx%.0f" % [
		HALL_HALF_X * 2.0, HALL_HALF_Z * 2.0, CEILING_Y, FLOOR2_Y,
		APRON_HALF_X * 2.0, APRON_HALF_Z * 2.0,
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
		fill.light_energy = 1.8
		fill.omni_range = 42.0
		fill.position = Vector3(0.0, 10.0, 0.0)


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
	"""Tall glass ribbons + skylights — cosmos visible from Hangar Core."""
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
	var y := 13.0
	var h := 7.5
	var t := 0.1
	_box(root, "LintS", Vector3(0, CEILING_Y - 0.55, hz), Vector3(hx * 2.0, 0.5, WALL_T), frame)
	_box(root, "LintN", Vector3(0, CEILING_Y - 0.55, -hz), Vector3(hx * 2.0, 0.5, WALL_T), frame)
	_box(root, "LintE", Vector3(hx, CEILING_Y - 0.55, 0), Vector3(WALL_T, 0.5, hz * 2.0), frame)
	_box(root, "LintW", Vector3(-hx, CEILING_Y - 0.55, 0), Vector3(WALL_T, 0.5, hz * 2.0), frame)
	# South / North glass bands (split around door bays).
	_box(root, "WinS", Vector3(0, y, hz), Vector3(hx * 2.0 - 1.0, h, t), glass)
	_box(root, "WinNW", Vector3(-12, y, -hz), Vector3(16.0, h, t), glass)
	_box(root, "WinNE", Vector3(12, y, -hz), Vector3(16.0, h, t), glass)
	_box(root, "WinW", Vector3(-hx, y, 6), Vector3(t, h, 14.0), glass)
	_box(root, "WinWN", Vector3(-hx, y, -10), Vector3(t, h, 10.0), glass)
	_box(root, "WinE", Vector3(hx, y, 6), Vector3(t, h, 14.0), glass)
	_box(root, "WinEN", Vector3(hx, y, -10), Vector3(t, h, 10.0), glass)
	var sky_glass := glass.duplicate() as StandardMaterial3D
	sky_glass.albedo_color = Color(0.2, 0.35, 0.65, 0.1)
	_box(root, "SkyL", Vector3(-8, CEILING_Y - 0.05, 0), Vector3(10.0, 0.06, 22.0), sky_glass)
	_box(root, "SkyR", Vector3(8, CEILING_Y - 0.05, 0), Vector3(10.0, 0.06, 22.0), sky_glass)


func _place_apron(root: Node3D) -> void:
	"""Exterior mothership deck beyond hangar walls (grid plating for future modules)."""
	var deck := _mat(Color(0.22, 0.26, 0.32), 0.85, 0.25)
	var grid := _mat(Color(0.35, 0.55, 0.7), 0.55, 0.15)
	grid.emission_enabled = true
	grid.emission = Color(0.2, 0.4, 0.6)
	grid.emission_energy_multiplier = 0.35
	var rim := _mat(Color(0.55, 0.7, 0.9), 0.4, 0.3)
	rim.emission_enabled = true
	rim.emission = Color(0.4, 0.65, 0.95)
	rim.emission_energy_multiplier = 0.55
	# Main apron slab (below hangar floor so interior deck stays primary).
	_box(
		root, "Apron",
		Vector3(0, -0.18, 0),
		Vector3(APRON_HALF_X * 2.0, 0.1, APRON_HALF_Z * 2.0),
		deck,
	)
	# Grid lines every 8 m.
	var step := 8.0
	var gx := -APRON_HALF_X + step
	while gx < APRON_HALF_X:
		_box(root, "GridX", Vector3(gx, -0.12, 0), Vector3(0.08, 0.02, APRON_HALF_Z * 2.0 - 1.0), grid)
		gx += step
	var gz := -APRON_HALF_Z + step
	while gz < APRON_HALF_Z:
		_box(root, "GridZ", Vector3(0, -0.12, gz), Vector3(APRON_HALF_X * 2.0 - 1.0, 0.02, 0.08), grid)
		gz += step
	# Rim lights (south dock emphasis).
	_box(root, "RimS", Vector3(0, -0.05, APRON_HALF_Z - 0.4), Vector3(APRON_HALF_X * 1.6, 0.06, 0.35), rim)
	_box(root, "RimN", Vector3(0, -0.05, -APRON_HALF_Z + 0.4), Vector3(APRON_HALF_X * 1.6, 0.06, 0.35), rim)
	_box(root, "RimE", Vector3(APRON_HALF_X - 0.4, -0.05, 0), Vector3(0.35, 0.06, APRON_HALF_Z * 1.4), rim)
	_box(root, "RimW", Vector3(-APRON_HALF_X + 0.4, -0.05, 0), Vector3(0.35, 0.06, APRON_HALF_Z * 1.4), rim)
	# Future-module pads (south apron = ship berth placeholders).
	var pad := _mat(Color(0.28, 0.32, 0.4), 0.7, 0.2)
	_box(root, "BerthL", Vector3(-14, -0.08, APRON_HALF_Z - 8), Vector3(10.0, 0.08, 8.0), pad)
	_box(root, "BerthR", Vector3(14, -0.08, APRON_HALF_Z - 8), Vector3(10.0, 0.08, 8.0), pad)
	_place_apron_modules(root)


func _place_apron_modules(root: Node3D) -> void:
	"""H12c: two exterior module pods on south berth pads (visual only)."""
	_module_pod(root, "ModHab", Vector3(-14, 0, APRON_HALF_Z - 8), Color(0.45, 0.55, 0.7), "栖息舱 · Hab")
	_module_pod(root, "ModDock", Vector3(14, 0, APRON_HALF_Z - 8), Color(0.55, 0.7, 0.55), "接驳舱 · Berth")


func _module_pod(root: Node3D, base: String, pos: Vector3, tint: Color, tag: String) -> void:
	"""Simple sealed module: hull + window band + mast."""
	var hull := _mat(tint.darkened(0.25), 0.65, 0.2)
	var band := _mat(tint.lightened(0.15), 0.4, 0.15)
	band.emission_enabled = true
	band.emission = tint
	band.emission_energy_multiplier = 0.45
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.5, 0.75, 0.95, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.12
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(root, base + "Hull", pos + Vector3(0, 2.2, 0), Vector3(7.0, 4.0, 5.5), hull)
	_box(root, base + "Band", pos + Vector3(0, 3.6, 0), Vector3(7.2, 0.25, 5.7), band)
	_box(root, base + "Win", pos + Vector3(0, 2.4, 2.85), Vector3(4.0, 1.6, 0.08), glass)
	_box(root, base + "Mast", pos + Vector3(2.8, 5.2, -1.5), Vector3(0.2, 2.4, 0.2), band)
	_box(root, base + "Dish", pos + Vector3(2.8, 6.5, -1.5), Vector3(1.4, 0.15, 1.4), band)
	var lab := Label3D.new()
	lab.text = tag
	lab.font_size = 42
	lab.outline_size = 6
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = tint.lightened(0.35)
	root.add_child(lab)
	lab.position = pos + Vector3(0, 5.0, 0)


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
	# Walls: lower band + upper band (door gaps); taller stack under glass ribbon.
	var split := 4.5
	_wall_ring(root, "WallLow", wall_low, 0.0, split)
	_wall_ring(root, "WallHi", wall_hi, split, 4.0)  ## ends ~8.5m; glass ribbon to ceiling
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
	# South split around Arena (E) bay
	var s_span := hx - door * 0.5
	_box(root, prefix + "SW", Vector3(-(hx + door) * 0.5, y_mid, hz), Vector3(s_span, h, t), mat)
	_box(root, prefix + "SE", Vector3((hx + door) * 0.5, y_mid, hz), Vector3(s_span, h, t), mat)
	# North split around Design (C) bay
	var n_span := hx - door * 0.5
	_box(root, prefix + "NW", Vector3(-(hx + door) * 0.5, y_mid, -hz), Vector3(n_span, h, t), mat)
	_box(root, prefix + "NE", Vector3((hx + door) * 0.5, y_mid, -hz), Vector3(n_span, h, t), mat)
	# West / East split around Training (B) / Workshop (A)
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
	tag.text = "L2 母港观景廊\nMothership Lounge"
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
	label.text = "电梯 · 按 F 乘梯\nElevator · F to ride"
	label.font_size = 40
	label.outline_size = 6
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.55, 0.9, 1.0)
	root.add_child(label)
	label.position = Vector3(ELEV_X, 4.0, ELEV_Z - w * 0.5 - 0.4)


func _place_room_shells(root: Node3D) -> void:
	"""H10: north-wall gallery / classroom corridor alcoves (narrative only)."""
	var frame := _mat(Color(0.28, 0.3, 0.34), 0.65, 0.15)
	var trim := _mat(Color(0.55, 0.48, 0.32), 0.5, 0.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.7, 0.85, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.15
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Gallery alcove (−X, −Z)
	_box(root, "GalArchL", Vector3(-9.5, 2.2, -HALL_HALF_Z + 0.35), Vector3(0.25, 4.2, 0.35), frame)
	_box(root, "GalArchR", Vector3(-6.5, 2.2, -HALL_HALF_Z + 0.35), Vector3(0.25, 4.2, 0.35), frame)
	_box(root, "GalLint", Vector3(-8.0, 4.2, -HALL_HALF_Z + 0.35), Vector3(3.2, 0.28, 0.4), trim)
	_box(root, "GalGlass", Vector3(-8.0, 2.0, -HALL_HALF_Z + 0.15), Vector3(2.6, 3.2, 0.06), glass)
	var gal := Label3D.new()
	gal.text = "展厅翼 · Gallery"
	gal.font_size = 42
	gal.outline_size = 6
	gal.pixel_size = 0.01
	gal.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	gal.modulate = Color(0.9, 0.8, 0.55)
	root.add_child(gal)
	gal.position = Vector3(-8.0, 4.7, -HALL_HALF_Z + 0.8)
	# Classroom alcove (+X, −Z)
	_box(root, "ClsArchL", Vector3(6.5, 2.2, -HALL_HALF_Z + 0.35), Vector3(0.25, 4.2, 0.35), frame)
	_box(root, "ClsArchR", Vector3(9.5, 2.2, -HALL_HALF_Z + 0.35), Vector3(0.25, 4.2, 0.35), frame)
	_box(root, "ClsLint", Vector3(8.0, 4.2, -HALL_HALF_Z + 0.35), Vector3(3.2, 0.28, 0.4), trim)
	_box(root, "ClsGlass", Vector3(8.0, 2.0, -HALL_HALF_Z + 0.15), Vector3(2.6, 3.2, 0.06), glass)
	var cls := Label3D.new()
	cls.text = "教室翼 · Classroom"
	cls.font_size = 42
	cls.outline_size = 6
	cls.pixel_size = 0.01
	cls.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cls.modulate = Color(0.55, 0.85, 1.0)
	root.add_child(cls)
	cls.position = Vector3(8.0, 4.7, -HALL_HALF_Z + 0.8)
	_place_arena_shell(root)
	_place_design_shell(root)
	_place_edge_shell(root)


func _place_design_shell(root: Node3D) -> void:
	"""H7c: Door C Design Lab — PMS card wing narrative shell (no editor)."""
	var frame := _mat(Color(0.28, 0.34, 0.42), 0.55, 0.15)
	var trim := _mat(Color(0.7, 0.85, 1.0), 0.4, 0.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.65, 0.8, 0.95, 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.15
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cx := 0.0
	var cz := -HALL_HALF_Z + 1.8
	_box(root, "DesArchL", Vector3(cx - 1.5, 2.1, cz), Vector3(0.26, 4.0, 0.3), frame)
	_box(root, "DesArchR", Vector3(cx + 1.5, 2.1, cz), Vector3(0.26, 4.0, 0.3), frame)
	_box(root, "DesLint", Vector3(cx, 4.15, cz), Vector3(3.2, 0.28, 0.36), trim)
	_box(root, "DesGlass", Vector3(cx, 2.0, cz - 0.15), Vector3(2.6, 3.2, 0.05), glass)
	_box(root, "DesPad", Vector3(cx, 0.03, cz + 1.0), Vector3(3.4, 0.06, 2.2), _mat(Color(0.3, 0.36, 0.44), 0.75, 0.05))
	# Status strip: sealed / Type B
	var seal := _mat(Color(0.55, 0.75, 0.95), 0.45, 0.1)
	seal.emission_enabled = true
	seal.emission = Color(0.4, 0.65, 0.9)
	seal.emission_energy_multiplier = 0.7
	_box(root, "DesSeal", Vector3(cx, 3.5, cz + 0.05), Vector3(2.0, 0.12, 0.12), seal)
	var lab := Label3D.new()
	lab.text = "设计室 · 卡片通道\nDesign Lab · Type B"
	lab.font_size = 36
	lab.outline_size = 6
	lab.pixel_size = 0.01
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(0.8, 0.9, 1.0)
	root.add_child(lab)
	lab.position = Vector3(cx, 4.7, cz + 0.6)


func _place_edge_shell(root: Node3D) -> void:
	"""H7c: Door D Edge Dock — edge/real-robot narrative shell (no live link)."""
	var frame := _mat(Color(0.22, 0.36, 0.32), 0.55, 0.2)
	var trim := _mat(Color(0.45, 0.85, 0.7), 0.4, 0.25)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.75, 0.6, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dx := -HALL_HALF_X + 1.9
	var dz := -10.0
	_box(root, "EdgArchT", Vector3(dx, 2.0, dz - 1.3), Vector3(0.28, 3.8, 0.3), frame)
	_box(root, "EdgArchB", Vector3(dx, 2.0, dz + 1.3), Vector3(0.28, 3.8, 0.3), frame)
	_box(root, "EdgLint", Vector3(dx, 3.95, dz), Vector3(0.36, 0.28, 2.8), trim)
	_box(root, "EdgGlass", Vector3(dx - 0.2, 1.9, dz), Vector3(0.05, 3.0, 2.2), glass)
	_box(root, "EdgPad", Vector3(dx + 1.0, 0.03, dz), Vector3(2.2, 0.06, 3.2), _mat(Color(0.2, 0.32, 0.28), 0.75, 0.05))
	# Airlock ring hint
	var ring := _mat(Color(0.4, 0.9, 0.7), 0.4, 0.15)
	ring.emission_enabled = true
	ring.emission = Color(0.3, 0.8, 0.6)
	ring.emission_energy_multiplier = 0.65
	_box(root, "EdgRing", Vector3(dx - 0.05, 1.8, dz), Vector3(0.1, 2.4, 0.1), ring)
	var lab := Label3D.new()
	lab.text = "边缘任务坞\nEdge Dock · Type C"
	lab.font_size = 36
	lab.outline_size = 6
	lab.pixel_size = 0.01
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(0.6, 0.95, 0.8)
	root.add_child(lab)
	lab.position = Vector3(dx + 0.8, 4.5, dz)


func _place_arena_shell(root: Node3D) -> void:
	"""H11: Door E arena gate shell (narrative only — no matchmaking)."""
	var frame := _mat(Color(0.42, 0.22, 0.2), 0.55, 0.2)
	var trim := _mat(Color(0.85, 0.45, 0.28), 0.45, 0.25)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.9, 0.35, 0.25, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.2
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ax := 0.0
	var az := HALL_HALF_Z - 1.8
	_box(root, "ArnArchL", Vector3(ax - 1.4, 2.0, az), Vector3(0.28, 3.8, 0.32), frame)
	_box(root, "ArnArchR", Vector3(ax + 1.4, 2.0, az), Vector3(0.28, 3.8, 0.32), frame)
	_box(root, "ArnLint", Vector3(ax, 3.95, az), Vector3(3.0, 0.3, 0.38), trim)
	_box(root, "ArnGlass", Vector3(ax, 1.9, az + 0.2), Vector3(2.4, 3.0, 0.05), glass)
	_box(root, "ArnPad", Vector3(ax, 0.03, az - 0.9), Vector3(3.2, 0.06, 2.0), _mat(Color(0.35, 0.18, 0.16), 0.7, 0.05))
	var lab := Label3D.new()
	lab.text = "竞技场门\nArena Gate"
	lab.font_size = 40
	lab.outline_size = 6
	lab.pixel_size = 0.01
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = Color(1.0, 0.55, 0.35)
	root.add_child(lab)
	lab.position = Vector3(ax, 4.55, az - 0.5)


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
	_ensure_marker(
		world, "DoorWorkshop",
		Vector3(HALL_HALF_X - 1.5, 1.6, 0.0),
		"A 仿真工坊\nWorkshop",
		Color(1.0, 0.7, 0.3),
	)
	_ensure_marker(
		world, "DoorCity",
		Vector3(-HALL_HALF_X + 1.5, 1.6, 0.0),
		"B 机甲训练场\nTraining Yard",
		Color(0.4, 0.85, 1.0),
	)
	_ensure_marker(
		world, "DoorStubC",
		Vector3(0.0, 1.6, -HALL_HALF_Z + 1.5),
		"C 设计室 · 卡片\nDesign Lab",
		Color(0.75, 0.85, 0.95),
	)
	_ensure_marker(
		world, "DoorStubD",
		Vector3(-HALL_HALF_X + 1.8, 1.6, -10.0),
		"D 边缘任务坞\nEdge Dock",
		Color(0.65, 0.75, 0.7),
	)
	_ensure_marker(
		world, "DoorStubE",
		Vector3(0.0, 1.6, HALL_HALF_Z - 1.5),
		"E 竞技场门\nArena Gate",
		Color(1.0, 0.5, 0.3),
	)


func _place_wing_labels(root: Node3D) -> void:
	"""Floor-facing wing tags for three exit types (docs/24)."""
	_zone_label(root, "ZoneA", Vector3(HALL_HALF_X - 5.0, 0.05, 4.0), "本仓关卡 · Native", Color(1.0, 0.65, 0.3))
	_zone_label(root, "ZoneB", Vector3(0.0, 0.05, -HALL_HALF_Z + 5.0), "卡片通道 · PMS Cards", Color(0.7, 0.85, 1.0))
	_zone_label(root, "ZoneC", Vector3(-HALL_HALF_X + 5.0, 0.05, -6.0), "边缘入口 · Edge", Color(0.55, 0.85, 0.7))
	_zone_label(root, "ZoneCore", Vector3(0.0, 0.05, 2.0), "母港核心 · Hangar Core", Color(0.85, 0.9, 1.0))


func _zone_label(root: Node3D, lab_name: String, pos: Vector3, text: String, col: Color) -> void:
	"""Billboard zone caption near the floor."""
	var lab := Label3D.new()
	lab.name = lab_name
	lab.text = text
	lab.font_size = 36
	lab.outline_size = 5
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = col
	root.add_child(lab)
	lab.position = pos + Vector3(0, 1.2, 0)


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
	_glow_at(world, Vector3(HALL_HALF_X - 0.35, 1.6, 0.0), Color(1.0, 0.45, 0.1), Vector3(0.12, 3.2, 3.0))
	_glow_at(world, Vector3(-HALL_HALF_X + 0.35, 1.6, 0.0), Color(0.2, 0.65, 1.0), Vector3(0.12, 3.2, 3.0))
	_glow_at(world, Vector3(0.0, 1.6, -HALL_HALF_Z + 0.35), Color(0.75, 0.85, 0.95), Vector3(2.6, 2.8, 0.12))
	_glow_at(world, Vector3(-HALL_HALF_X + 0.35, 1.6, -10.0), Color(0.45, 0.75, 0.6), Vector3(0.12, 2.8, 2.4))
	_glow_at(world, Vector3(0.0, 1.6, HALL_HALF_Z - 0.35), Color(1.0, 0.4, 0.2), Vector3(2.6, 2.8, 0.12))


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
