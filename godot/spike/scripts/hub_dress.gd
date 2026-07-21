## Viewer-only hub hall dress: solid enclosed hangar (docs/18 · 24).
## Visual language: matte megastructure + cyan emissive panels (spaceport island).
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
## Exterior apron half-extents (walkable island + visual city mass).
const APRON_HALF_X := 48.0
const APRON_HALF_Z := 42.0
## Port accent (refs: modular ring / cyan energy panels).
const CYAN := Color(0.25, 0.85, 1.0)


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
	"""Cool port lighting + deep-space sky (harder contrast than warehouse)."""
	var env_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		var e: Environment = env_node.environment
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.28, 0.34, 0.45)
		e.ambient_light_energy = 0.35
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.tonemap_exposure = 1.05
		e.glow_enabled = true
		e.glow_intensity = 0.35
		e.glow_strength = 0.7
		e.glow_bloom = 0.08
		_apply_space_sky(e)
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color(0.75, 0.85, 1.0)
		sun.light_energy = 0.85
		sun.shadow_enabled = false
		sun.rotation_degrees = Vector3(-48, 35, 0)
	var fill := get_parent().get_node_or_null("Fill") as OmniLight3D
	if fill != null:
		fill.light_color = Color(0.35, 0.75, 0.95)
		fill.light_energy = 2.4
		fill.omni_range = 48.0
		fill.position = Vector3(0.0, 12.0, 0.0)


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
	"""Tall cyan glass ribbons + skylights — cosmos as port backdrop."""
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.2, 0.55, 0.85, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.45
	glass.emission_enabled = true
	glass.emission = CYAN
	glass.emission_energy_multiplier = 0.55
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var frame := _mat(Color(0.18, 0.22, 0.28), 0.55, 0.35)
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
	sky_glass.albedo_color = Color(0.15, 0.4, 0.7, 0.12)
	_box(root, "SkyL", Vector3(-8, CEILING_Y - 0.05, 0), Vector3(10.0, 0.06, 22.0), sky_glass)
	_box(root, "SkyR", Vector3(8, CEILING_Y - 0.05, 0), Vector3(10.0, 0.06, 22.0), sky_glass)


func _place_apron(root: Node3D) -> void:
	"""Irregular harbor island: ring decks + dock basins (not one flat slab)."""
	var deck := _mat(Color(0.16, 0.19, 0.24), 0.8, 0.35)
	var terrace := _mat(Color(0.14, 0.17, 0.22), 0.78, 0.4)
	var grid := _emissive(Color(0.2, 0.35, 0.45), CYAN, 0.5)
	var rim := _emissive(Color(0.3, 0.5, 0.6), CYAN, 0.95)
	# Core plaza under hangar (keeps walkable center).
	_box(root, "CoreDeck", Vector3(0, -0.18, 0), Vector3(HALL_HALF_X * 2.4, 0.14, HALL_HALF_Z * 2.4), deck)
	# Ring harbor decks (octant slabs) — broken silhouette vs single rectangle.
	_box(root, "RingN", Vector3(0, -0.2, -30), Vector3(56, 0.14, 18), deck)
	_box(root, "RingNE", Vector3(30, -0.28, -24), Vector3(22, 0.14, 20), deck)
	_box(root, "RingE", Vector3(36, -0.35, 0), Vector3(18, 0.14, 44), deck)
	_box(root, "RingSE", Vector3(30, -0.28, 22), Vector3(22, 0.14, 18), deck)
	_box(root, "RingNW", Vector3(-30, -0.28, -24), Vector3(22, 0.14, 20), deck)
	_box(root, "RingW", Vector3(-36, -0.35, 0), Vector3(18, 0.14, 44), deck)
	_box(root, "RingSW", Vector3(-30, -0.28, 22), Vector3(22, 0.14, 18), deck)
	# South split into three pads with dock basins between.
	_box(root, "RingS_L", Vector3(-24, -0.22, 32), Vector3(20, 0.14, 16), deck)
	_box(root, "RingS_M", Vector3(0, -0.22, 30), Vector3(14, 0.14, 12), deck)
	_box(root, "RingS_R", Vector3(24, -0.22, 32), Vector3(20, 0.14, 16), deck)
	# Outer terraces (lower shelves).
	_box(root, "TerraceN", Vector3(0, -0.7, -44), Vector3(50, 0.2, 12), terrace)
	_box(root, "TerraceE", Vector3(48, -1.0, 0), Vector3(12, 0.2, 50), terrace)
	_box(root, "TerraceW", Vector3(-48, -1.0, 0), Vector3(12, 0.2, 50), terrace)
	_box(root, "TerraceSE", Vector3(34, -0.85, 40), Vector3(18, 0.2, 12), terrace)
	_box(root, "TerraceSW", Vector3(-34, -0.85, 40), Vector3(18, 0.2, 12), terrace)
	# Sparse grid only on core + north ring (avoid filling dock voids).
	var step := 8.0
	var gx := -20.0
	while gx <= 20.0:
		_box(root, "GridX", Vector3(gx, -0.08, -6), Vector3(0.08, 0.02, 36.0), grid)
		gx += step
	var gz := -28.0
	while gz <= 12.0:
		_box(root, "GridZ", Vector3(0, -0.08, gz), Vector3(40.0, 0.02, 0.08), grid)
		gz += step
	# Rim lights along ring outer edges.
	_box(root, "RimN", Vector3(0, -0.05, -38), Vector3(52, 0.08, 0.4), rim)
	_box(root, "RimE", Vector3(44, -0.12, 0), Vector3(0.4, 0.08, 48), rim)
	_box(root, "RimW", Vector3(-44, -0.12, 0), Vector3(0.4, 0.08, 48), rim)
	# South berth pads sit on RingS_* .
	var pad := _mat(Color(0.2, 0.24, 0.3), 0.7, 0.3)
	_box(root, "BerthL", Vector3(-24, -0.1, 34), Vector3(14.0, 0.1, 10.0), pad)
	_box(root, "BerthR", Vector3(24, -0.1, 34), Vector3(14.0, 0.1, 10.0), pad)
	_box(root, "BerthMid", Vector3(0, -0.1, 32), Vector3(12.0, 0.1, 8.0), pad)
	# Dock basins: recessed floors + side walls (visible notches).
	_place_dock_basins(root, deck, rim)
	_place_apron_modules(root)
	_place_mini_city(root)
	_place_island_skirt(root)


func _place_dock_basins(root: Node3D, deck: Material, rim: Material) -> void:
	"""South harbor notches — empty berth pockets + long docking arms."""
	var basin := _mat(Color(0.08, 0.12, 0.18), 0.9, 0.2)
	var wall := _mat(Color(0.18, 0.22, 0.28), 0.7, 0.4)
	var panel := _emissive(Color(0.12, 0.35, 0.45), CYAN, 1.15)
	var amber := _emissive(Color(0.35, 0.28, 0.18), Color(1.0, 0.55, 0.2), 0.85)
	# Three basin pockets between south pads (void reads as dock slips).
	_dock_basin_at(root, -12.0, 40.0, basin, wall, rim)
	_dock_basin_at(root, 0.0, 42.0, basin, wall, rim)
	_dock_basin_at(root, 12.0, 40.0, basin, wall, rim)
	# Lengthened cantilever arms into / beyond basins.
	_dock_arm(root, "DockArmL", Vector3(-24, 3.2, 44), wall, panel, 26.0)
	_dock_arm(root, "DockArmR", Vector3(24, 3.2, 44), wall, panel, 26.0)
	_dock_arm(root, "DockArmMid", Vector3(0, 3.8, 48), wall, amber, 30.0)
	# Approach guide lights on basin lips.
	_box(root, "ApproachL", Vector3(-12, 0.2, 48), Vector3(0.35, 0.35, 10.0), panel)
	_box(root, "ApproachR", Vector3(12, 0.2, 48), Vector3(0.35, 0.35, 10.0), panel)
	_box(root, "ApproachM", Vector3(0, 0.25, 52), Vector3(0.4, 0.4, 12.0), amber)


func _dock_basin_at(
	root: Node3D, bx: float, bz: float, basin: Material, wall: Material, rim: Material
) -> void:
	"""One recessed south dock slip."""
	_box(root, "BasinFloor", Vector3(bx, -2.4, bz), Vector3(8.0, 0.2, 14.0), basin)
	_box(root, "BasinWallL", Vector3(bx - 4.2, -1.0, bz), Vector3(0.5, 2.8, 14.0), wall)
	_box(root, "BasinWallR", Vector3(bx + 4.2, -1.0, bz), Vector3(0.5, 2.8, 14.0), wall)
	_box(root, "BasinLip", Vector3(bx, -0.35, bz - 6), Vector3(9.0, 0.25, 0.6), rim)


func _place_island_skirt(root: Node3D) -> void:
	"""Drop-edge keel skirt — understructure readable from the side."""
	var hull := _mat(Color(0.18, 0.22, 0.28), 0.75, 0.45)
	var hull_hi := _mat(Color(0.22, 0.26, 0.32), 0.7, 0.4)
	var panel := _emissive(Color(0.12, 0.32, 0.42), CYAN, 0.95)
	# Perimeter drop faces (island lip hanging into void).
	_box(root, "SkirtN", Vector3(0, -3.2, -39), Vector3(54, 6.0, 1.2), hull)
	_box(root, "SkirtS_L", Vector3(-26, -3.0, 39), Vector3(22, 5.5, 1.2), hull)
	_box(root, "SkirtS_R", Vector3(26, -3.0, 39), Vector3(22, 5.5, 1.2), hull)
	_box(root, "SkirtE", Vector3(45, -3.5, 0), Vector3(1.2, 6.5, 52), hull)
	_box(root, "SkirtW", Vector3(-45, -3.5, 0), Vector3(1.2, 6.5, 52), hull)
	# Cyan face panels on skirts.
	_box(root, "SkirtPanelN", Vector3(0, -2.5, -39.7), Vector3(40, 3.5, 0.2), panel)
	_box(root, "SkirtPanelE", Vector3(45.7, -2.8, 0), Vector3(0.2, 4.0, 36), panel)
	_box(root, "SkirtPanelW", Vector3(-45.7, -2.8, 0), Vector3(0.2, 4.0, 36), panel)
	# Deeper keel mass (stepped).
	_box(root, "Keel", Vector3(0, -6.5, -4), Vector3(42, 5.0, 48), hull)
	_box(root, "KeelCore", Vector3(0, -11.0, -2), Vector3(22, 6.0, 28), hull_hi)
	_box(root, "KeelFinS", Vector3(0, -8.0, 28), Vector3(16, 4.0, 8), hull)
	_box(
		root, "UnderGlow",
		Vector3(0, -2.0, 0),
		Vector3(70, 0.15, 64),
		_emissive(Color(0.1, 0.25, 0.35), CYAN, 0.9),
	)
	_box(
		root, "UnderGlowDeep",
		Vector3(0, -12.5, -2),
		Vector3(16, 0.2, 20),
		_emissive(Color(0.15, 0.3, 0.4), CYAN, 0.65),
	)


func _place_mini_city(root: Node3D) -> void:
	"""Dense stacked modules on ring — taller height range."""
	var hull := _mat(Color(0.2, 0.24, 0.3), 0.7, 0.4)
	var hull_hi := _mat(Color(0.24, 0.28, 0.34), 0.65, 0.35)
	var panel := _emissive(Color(0.15, 0.35, 0.45), CYAN, 1.1)
	var amber := _emissive(Color(0.35, 0.28, 0.18), Color(1.0, 0.55, 0.2), 0.75)
	# Corner command pylons.
	for p in [
		Vector3(40, 0, 34), Vector3(-40, 0, 34),
		Vector3(40, 0, -34), Vector3(-40, 0, -34),
	]:
		_box(root, "Pylon", p + Vector3(0, 8.0, 0), Vector3(3.2, 16.0, 3.2), hull)
		_box(root, "PylonMid", p + Vector3(0, 14.0, 0), Vector3(4.2, 2.4, 4.2), hull_hi)
		_box(root, "PylonCap", p + Vector3(0, 16.5, 0), Vector3(3.6, 0.45, 3.6), panel)
		_box(root, "PylonFace", p + Vector3(0, 9.0, 1.7), Vector3(2.2, 6.0, 0.14), panel)
	# Dense north / east / west stacks (higher variance).
	_city_stack(root, "N1", Vector3(-28, 0, -32), 5, hull, panel)
	_city_stack(root, "N2", Vector3(-12, 0, -34), 7, hull_hi, panel)
	_city_stack(root, "N3", Vector3(4, 0, -30), 4, hull, amber)
	_city_stack(root, "N4", Vector3(18, 0, -34), 6, hull_hi, panel)
	_city_stack(root, "N5", Vector3(32, 0, -30), 5, hull, panel)
	_city_stack(root, "E1", Vector3(38, 0, -16), 6, hull, panel)
	_city_stack(root, "E2", Vector3(40, 0, -2), 8, hull_hi, panel)
	_city_stack(root, "E3", Vector3(38, 0, 14), 5, hull, amber)
	_city_stack(root, "E4", Vector3(36, 0, 26), 4, hull, panel)
	_city_stack(root, "W1", Vector3(-38, 0, -14), 6, hull, panel)
	_city_stack(root, "W2", Vector3(-40, 0, 2), 7, hull_hi, amber)
	_city_stack(root, "W3", Vector3(-38, 0, 16), 5, hull, panel)
	_city_stack(root, "W4", Vector3(-36, 0, 28), 4, hull_hi, panel)
	# South flanks beside basins (keep basin voids clear).
	_city_stack(root, "S1", Vector3(-34, 0, 28), 4, hull, panel)
	_city_stack(root, "S2", Vector3(34, 0, 28), 4, hull, amber)
	_city_stack(root, "S3", Vector3(-20, 0, 26), 3, hull_hi, panel)
	_city_stack(root, "S4", Vector3(20, 0, 26), 3, hull_hi, panel)
	# Mid-ring fillers for density.
	_city_stack(root, "M1", Vector3(-22, 0, -12), 3, hull, panel)
	_city_stack(root, "M2", Vector3(22, 0, -10), 4, hull_hi, panel)
	_city_stack(root, "M3", Vector3(-26, 0, 8), 3, hull, amber)
	_city_stack(root, "M4", Vector3(26, 0, 6), 3, hull, panel)
	# Sky bridges.
	_box(root, "BridgeN", Vector3(0, 8.0, -HALL_HALF_Z - 6), Vector3(4.5, 0.7, 18.0), hull_hi)
	_box(root, "BridgeNGlow", Vector3(0, 8.0, -HALL_HALF_Z - 6), Vector3(0.4, 0.25, 18.0), panel)
	_box(root, "BridgeE", Vector3(HALL_HALF_X + 10, 7.0, 0), Vector3(22.0, 0.55, 3.2), hull_hi)
	_box(root, "BridgeEGlow", Vector3(HALL_HALF_X + 10, 7.0, 0), Vector3(22.0, 0.2, 0.35), panel)
	_box(root, "BridgeW", Vector3(-HALL_HALF_X - 10, 7.0, 0), Vector3(22.0, 0.55, 3.2), hull_hi)
	_box(root, "BridgeWGlow", Vector3(-HALL_HALF_X - 10, 7.0, 0), Vector3(22.0, 0.2, 0.35), panel)
	# East/west secondary dock stubs.
	_box(root, "DockStubE", Vector3(48, 3.5, 0), Vector3(12.0, 1.4, 2.4), hull)
	_box(root, "DockStubETip", Vector3(56, 3.5, 0), Vector3(2.0, 2.0, 2.0), panel)
	_box(root, "DockStubW", Vector3(-48, 3.5, 0), Vector3(12.0, 1.4, 2.4), hull)
	_box(root, "DockStubWTip", Vector3(-56, 3.5, 0), Vector3(2.0, 2.0, 2.0), panel)
	_place_soft_accents(root, hull, hull_hi, panel, amber)


func _place_soft_accents(
	root: Node3D, hull: Material, hull_hi: Material, panel: Material, amber: Material
) -> void:
	"""Viewer-only spheres / rings / capsules to break pure box silhouette."""
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.3, 0.7, 0.95, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.08
	glass.metallic = 0.35
	glass.emission_enabled = true
	glass.emission = CYAN
	glass.emission_energy_multiplier = 0.55
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Corner radar domes on pylons.
	for p in [
		Vector3(40, 17.8, 34), Vector3(-40, 17.8, 34),
		Vector3(40, 17.8, -34), Vector3(-40, 17.8, -34),
	]:
		_sphere(root, "RadarDome", p, 2.4, glass)
		_torus(root, "RadarRing", p + Vector3(0, -0.4, 0), 2.8, 0.12, panel, Vector3(90, 0, 0))
	# Fuel / pressure tanks (south harbor + mid flanks).
	_sphere(root, "TankS", Vector3(0, 5.5, 36), 3.6, hull_hi)
	_torus(root, "TankSBand", Vector3(0, 5.5, 36), 3.7, 0.22, panel, Vector3(90, 0, 0))
	_sphere(root, "TankSW", Vector3(-30, 4.2, 22), 2.8, hull)
	_sphere(root, "TankSE", Vector3(30, 4.2, 22), 2.8, hull)
	_sphere(root, "TankNW", Vector3(-28, 6.0, -22), 2.2, hull_hi)
	_sphere(root, "TankNE", Vector3(28, 6.0, -22), 2.2, hull_hi)
	# Soft glow orbs tucked beside tall stacks.
	_sphere(root, "GlowE", Vector3(42, 10.0, -2), 1.6, glass)
	_sphere(root, "GlowW", Vector3(-42, 9.0, 2), 1.5, glass)
	_sphere(root, "GlowN", Vector3(-12, 12.0, -36), 1.8, amber)
	# Horizontal orbital rings (apron halo — read as curves from afar).
	_torus(root, "HaloInner", Vector3(0, 1.2, 0), 30.0, 0.35, panel, Vector3(90, 0, 0))
	_torus(root, "HaloOuter", Vector3(0, 0.6, 4), 44.0, 0.28, amber, Vector3(90, 0, 0))
	_torus(root, "HaloHi", Vector3(0, 14.0, -8), 18.0, 0.22, glass, Vector3(90, 12, 0))
	# Capsule soft-links on east/west dock stubs.
	_capsule(root, "CapE", Vector3(52, 3.5, 0), 1.1, 5.5, panel, Vector3(0, 0, 90))
	_capsule(root, "CapW", Vector3(-52, 3.5, 0), 1.1, 5.5, panel, Vector3(0, 0, 90))
	# Arch-ish uprights (cylinder bowed silhouette via paired pillars + ring).
	_cylinder(root, "ArchSPillarL", Vector3(-8, 4.0, 38), 0.55, 8.0, hull)
	_cylinder(root, "ArchSPillarR", Vector3(8, 4.0, 38), 0.55, 8.0, hull)
	_torus(root, "ArchSRing", Vector3(0, 8.2, 38), 8.2, 0.35, panel, Vector3(0, 0, 0))
	_cylinder(root, "ArchNPillarL", Vector3(-10, 5.0, -36), 0.45, 10.0, hull)
	_cylinder(root, "ArchNPillarR", Vector3(10, 5.0, -36), 0.45, 10.0, hull)
	_torus(root, "ArchNRing", Vector3(0, 10.5, -36), 10.2, 0.3, glass, Vector3(0, 0, 0))


func _city_stack(
	root: Node3D, base: String, pos: Vector3, floors: int, hull: Material, panel: Material
) -> void:
	"""Vertical stack of sealed modules (taller = more city silhouette)."""
	var y := 2.0
	var last_w := 7.0
	for i in range(floors):
		var w := 7.0 - float(i % 3) * 0.7
		var d := 5.8 - float((i + 1) % 2) * 0.7
		last_w = w
		_box(root, base + "F%d" % i, pos + Vector3(0, y, 0), Vector3(w, 3.4, d), hull)
		_box(root, base + "P%d" % i, pos + Vector3(0, y, d * 0.5 + 0.06), Vector3(w * 0.78, 2.2, 0.12), panel)
		y += 3.55
	_box(root, base + "Mast", pos + Vector3(last_w * 0.28, y + 1.4, 0), Vector3(0.28, 3.2, 0.28), panel)


func _dock_arm(
	root: Node3D, base: String, pos: Vector3, hull: Material, tip: Material, boom_len: float = 14.0
) -> void:
	"""Long cantilever fleet docking arm (south harbor)."""
	var half := boom_len * 0.5
	_box(root, base + "Boom", pos + Vector3(0, 0, half * 0.15), Vector3(2.4, 1.15, boom_len), hull)
	_box(root, base + "Joint", pos + Vector3(0, 0.2, -half * 0.35), Vector3(3.4, 2.0, 2.4), hull)
	_box(root, base + "Tip", pos + Vector3(0, 0.3, half * 0.85), Vector3(3.2, 2.6, 2.8), tip)
	_box(root, base + "Guide", pos + Vector3(0, 0.75, half * 0.1), Vector3(0.3, 0.25, boom_len), tip)
	_box(root, base + "Clamp", pos + Vector3(0, -0.6, half * 0.7), Vector3(4.0, 0.5, 1.2), tip)


func _place_apron_modules(root: Node3D) -> void:
	"""Labeled berth pods on south harbor pads."""
	_module_pod(root, "ModHab", Vector3(-24, 0, 34), Color(0.35, 0.42, 0.52), MWi18n.t("栖息舱", "Hab"))
	_module_pod(root, "ModDock", Vector3(24, 0, 34), Color(0.32, 0.4, 0.38), MWi18n.t("接驳舱", "Berth"))
	_module_pod(root, "ModCtrl", Vector3(0, 0, 30), Color(0.3, 0.36, 0.45), MWi18n.t("调度塔", "Control"))


func _module_pod(root: Node3D, base: String, pos: Vector3, tint: Color, tag: String) -> void:
	"""Sealed module: matte hull + cyan face panels + mast (ref ring aesthetic)."""
	var hull := _mat(tint.darkened(0.15), 0.7, 0.35)
	var panel := _emissive(Color(0.12, 0.32, 0.42), CYAN, 1.0)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.35, 0.75, 0.95, 0.4)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.1
	glass.emission_enabled = true
	glass.emission = CYAN
	glass.emission_energy_multiplier = 0.4
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_box(root, base + "Hull", pos + Vector3(0, 2.4, 0), Vector3(7.2, 4.4, 5.8), hull)
	_box(root, base + "Face", pos + Vector3(0, 2.5, 2.95), Vector3(5.5, 3.0, 0.12), panel)
	_box(root, base + "Win", pos + Vector3(0, 2.5, 3.02), Vector3(3.6, 1.4, 0.06), glass)
	_box(root, base + "Band", pos + Vector3(0, 4.5, 0), Vector3(7.4, 0.2, 6.0), panel)
	_box(root, base + "Mast", pos + Vector3(2.8, 5.6, -1.5), Vector3(0.22, 2.6, 0.22), panel)
	_sphere(root, base + "Dish", pos + Vector3(2.8, 7.0, -1.5), 1.05, panel)
	_torus(root, base + "Ring", pos + Vector3(2.8, 6.6, -1.5), 1.35, 0.08, panel, Vector3(90, 0, 0))
	var lab := Label3D.new()
	lab.text = tag
	lab.font_size = 42
	lab.outline_size = 6
	lab.pixel_size = 0.012
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.modulate = CYAN.lightened(0.25)
	root.add_child(lab)
	lab.position = pos + Vector3(0, 5.4, 0)


func _place_solid_hall(root: Node3D) -> void:
	"""Port core volume: dark plating, panel walls, cyan energy guides."""
	var floor_mat := _mat(Color(0.22, 0.26, 0.32), 0.75, 0.25)
	var wall_low := _mat(Color(0.28, 0.32, 0.38), 0.7, 0.28)
	var wall_hi := _mat(Color(0.2, 0.28, 0.34), 0.65, 0.3)
	var ceil_mat := _mat(Color(0.18, 0.22, 0.28), 0.75, 0.25)
	# Floor
	_box(root, "Deck", Vector3(0, -0.06, 0), Vector3(HALL_HALF_X * 2.0, 0.12, HALL_HALF_Z * 2.0), floor_mat)
	# Cyan primary guide + thin wing tint lanes (readable but not gym-floor).
	var cyan_lane := _emissive(Color(0.15, 0.4, 0.5), CYAN, 0.65)
	_box(root, "LaneCyanX", Vector3(0, 0.015, 0), Vector3(0.55, 0.02, HALL_HALF_Z * 1.6), cyan_lane)
	_box(root, "LaneCyanZ", Vector3(0, 0.015, 0), Vector3(HALL_HALF_X * 1.6, 0.02, 0.55), cyan_lane)
	_box(root, "LaneX", Vector3(0, 0.01, 0), Vector3(0.22, 0.015, HALL_HALF_Z * 1.35), _mat(Color(0.25, 0.45, 0.7), 0.55, 0.1))
	_box(root, "LaneZ", Vector3(0, 0.01, 0), Vector3(HALL_HALF_X * 1.35, 0.015, 0.22), _mat(Color(0.7, 0.4, 0.22), 0.55, 0.1))
	# Deck plate seams
	var seam := _mat(Color(0.14, 0.16, 0.2), 0.85, 0.15)
	for x in [-16.0, -8.0, 8.0, 16.0]:
		_box(root, "SeamX", Vector3(x, 0.005, 0), Vector3(0.06, 0.01, HALL_HALF_Z * 1.8), seam)
	for z in [-12.0, -4.0, 4.0, 12.0]:
		_box(root, "SeamZ", Vector3(0, 0.005, z), Vector3(HALL_HALF_X * 1.8, 0.01, 0.06), seam)
	# Walls: lower band + upper band (door gaps); taller stack under glass ribbon.
	var split := 4.5
	_wall_ring(root, "WallLow", wall_low, 0.0, split)
	_wall_ring(root, "WallHi", wall_hi, split, 4.0)  ## ends ~8.5m; glass ribbon to ceiling
	_place_wall_energy_ribs(root)
	# Ceiling rim with two open skylight bays (stars visible looking up)
	var y_c := CEILING_Y
	var span_x := HALL_HALF_X * 2.0 + 1.0
	var span_z := HALL_HALF_Z * 2.0 + 1.0
	_box(root, "CeilN", Vector3(0, y_c, -hz_edge(span_z)), Vector3(span_x, 0.4, 4.0), ceil_mat)
	_box(root, "CeilS", Vector3(0, y_c, hz_edge(span_z)), Vector3(span_x, 0.4, 4.0), ceil_mat)
	_box(root, "CeilW", Vector3(-hx_edge(span_x), y_c, 0), Vector3(4.0, 0.4, span_z - 8.0), ceil_mat)
	_box(root, "CeilE", Vector3(hx_edge(span_x), y_c, 0), Vector3(4.0, 0.4, span_z - 8.0), ceil_mat)
	_box(root, "CeilMid", Vector3(0, y_c, 0), Vector3(3.0, 0.35, span_z - 8.0), ceil_mat)
	# Cyan gantry LEDs
	var led := _emissive(Color(0.4, 0.7, 0.85), CYAN, 1.0)
	for sx in [-12.0, -4.0, 4.0, 12.0]:
		_box(root, "Led", Vector3(sx, CEILING_Y - 0.35, 0), Vector3(0.7, 0.08, HALL_HALF_Z * 1.5), led)


func _place_wall_energy_ribs(root: Node3D) -> void:
	"""Vertical cyan panel ribs on interior walls — breaks flat warehouse look."""
	var rib := _mat(Color(0.15, 0.18, 0.22), 0.6, 0.4)
	var glow := _emissive(Color(0.12, 0.35, 0.45), CYAN, 0.85)
	var hx := HALL_HALF_X - 0.2
	var hz := HALL_HALF_Z - 0.2
	for x in [-18.0, -10.0, 10.0, 18.0]:
		_box(root, "RibN", Vector3(x, 4.2, -hz), Vector3(0.35, 7.5, 0.2), rib)
		_box(root, "RibNGlow", Vector3(x, 4.2, -hz + 0.12), Vector3(0.12, 6.5, 0.08), glow)
		_box(root, "RibS", Vector3(x, 4.2, hz), Vector3(0.35, 7.5, 0.2), rib)
		_box(root, "RibSGlow", Vector3(x, 4.2, hz - 0.12), Vector3(0.12, 6.5, 0.08), glow)
	for z in [-14.0, -6.0, 6.0, 14.0]:
		_box(root, "RibW", Vector3(-hx, 4.2, z), Vector3(0.2, 7.5, 0.35), rib)
		_box(root, "RibWGlow", Vector3(-hx + 0.12, 4.2, z), Vector3(0.08, 6.5, 0.12), glow)
		_box(root, "RibE", Vector3(hx, 4.2, z), Vector3(0.2, 7.5, 0.35), rib)
		_box(root, "RibEGlow", Vector3(hx - 0.12, 4.2, z), Vector3(0.08, 6.5, 0.12), glow)


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


func _sphere(parent: Node3D, mesh_name: String, pos: Vector3, radius: float, mat: Material) -> void:
	"""Decorative sphere (radar / tank / glow)."""
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 24
	sm.rings = 12
	mi.mesh = sm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func _cylinder(
	parent: Node3D, mesh_name: String, pos: Vector3, radius: float, height: float, mat: Material
) -> void:
	"""Upright cylinder pillar."""
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 20
	mi.mesh = cm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func _capsule(
	parent: Node3D,
	mesh_name: String,
	pos: Vector3,
	radius: float,
	height: float,
	mat: Material,
	rot_deg: Vector3 = Vector3.ZERO,
) -> void:
	"""Soft capsule link (dock stub tips)."""
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = height
	cap.radial_segments = 16
	mi.mesh = cap
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg


func _torus(
	parent: Node3D,
	mesh_name: String,
	pos: Vector3,
	ring_r: float,
	tube_r: float,
	mat: Material,
	rot_deg: Vector3 = Vector3.ZERO,
) -> void:
	"""Ring / halo / arch accent (ring_r ≈ centerline, tube_r ≈ thickness/2)."""
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	var tm := TorusMesh.new()
	tm.outer_radius = ring_r + tube_r
	tm.inner_radius = maxf(0.05, ring_r - tube_r)
	tm.rings = 48
	tm.ring_segments = 16
	mi.mesh = tm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot_deg


func _mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	"""Simple opaque material."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _emissive(albedo: Color, emit: Color, energy: float) -> StandardMaterial3D:
	"""Matte surface with cyan-style emission (port energy panels)."""
	var mat := _mat(albedo, 0.45, 0.25)
	mat.emission_enabled = true
	mat.emission = emit
	mat.emission_energy_multiplier = energy
	return mat


func _place_mezzanine(root: Node3D) -> void:
	"""Half-floor lounge + static elevator shaft (preview only)."""
	var deck := _mat(Color(0.38, 0.42, 0.48), 0.65, 0.12)
	var beam := _mat(Color(0.28, 0.32, 0.38), 0.7, 0.2)
	var rail := _mat(Color(0.55, 0.6, 0.68), 0.45, 0.35)
	var accent := _emissive(Color(0.2, 0.4, 0.5), CYAN, 0.75)
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
	tag.text = MWi18n.t("L2 母港观景廊", "L2 Mothership Lounge")
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
	label.text = MWi18n.t("电梯 · 按 F 乘梯", "Elevator · F to ride")
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
	gal.text = MWi18n.t("展厅翼", "Gallery")
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
	cls.text = MWi18n.t("教室翼", "Classroom")
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
	lab.text = MWi18n.t("设计室 · 卡片通道", "Design Lab · Type B")
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
	lab.text = MWi18n.t("边缘任务坞", "Edge Dock · Type C")
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
	lab.text = MWi18n.t("竞技场门", "Arena Gate")
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
		MWi18n.t("A 仿真工坊", "A Workshop"),
		Color(1.0, 0.7, 0.3),
	)
	_ensure_marker(
		world, "DoorCity",
		Vector3(-HALL_HALF_X + 1.5, 1.6, 0.0),
		MWi18n.t("B 机甲训练场", "B Training Yard"),
		Color(0.4, 0.85, 1.0),
	)
	_ensure_marker(
		world, "DoorStubC",
		Vector3(0.0, 1.6, -HALL_HALF_Z + 1.5),
		MWi18n.t("C 设计室", "C Design Lab"),
		Color(0.75, 0.85, 0.95),
	)
	_ensure_marker(
		world, "DoorStubD",
		Vector3(-HALL_HALF_X + 1.8, 1.6, -10.0),
		MWi18n.t("D 边缘任务坞", "D Edge Dock"),
		Color(0.65, 0.75, 0.7),
	)
	_ensure_marker(
		world, "DoorStubE",
		Vector3(0.0, 1.6, HALL_HALF_Z - 1.5),
		MWi18n.t("E 竞技场门", "E Arena Gate"),
		Color(1.0, 0.5, 0.3),
	)


func _place_wing_labels(root: Node3D) -> void:
	"""Floor-facing wing tags for three exit types (docs/24)."""
	_zone_label(root, "ZoneA", Vector3(HALL_HALF_X - 5.0, 0.05, 4.0), MWi18n.t("本仓关卡", "Native"), Color(1.0, 0.65, 0.3))
	_zone_label(root, "ZoneB", Vector3(0.0, 0.05, -HALL_HALF_Z + 5.0), MWi18n.t("卡片通道", "PMS Cards"), Color(0.7, 0.85, 1.0))
	_zone_label(root, "ZoneC", Vector3(-HALL_HALF_X + 5.0, 0.05, -6.0), MWi18n.t("边缘入口", "Edge"), Color(0.55, 0.85, 0.7))
	_zone_label(root, "ZoneCore", Vector3(0.0, 0.05, 2.0), MWi18n.t("母港核心", "Hangar Core"), Color(0.85, 0.9, 1.0))


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
	"""Door route label (locale-aware; hide legacy bilingual Label3Ds)."""
	var n := world.get_node_or_null(marker_name) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = marker_name
		world.add_child(n)
	n.position = pos
	var label := n.get_node_or_null("DoorLabel") as Label3D
	if label == null:
		for child in n.get_children():
			if child is Label3D:
				label = child as Label3D
				break
	if label == null:
		label = Label3D.new()
		label.name = "DoorLabel"
		n.add_child(label)
		label.position = Vector3(0, 2.2, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 56
		label.outline_size = 8
		label.pixel_size = 0.01
	for child in n.get_children():
		if child is Label3D and child != label:
			(child as Label3D).visible = false
	label.visible = true
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
