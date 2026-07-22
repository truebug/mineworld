## Hub life: furniture, humanoid NPCs, interactive props (viewer-only).
## Mid-ring welcome + wall props; center has wayfinding beacon (docs/24 first-look).
extends Node3D

const BLOCKY_DIR := "res://assets/kenney_blocky/"
const FACTORY_DIR := "res://assets/kenney_factory/"
## Keep ~1.5m inside hub_dress HALL_HALF (24×20).
const WALL_X := 22.5
const WALL_Z := 18.5
const INTERACT_DIST := 3.6
const NPC_SCALE := 0.36
const BEACON_POS := Vector3(5.0, 0.0, 0.0)

## [{node, id, prompt, line}]
var interactables: Array = []


func _ready() -> void:
	"""Spawn lounge furniture + NPCs + interactive stations."""
	call_deferred("_build")


func _build() -> void:
	"""Assemble hub life: mid-ring focus + walls + ambient life."""
	_place_furniture()
	_place_mid_ring()
	_place_beacon()
	_place_stations()
	_place_npcs()
	_place_patrols()
	_start_ambient_hum()
	print("[MW] hub life: mid-ring + %d interactables" % interactables.size())


func nearest_interact(player_pos: Vector3) -> Dictionary:
	"""Return closest interactable within range (XZ planar), or {}."""
	var best: Dictionary = {}
	var best_d := INTERACT_DIST
	var p := Vector2(player_pos.x, player_pos.z)
	for item in interactables:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var n: Node3D = item.get("node") as Node3D
		if n == null:
			continue
		var gp := n.global_position
		var d := p.distance_to(Vector2(gp.x, gp.z))
		if d < best_d:
			best_d = d
			best = item
	return best


func _place_furniture() -> void:
	"""Benches / planters flush to walls (center clear)."""
	var wood := _mat(Color(0.45, 0.32, 0.22), 0.8, 0.0)
	var cushion := _mat(Color(0.25, 0.45, 0.55), 0.7, 0.0)
	var plant_pot := _mat(Color(0.35, 0.38, 0.4), 0.75, 0.05)
	var leaf := _mat(Color(0.28, 0.55, 0.32), 0.85, 0.0)
	var rug := _mat(Color(0.35, 0.28, 0.4), 0.9, 0.0)
	# South wall (+Z)
	_box(Vector3(-7, 0.02, WALL_Z - 1.2), Vector3(4.5, 0.04, 2.2), rug)
	_box(Vector3(7, 0.02, WALL_Z - 1.2), Vector3(4.5, 0.04, 2.2), rug)
	_bench(Vector3(-7, 0, WALL_Z - 0.9), 0.0, wood, cushion)
	_bench(Vector3(7, 0, WALL_Z - 0.9), 0.0, wood, cushion)
	_planter(Vector3(-11.5, 0, WALL_Z - 0.8), plant_pot, leaf)
	_planter(Vector3(11.5, 0, WALL_Z - 0.8), plant_pot, leaf)
	# North wall (−Z), leave door bay at x≈0
	_bench(Vector3(-12, 0, -WALL_Z + 0.9), 180.0, wood, cushion)
	_bench(Vector3(12, 0, -WALL_Z + 0.9), 180.0, wood, cushion)
	_planter(Vector3(-15, 0, -WALL_Z + 0.8), plant_pot, leaf)
	_planter(Vector3(15, 0, -WALL_Z + 0.8), plant_pot, leaf)
	# West / East walls, clear of door z≈0
	_bench(Vector3(-WALL_X + 0.9, 0, 8), 90.0, wood, cushion)
	_bench(Vector3(WALL_X - 0.9, 0, 8), -90.0, wood, cushion)
	_bench(Vector3(-WALL_X + 0.9, 0, -8), 90.0, wood, cushion)
	_bench(Vector3(WALL_X - 0.9, 0, -8), -90.0, wood, cushion)
	_planter(Vector3(-WALL_X + 0.8, 0, 11), plant_pot, leaf)
	_planter(Vector3(WALL_X - 0.8, 0, 11), plant_pot, leaf)
	# Corner crates
	_spawn_factory("box-small.glb", -WALL_X + 1.2, -WALL_Z + 1.2, 15.0, 1.0)
	_spawn_factory("box-large.glb", WALL_X - 1.5, -WALL_Z + 1.5, -20.0, 1.0)
	_spawn_factory("cone.glb", -WALL_X + 1.0, WALL_Z - 2.5, 0.0, 1.0)
	# SE reserved for elevator — cone on SW instead
	_spawn_factory("cone.glb", -WALL_X + 3.0, WALL_Z - 1.2, 0.0, 1.0)


func _bench(pos: Vector3, yaw_deg: float, wood: Material, cushion: Material) -> void:
	"""Simple seat: board + back + cushions."""
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	_box_child(root, Vector3(0, 0.28, 0), Vector3(2.2, 0.12, 0.7), wood)
	_box_child(root, Vector3(0, 0.7, -0.28), Vector3(2.2, 0.7, 0.12), wood)
	_box_child(root, Vector3(-0.55, 0.38, 0.05), Vector3(0.9, 0.1, 0.55), cushion)
	_box_child(root, Vector3(0.55, 0.38, 0.05), Vector3(0.9, 0.1, 0.55), cushion)


func _planter(pos: Vector3, pot: Material, leaf: Material) -> void:
	"""Box planter with leafy blob."""
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	_box_child(root, Vector3(0, 0.25, 0), Vector3(0.7, 0.5, 0.7), pot)
	_box_child(root, Vector3(0, 0.7, 0), Vector3(0.55, 0.45, 0.55), leaf)
	_box_child(root, Vector3(0.15, 0.95, 0.1), Vector3(0.35, 0.35, 0.35), leaf)


func _place_stations() -> void:
	"""Kiosks: welcome near beacon; others flush to walls + E4 exhibits."""
	_station(
		"kiosk_welcome",
		Vector3(3.2, 0, 3.2),
		-35.0,
		MWi18n.t("F · 导览台", "F · Welcome"),
		MWi18n.t(
			"欢迎来到机甲学院母港。\n东橙 A 工坊 · 西蓝 B 训练 · 北 C 卡片 · 南 E 竞技(建设中) · 东南 R 赛车\n跟随地面灯带前往。",
			"Welcome to Mech Academy Hangar.\nA Workshop · B Training · C Cards · E Arena(WIP) · SE R Race.\nFollow the floor lights."
		),
		Color(0.95, 0.7, 0.35),
	)
	_station(
		"board_party",
		Vector3(-WALL_X + 1.0, 0, 5.5),
		90.0,
		MWi18n.t("F · 组队板", "F · Party board"),
		MWi18n.t("组队板 — 按 F 发布/清除招募。", "Party board — F to toggle Looking for crew."),
		Color(1.0, 0.7, 0.3),
	)
	_station(
		"vendor",
		Vector3(WALL_X - 1.0, 0, 5.5),
		-90.0,
		MWi18n.t("F · 商贩", "F · Vendor"),
		MWi18n.t("商贩 — 按 F 循环机甲配色。", "Vendor — F to cycle suit accent."),
		Color(0.9, 0.45, 0.85),
	)
	_station(
		"pad_photo",
		Vector3(5.0, 0, -WALL_Z + 1.2),
		0.0,
		MWi18n.t("F · 拍照点", "F · Photo pad"),
		MWi18n.t("拍照点 — 未来高光回放占位。", "Photo pad — highlight reel later."),
		Color(0.5, 0.9, 0.6),
	)
	_place_exhibits()
	_place_room_shell_stations()
	_place_arena_station()
	_place_cd_stations()
	_spawn_factory("screen-panel-wide.glb", 0.0, WALL_Z - 0.6, 180.0, 2.2)
	_spawn_factory("machine.glb", WALL_X - 1.2, 9.0, -90.0, 1.0)
	_spawn_factory("structure-medium.glb", -WALL_X + 1.2, 9.0, 90.0, 1.0)
	_spawn_factory("hopper-round.glb", WALL_X - 1.3, -9.0, 0.0, 1.0)
	_spawn_factory("warning-orange.glb", -WALL_X + 1.3, -9.0, 0.0, 1.0)
	# Elevator call panel (H8 ride; matches hub_dress ELEV_X/Z ≈ 16/15)
	_station(
		"elevator",
		Vector3(16.0, 0, 14.2),
		180.0,
		MWi18n.t("F · 电梯", "F · Elevator"),
		MWi18n.t("电梯 — 按 F 在一层与 L2 观景廊之间切换。", "Elevator — F to ride L1 ↔ L2."),
		Color(0.4, 0.85, 1.0),
	)
	_station(
		"elevator",
		Vector3(16.0, 8.5, 14.2),
		180.0,
		MWi18n.t("F · 电梯", "F · Elevator"),
		MWi18n.t("电梯 — 按 F 返回母港一层。", "Elevator — F to return to hangar floor."),
		Color(0.4, 0.85, 1.0),
	)


func _place_cd_stations() -> void:
	"""H7c: Design (C) + Edge Dock (D) pads — F cycles stub status (no join / no edge)."""
	_station(
		"design_lab",
		Vector3(0.0, 0, -WALL_Z + 2.2),
		0.0,
		MWi18n.t("F · 设计室", "F · Design Lab"),
		MWi18n.t("设计室 — 卡片通道。\n按 F 查看状态（编辑器后置）。", "Design Lab — card wing.\nF for stub status."),
		Color(0.75, 0.85, 0.98),
	)
	_station(
		"edge_dock",
		Vector3(-WALL_X + 2.2, 0, -10.0),
		90.0,
		MWi18n.t("F · 边缘坞", "F · Edge Dock"),
		MWi18n.t("边缘任务坞。\n按 F 查看链路状态（真机后置）。", "Edge Dock.\nF for link stub."),
		Color(0.5, 0.9, 0.75),
	)


func _place_exhibits() -> void:
	"""E5d: north-wing boards grouped by role (classroom / gallery / lab / foresight)."""
	var exhibits := _load_exhibits()
	var by_role: Dictionary = {
		"classroom": [],
		"gallery": [],
		"lab": [],
		"foresight": [],
	}
	for ex in exhibits:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		var role := str(ex.get("role", "gallery")).strip_edges()
		if not by_role.has(role):
			role = "gallery"
		(by_role[role] as Array).append(ex)

	# Classroom wing (east-north): keep clear of NE corner clutter.
	_mount_role_row(
		by_role["classroom"] as Array,
		4.5,
		15.5,
		-WALL_Z + 1.35,
		0.0,
		Color(0.42, 0.72, 0.95),
		0.52,
	)
	# Gallery wing (west-north): keep clear of NW corner / door B bay.
	_mount_role_row(
		by_role["gallery"] as Array,
		-4.5,
		-15.5,
		-WALL_Z + 1.35,
		0.0,
		Color(0.88, 0.68, 0.32),
		0.55,
	)
	# Foresight + lab on west wall, inset slightly so boards sit in front of wall.
	_mount_role_row(
		by_role["foresight"] as Array,
		-WALL_X + 2.0,
		-WALL_X + 2.0,
		-16.0,
		90.0,
		Color(0.95, 0.55, 0.28),
		0.5,
		true,
	)
	_mount_role_row(
		by_role["lab"] as Array,
		-WALL_X + 2.0,
		-WALL_X + 2.0,
		-12.0,
		90.0,
		Color(0.4, 0.88, 0.62),
		0.5,
		true,
	)


func _mount_role_row(
	items: Array,
	x0: float,
	x1: float,
	z: float,
	yaw: float,
	accent: Color,
	board_scale: float,
	along_z: bool = false,
) -> void:
	"""Place exhibit boards evenly between x0..x1 (or along Z when along_z)."""
	var n := items.size()
	if n <= 0:
		return
	for i in range(n):
		var ex: Dictionary = items[i]
		var t := 0.0 if n == 1 else float(i) / float(n - 1)
		var pos: Vector3
		if along_z:
			# x0/x1 unused as range; x fixed; z spreads from z toward less-negative.
			var z1 := z + float(n - 1) * 2.4
			pos = Vector3(x0, 0.0, lerpf(z, z1, t))
		else:
			pos = Vector3(lerpf(x0, x1, t), 0.0, z)
		var eid := str(ex.get("id", "exhibit_%d" % i))
		var title := MWi18n.t(
			str(ex.get("title_zh", ex.get("title", "展柜"))),
			str(ex.get("title_en", ex.get("title", "Exhibit"))),
		)
		var url := str(ex.get("url", "")).strip_edges()
		var space_id := str(ex.get("space_id", "")).strip_edges()
		var role := str(ex.get("role", "")).strip_edges()
		var lore := MWi18n.t(
			str(ex.get("lore_zh", ex.get("lore", "外部 Space 卡片。"))),
			str(ex.get("lore_en", ex.get("lore", "External Space card."))),
		)
		var line := MWi18n.t(
			"[%s] %s\n%s\n（按 F 打开 · space_id=%s）",
			"[%s] %s\n%s\n(F opens · space_id=%s)",
		) % [role if role != "" else "card", title, lore, space_id if space_id != "" else "—"]
		_exhibit_board(
			eid,
			pos,
			yaw,
			MWi18n.t("F · %s", "F · %s") % title,
			line,
			accent,
			url,
			title,
			space_id,
			board_scale,
		)


func _exhibit_board(
	id: String,
	pos: Vector3,
	yaw_deg: float,
	prompt: String,
	line: String,
	accent: Color,
	url: String = "",
	title: String = "",
	space_id: String = "",
	board_scale: float = 1.0,
) -> void:
	"""Tall PMS card info screen (scale down for dense north-wing rows)."""
	var s := clampf(board_scale, 0.35, 1.0)
	var root := Node3D.new()
	root.name = "Exhibit_%s" % id
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	var body := _mat(Color(0.18, 0.22, 0.28), 0.5, 0.3)
	var trim := _mat(Color(0.35, 0.42, 0.5), 0.45, 0.25)
	var glow := _mat(accent, 0.35, 0.15)
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 1.8
	_box_child(root, Vector3(0, 0.2 * s, 0.15 * s), Vector3(3.2 * s, 0.4 * s, 1.2 * s), body)
	_box_child(root, Vector3(0, 2.6 * s, 0.0), Vector3(3.0 * s, 4.6 * s, 0.45 * s), body)
	_box_child(root, Vector3(0, 2.7 * s, 0.28 * s), Vector3(2.55 * s, 4.0 * s, 0.1 * s), glow)
	_box_child(root, Vector3(0, 4.85 * s, 0.3 * s), Vector3(2.4 * s, 0.14 * s, 0.14 * s), trim)
	_box_child(root, Vector3(0, 0.55 * s, 0.32 * s), Vector3(2.4 * s, 0.1 * s, 0.12 * s), glow)
	# Short title plate above plinth (readable at distance).
	var tag := Label3D.new()
	tag.name = "Title"
	tag.text = title if title != "" else id
	tag.font_size = int(42.0 * s)
	tag.modulate = accent.lightened(0.25)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, 5.2 * s, 0.35 * s)
	MWFonts.apply_label3d(tag)
	root.add_child(tag)
	interactables.append({
		"node": root,
		"id": id,
		"prompt": prompt,
		"line": line,
		"url": url,
		"title": title,
		"space_id": space_id,
	})

func _place_room_shell_stations() -> void:
	"""H10: gallery / classroom corridor pads — point at role-grouped E5d boards."""
	var counts := _exhibit_role_counts()
	_station(
		"room_gallery",
		Vector3(-8.0, 0, -WALL_Z + 1.2),
		0.0,
		MWi18n.t("F · 展厅翼", "F · Gallery"),
		MWi18n.t(
			"展厅翼 — 场景/厨房展柜 ×%d（西墙前瞻 ×%d）。\n走近橙屏按 F 开 Space。",
			"Gallery — scene/kitchen boards ×%d (west foresight ×%d).\nApproach orange screen · F opens Space."
		) % [int(counts.get("gallery", 0)), int(counts.get("foresight", 0))],
		Color(0.75, 0.65, 0.4),
	)
	_station(
		"room_classroom",
		Vector3(9.5, 0, -WALL_Z + 1.2),
		0.0,
		MWi18n.t("F · 教室翼", "F · Classroom"),
		MWi18n.t(
			"教室翼 — 课程卡 ×%d（实验室西墙 ×%d）。\n走近蓝屏按 F 开课件 Space。",
			"Classroom — course cards ×%d (lab west wall ×%d).\nApproach blue screen · F opens Space."
		) % [int(counts.get("classroom", 0)), int(counts.get("lab", 0))],
		Color(0.45, 0.7, 0.85),
	)


func _exhibit_role_counts() -> Dictionary:
	"""Count curated exhibits by role for wing lore."""
	var out := {"classroom": 0, "gallery": 0, "lab": 0, "foresight": 0}
	for ex in _load_exhibits():
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		var role := str(ex.get("role", "gallery"))
		if out.has(role):
			out[role] = int(out[role]) + 1
	return out


func _place_arena_station() -> void:
	"""H11: Arena gate pad — F cycles 1v1/party stub (no join / no PMS URL)."""
	_station(
		"arena_gate",
		Vector3(0.0, 0, WALL_Z - 2.4),
		180.0,
		MWi18n.t("F · 竞技场门", "F · Arena Gate"),
		MWi18n.t("竞技场门 — 建设中：机甲格斗（1v1 / 团队对战）规划中。\n按 F：1v1 ↔ 组队 · 切换模式预览。", "Arena Gate — under construction: mech combat (1v1 / team) planned.\nF: cycle 1v1/party · preview modes."),
		Color(1.0, 0.45, 0.28),
	)


func _load_exhibits() -> Array:
	"""Load E5 exhibit list from packed JSON (fallback: empty)."""
	var path := "res://data/exhibits.v0.json"
	if not FileAccess.file_exists(path):
		push_warning("[MW] exhibits: missing %s" % path)
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var arr: Variant = (parsed as Dictionary).get("exhibits", [])
	return arr if typeof(arr) == TYPE_ARRAY else []


func _station(
	id: String,
	pos: Vector3,
	yaw_deg: float,
	prompt: String,
	line: String,
	accent: Color,
	url: String = "",
	title: String = "",
	space_id: String = "",
) -> void:
	"""Pedestal + glowing panel + prompt label; optional external url (E4)."""
	var root := Node3D.new()
	root.name = "Station_%s" % id
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	var body := _mat(Color(0.22, 0.26, 0.32), 0.55, 0.25)
	var glow := _mat(accent, 0.4, 0.1)
	glow.emission_enabled = true
	glow.emission = accent
	glow.emission_energy_multiplier = 1.4
	_box_child(root, Vector3(0, 0.5, 0), Vector3(1.1, 1.0, 0.7), body)
	_box_child(root, Vector3(0, 1.35, 0.2), Vector3(0.9, 0.7, 0.08), glow)
	# No floating "F · …" Label3D — HUD tips show prompt when near (declutter).
	interactables.append({
		"node": root,
		"id": id,
		"prompt": prompt,
		"line": line,
		"url": url,
		"title": title,
		"space_id": space_id,
	})


func _place_npcs() -> void:
	"""Greeters on mid-ring: beacon + A/B approaches (not all on walls)."""
	_npc(
		"maya",
		MWi18n.t("玛雅", "Maya"),
		"character-a.glb", Vector3(5.8, 0, 2.4), -120.0, Color(1.0, 0.85, 0.4),
		MWi18n.t("F · 与玛雅交谈", "F · Talk to Maya"),
		[
			MWi18n.t("跟橙灯带去工坊~", "Follow orange lights to Workshop~"),
			MWi18n.t("蓝灯带 → 训练场。", "Blue lights → Training yard."),
			MWi18n.t("新人？先看中央碑。", "New here? Check the central board."),
		],
		0.0,
	)
	_npc(
		"rex",
		MWi18n.t("雷克斯", "Rex"),
		"character-b.glb", Vector3(17.5, 0, 2.4), -90.0, Color(1.0, 0.55, 0.25),
		MWi18n.t("F · 与雷克斯交谈", "F · Talk to Rex"),
		[
			MWi18n.t("橙门工坊就在前面！", "Orange gate Workshop ahead!"),
			MWi18n.t("把推车完整带回来。", "Bring the cart back intact."),
			MWi18n.t("臂爪任务，慢慢来。", "Arm/claw tasks — take it slow."),
		],
		1.1,
	)
	_npc(
		"jin",
		MWi18n.t("金", "Jin"),
		"character-c.glb", Vector3(-17.5, 0, 2.2), 90.0, Color(0.45, 0.8, 1.0),
		MWi18n.t("F · 与金交谈", "F · Talk to Jin"),
		[
			MWi18n.t("蓝门是训练场。", "Blue door = Training yard."),
			MWi18n.t("进街区前先热身。", "Warm up before the blocks."),
			MWi18n.t("别撞展柜啊。", "Don't ram the exhibits."),
		],
		2.2,
	)
	_npc(
		"pip",
		MWi18n.t("皮普", "Pip"),
		"character-d.glb", Vector3(0.0, 0, -8.0), 0.0, Color(0.7, 0.9, 0.5),
		MWi18n.t("F · 与皮普交谈", "F · Talk to Pip"),
		[
			MWi18n.t("中央碑有今日去处！", "Central board has today's routes!"),
			MWi18n.t("朋友进厅记得打招呼。", "Say hi when friends join."),
			MWi18n.t("电梯可上 L2 观景。", "Elevator goes to L2 lounge."),
		],
		3.4,
	)


func _npc(
	npc_id: String,
	display: String,
	asset: String,
	pos: Vector3,
	face_yaw_deg: float,
	accent: Color,
	prompt: String,
	lines: Array,
	bubble_offset: float = 0.0,
) -> void:
	"""Spawn a scaled blocky character with rotating speech bubble."""
	var root := Node3D.new()
	root.name = "NPC_%s" % npc_id
	add_child(root)
	root.position = pos
	root.rotation_degrees.y = face_yaw_deg
	var mesh_ok := _spawn_blocky(root, asset)
	if not mesh_ok:
		_fallback_figure(root, accent)
	else:
		call_deferred("_plant_feet", root)
	var tag := Label3D.new()
	MWFonts.apply_label3d(tag)
	tag.name = "NpcTag"
	tag.text = display
	tag.font_size = 32
	tag.outline_size = 6
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = accent
	root.add_child(tag)
	tag.position = Vector3(0, 1.42, 0)
	var bubble: Node3D = preload("res://scripts/hub_speech_bubble.gd").new()
	bubble.name = "SpeechBubble"
	root.add_child(bubble)
	bubble.position = Vector3(0, 1.92, 0)
	bubble.call("setup", lines, accent.lightened(0.2), bubble_offset)
	var talk_line := str(lines[0]) if not lines.is_empty() else display
	interactables.append({
		"node": root,
		"id": "npc_%s" % npc_id,
		"prompt": prompt,
		"line": "%s: %s" % [display, talk_line],
	})


func _spawn_blocky(parent: Node3D, asset: String) -> bool:
	"""Instance Kenney Blocky character if available."""
	var path := BLOCKY_DIR + asset
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	parent.add_child(node)
	node.name = "Mesh"
	node.scale = Vector3(NPC_SCALE, NPC_SCALE, NPC_SCALE)
	_freeze_anims(node)
	return true


func _freeze_anims(n: Node) -> void:
	"""Stop any autoplay idle so greeters stand still."""
	if n is AnimationPlayer:
		var ap := n as AnimationPlayer
		ap.active = false
		ap.stop()
	for c in n.get_children():
		_freeze_anims(c)


func _plant_feet(root: Node3D) -> void:
	"""Shift mesh so the lowest vertex sits on y=0 (fixes floating pivots)."""
	var mesh := root.get_node_or_null("Mesh") as Node3D
	if mesh == null:
		return
	var min_y := 1e9
	for mi in _all_meshes(mesh):
		var aabb: AABB = mi.get_aabb()
		var p := aabb.position
		var e := aabb.end
		var corners := [
			Vector3(p.x, p.y, p.z), Vector3(p.x, p.y, e.z),
			Vector3(e.x, p.y, p.z), Vector3(e.x, p.y, e.z),
			Vector3(p.x, e.y, p.z), Vector3(p.x, e.y, e.z),
			Vector3(e.x, e.y, p.z), Vector3(e.x, e.y, e.z),
		]
		for c in corners:
			var w: Vector3 = mi.global_transform * c
			min_y = minf(min_y, w.y)
	if min_y < 1e8:
		mesh.global_position.y -= min_y
	# Name tag / bubble sit just above scaled head after plant.
	var nametag := root.get_node_or_null("NpcTag") as Label3D
	if nametag != null:
		nametag.position.y = 1.35
	var bubble := root.get_node_or_null("SpeechBubble") as Node3D
	if bubble != null:
		bubble.position.y = 1.85


func _all_meshes(n: Node) -> Array:
	"""Collect MeshInstance3D descendants."""
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _fallback_figure(parent: Node3D, accent: Color) -> void:
	"""Procedural stand-in if GLB missing on Web."""
	var dark := accent.darkened(0.35)
	_box_child(parent, Vector3(0, 0.45, 0), Vector3(0.35, 0.55, 0.22), _mat(accent, 0.5, 0.2))
	_box_child(parent, Vector3(0, 0.9, 0), Vector3(0.26, 0.26, 0.26), _mat(accent.lightened(0.15), 0.45, 0.15))
	_box_child(parent, Vector3(0.1, 0.2, 0), Vector3(0.12, 0.35, 0.12), _mat(dark, 0.6, 0.1))
	_box_child(parent, Vector3(-0.1, 0.2, 0), Vector3(0.12, 0.35, 0.12), _mat(dark, 0.6, 0.1))


func _spawn_factory(asset: String, x: float, z: float, yaw_deg: float, s: float) -> void:
	"""Optional Kenney Factory prop."""
	var path := FACTORY_DIR + asset
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var node := packed.instantiate() as Node3D
	add_child(node)
	node.position = Vector3(x, 0.0, z)
	node.rotation_degrees.y = yaw_deg
	if s != 1.0:
		node.scale = Vector3(s, s, s)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	"""World-space box."""
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.position = pos


func _box_child(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	"""Local-space box under parent."""
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func _mat(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	"""Shared material helper."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _place_mid_ring() -> void:
	"""Planters / crates around beacon so the plaza is not empty grid."""
	var pot := _mat(Color(0.38, 0.34, 0.3), 0.75, 0.05)
	var leaf := _mat(Color(0.32, 0.58, 0.35), 0.85, 0.0)
	var rug := _mat(Color(0.4, 0.32, 0.28), 0.9, 0.0)
	_box(Vector3(5.0, 0.02, 0.0), Vector3(5.5, 0.04, 5.5), rug)
	_planter(Vector3(7.5, 0, 3.2), pot, leaf)
	_planter(Vector3(7.5, 0, -3.2), pot, leaf)
	_planter(Vector3(2.5, 0, 3.5), pot, leaf)
	_spawn_factory("cone.glb", 8.5, -2.0, 15.0, 1.0)
	_spawn_factory("box-small.glb", 3.5, -3.0, -25.0, 1.0)


func _place_beacon() -> void:
	"""Central wayfinding pillar: A Workshop / B Training (F for lore)."""
	var root := Node3D.new()
	root.name = "WayfindingBeacon"
	add_child(root)
	root.position = BEACON_POS
	var hull := _mat(Color(0.22, 0.24, 0.28), 0.45, 0.35)
	var warm := _mat(Color(1.0, 0.72, 0.35), 0.35, 0.1)
	warm.emission_enabled = true
	warm.emission = Color(1.0, 0.65, 0.25)
	warm.emission_energy_multiplier = 1.6
	var cyan := _mat(Color(0.3, 0.8, 1.0), 0.35, 0.1)
	cyan.emission_enabled = true
	cyan.emission = Color(0.25, 0.75, 1.0)
	cyan.emission_energy_multiplier = 1.4
	_box_child(root, Vector3(0, 0.15, 0), Vector3(1.6, 0.3, 1.6), hull)
	_box_child(root, Vector3(0, 1.1, 0), Vector3(0.55, 1.9, 0.55), hull)
	_box_child(root, Vector3(0, 2.25, 0), Vector3(1.1, 0.12, 1.1), warm)
	_box_child(root, Vector3(0.42, 1.2, 0), Vector3(0.08, 1.2, 0.45), warm)
	_box_child(root, Vector3(-0.42, 1.2, 0), Vector3(0.08, 1.2, 0.45), cyan)
	var ring := OmniLight3D.new()
	ring.position = Vector3(0, 2.4, 0)
	ring.light_color = Color(1.0, 0.75, 0.45)
	ring.light_energy = 1.8
	ring.omni_range = 8.0
	ring.shadow_enabled = false
	root.add_child(ring)
	var title := Label3D.new()
	MWFonts.apply_label3d(title)
	title.text = MWi18n.t("今日去处", "Today")
	title.font_size = 42
	title.outline_size = 6
	title.pixel_size = 0.011
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.modulate = Color(1.0, 0.85, 0.55)
	root.add_child(title)
	title.position = Vector3(0, 2.85, 0)
	var body := Label3D.new()
	MWFonts.apply_label3d(body)
	body.text = MWi18n.t("→ 东 A 仿真工坊\n← 西 B 机甲训练", "→ East A Workshop\n← West B Training")
	body.font_size = 32
	body.outline_size = 5
	body.pixel_size = 0.01
	body.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	body.modulate = Color(0.95, 0.95, 0.98)
	root.add_child(body)
	body.position = Vector3(0, 3.35, 0)
	interactables.append({
		"node": root,
		"id": "beacon",
		"prompt": MWi18n.t("F · 今日去处", "F · Destinations"),
		"line": MWi18n.t(
			"今日去处\n橙灯带 → A 仿真工坊（臂爪任务）\n蓝灯带 → B 机甲训练场（街区驾驶）\n走近发光门即可进入。",
			"Destinations\nOrange lights → A Workshop (arm/claw)\nBlue lights → B Training yard\nWalk into the glowing door."
		),
	})


func _place_patrols() -> void:
	"""Local walkers with dwell stops + chat bubbles (not on Gateway)."""
	_patrol(
		"scout_a",
		"character-b.glb",
		Color(1.0, 0.6, 0.3),
		[
			Vector3(8.0, 0, 6.0),
			Vector3(14.0, 0, 4.0),
			Vector3(14.0, 0, -4.0),
			Vector3(8.0, 0, -5.0),
		],
		[
			MWi18n.t("去工坊看看？", "Heading to Workshop?"),
			MWi18n.t("今日通关率不错。", "Clear rate looks good today."),
			MWi18n.t("小心门湾别卡住。", "Watch the door bays."),
		],
		0.4,
	)
	_patrol(
		"scout_b",
		"character-c.glb",
		Color(0.4, 0.75, 1.0),
		[
			Vector3(-6.0, 0, 5.0),
			Vector3(-12.0, 0, 3.0),
			Vector3(-12.0, 0, -4.0),
			Vector3(-5.0, 0, -5.5),
		],
		[
			MWi18n.t("训练场在蓝门。", "Training yard at the blue door."),
			MWi18n.t("有人组队吗？", "Anyone for a party?"),
			MWi18n.t("L2 风不错。", "Nice breeze on L2."),
		],
		1.6,
	)
	_patrol(
		"scout_c",
		"character-a.glb",
		Color(0.95, 0.8, 0.45),
		[
			Vector3(2.0, 0, 8.0),
			Vector3(-3.0, 0, 10.0),
			Vector3(4.0, 0, 12.0),
		],
		[
			MWi18n.t("东南赛车场……", "Race oval to the southeast…"),
			MWi18n.t("先热身再进关。", "Warm up before entering."),
			MWi18n.t("嗨——欢迎。", "Hey — welcome."),
		],
		2.8,
	)


func _patrol(
	npc_id: String, asset: String, accent: Color, path: Array, lines: Array = [], offset: float = 0.0
) -> void:
	"""Instance a hub_patrol_npc along waypoints with optional chat lines."""
	var node: Node3D = preload("res://scripts/hub_patrol_npc.gd").new()
	node.name = "Patrol_%s" % npc_id
	add_child(node)
	if node.has_method("setup"):
		node.call("setup", asset, path, accent, lines, offset)


func _start_ambient_hum() -> void:
	"""Low procedural hangar hum (no third-party sample; soft loop)."""
	var player := AudioStreamPlayer.new()
	player.name = "AmbientHum"
	player.volume_db = -22.0
	add_child(player)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.5
	player.stream = gen
	player.play()
	var filler: Node = preload("res://scripts/hub_ambient_hum.gd").new()
	filler.name = "AmbientHumFiller"
	filler.set("player", player)
	add_child(filler)
