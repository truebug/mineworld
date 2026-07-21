## Hub life: furniture, humanoid NPCs, interactive props (viewer-only).
## Props hug the walls; center stays clear for player traffic.
extends Node3D

const BLOCKY_DIR := "res://assets/kenney_blocky/"
const FACTORY_DIR := "res://assets/kenney_factory/"
## Keep ~1.5m inside hub_dress HALL_HALF (24×20).
const WALL_X := 22.5
const WALL_Z := 18.5
const INTERACT_DIST := 3.6
const NPC_SCALE := 0.36

## [{node, id, prompt, line}]
var interactables: Array = []


func _ready() -> void:
	"""Spawn lounge furniture + NPCs + interactive stations."""
	call_deferred("_build")


func _build() -> void:
	"""Assemble hub life dressing along walls."""
	_place_furniture()
	_place_stations()
	_place_npcs()
	print("[MW] hub life: wall props + %d interactables" % interactables.size())


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
	"""Kiosks flush to walls + E4 exhibit cabinets."""
	_station(
		"kiosk_welcome",
		Vector3(-6.0, 0, WALL_Z - 1.0),
		180.0,
		MWi18n.t("F · 导览台", "F · Welcome"),
		MWi18n.t(
			"欢迎来到母港。\n东橙 A 工坊 · 西蓝 B 训练 · 北 C 卡片 · 西偏北 D 边缘 · 南 E 竞技\n按 V 切换相机。",
			"Welcome to Hangar Core.\nA Workshop · B Training · C Cards · D Edge · E Arena.\nPress V for camera."
		),
		Color(0.3, 0.7, 1.0),
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
	"""E4: tall wall boards from exhibits.v0.json — F opens external Space URL."""
	var exhibits := _load_exhibits()
	# North wing (TYPE B) — large screens flank the Design / gallery bay.
	var slots: Array = [
		{"pos": Vector3(-14.5, 0, -WALL_Z + 1.35), "yaw": 0.0},
		{"pos": Vector3(14.5, 0, -WALL_Z + 1.35), "yaw": 0.0},
	]
	var i := 0
	for ex in exhibits:
		if typeof(ex) != TYPE_DICTIONARY:
			continue
		if i >= slots.size():
			break
		var slot: Dictionary = slots[i]
		i += 1
		var eid := str(ex.get("id", "exhibit_%d" % i))
		var title := MWi18n.t(
			str(ex.get("title_zh", ex.get("title", "展柜"))),
			str(ex.get("title_en", ex.get("title", "Exhibit"))),
		)
		var url := str(ex.get("url", "")).strip_edges()
		var space_id := str(ex.get("space_id", "")).strip_edges()
		var lore := MWi18n.t(
			str(ex.get("lore_zh", ex.get("lore", "外部 Space 卡片。"))),
			str(ex.get("lore_en", ex.get("lore", "External Space card."))),
		)
		var line := MWi18n.t(
			"%s\n%s\n（按 F 打开卡片 · space_id=%s）",
			"%s\n%s\n(F opens card · space_id=%s)",
		) % [title, lore, space_id if space_id != "" else "—"]
		_exhibit_board(
			eid,
			slot["pos"],
			float(slot["yaw"]),
			MWi18n.t("F · %s", "F · %s") % title,
			line,
			Color(0.45, 0.9, 0.75),
			url,
			title,
			space_id,
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
) -> void:
	"""Tall PMS card info screen (much larger than kiosk pedestals)."""
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
	# Plinth
	_box_child(root, Vector3(0, 0.2, 0.15), Vector3(3.2, 0.4, 1.2), body)
	# Tall frame + screen face (~4.5 m high overall)
	_box_child(root, Vector3(0, 2.6, 0.0), Vector3(3.0, 4.6, 0.45), body)
	_box_child(root, Vector3(0, 2.7, 0.28), Vector3(2.55, 4.0, 0.1), glow)
	_box_child(root, Vector3(0, 4.85, 0.3), Vector3(2.4, 0.14, 0.14), trim)
	_box_child(root, Vector3(0, 0.55, 0.32), Vector3(2.4, 0.1, 0.12), glow)
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
	"""H10: gallery / classroom corridor pads (lore; exhibits hold real URLs)."""
	_station(
		"room_gallery",
		Vector3(-8.0, 0, -WALL_Z + 1.2),
		0.0,
		MWi18n.t("F · 展厅翼", "F · Gallery"),
		MWi18n.t("展厅翼 — 卡片通道。\n展柜可开 Space；无本仓仿真。", "Gallery wing — card corridor.\nExhibits open Spaces; no Hub MuJoCo."),
		Color(0.75, 0.65, 0.4),
	)
	_station(
		"room_classroom",
		Vector3(9.5, 0, -WALL_Z + 1.2),
		0.0,
		MWi18n.t("F · 教室翼", "F · Classroom"),
		MWi18n.t("教室翼 — 课件走廊。\n未绑 URL 时仅说明；真卡片用展柜。", "Classroom wing.\nStub lore until Space URL linked."),
		Color(0.45, 0.7, 0.85),
	)


func _place_arena_station() -> void:
	"""H11: Arena gate pad — F cycles 1v1/party stub (no join / no PMS URL)."""
	_station(
		"arena_gate",
		Vector3(0.0, 0, WALL_Z - 2.4),
		180.0,
		MWi18n.t("F · 竞技场门", "F · Arena Gate"),
		MWi18n.t("竞技场门 — 排名对战（权威后置）。\n按 F：1v1 ↔ 组队 · 切换排队。", "Arena Gate — ranked bouts later.\nF: cycle 1v1/party · looking."),
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
	"""Small standing greeters at walls near doors (no wander)."""
	_npc(
		"maya",
		MWi18n.t("玛雅", "Maya"),
		"character-a.glb", Vector3(-4.5, 0, WALL_Z - 1.3), 180.0, Color(1.0, 0.85, 0.4),
		MWi18n.t("F · 与玛雅交谈", "F · Talk to Maya"),
		MWi18n.t("玛雅: 橙门工坊 · 蓝门训练。按 V 切相机。", "Maya: Orange Workshop, blue Training. V = camera."),
	)
	_npc(
		"rex",
		MWi18n.t("雷克斯", "Rex"),
		"character-b.glb", Vector3(WALL_X - 1.3, 0, 2.2), -90.0, Color(1.0, 0.55, 0.25),
		MWi18n.t("F · 与雷克斯交谈", "F · Talk to Rex"),
		MWi18n.t("雷克斯: 工坊在橙门。把推车完整带回来！", "Rex: Workshop through the orange gate."),
	)
	_npc(
		"jin",
		MWi18n.t("金", "Jin"),
		"character-c.glb", Vector3(-WALL_X + 1.3, 0, -2.2), 90.0, Color(0.45, 0.8, 1.0),
		MWi18n.t("F · 与金交谈", "F · Talk to Jin"),
		MWi18n.t("金: 蓝门是训练场。进街区前先热身。", "Jin: Blue door = Training yard."),
	)
	_npc(
		"pip",
		MWi18n.t("皮普", "Pip"),
		"character-d.glb", Vector3(4.5, 0, -WALL_Z + 1.3), 0.0, Color(0.7, 0.9, 0.5),
		MWi18n.t("F · 与皮普交谈", "F · Talk to Pip"),
		MWi18n.t("皮普: 我在看人来人往。朋友进厅记得打招呼！", "Pip: People-watching — say hi when friends join."),
	)


func _npc(
	npc_id: String,
	display: String,
	asset: String,
	pos: Vector3,
	face_yaw_deg: float,
	accent: Color,
	prompt: String,
	line: String,
) -> void:
	"""Spawn a scaled blocky character planted on the floor."""
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
	tag.text = display
	tag.font_size = 36
	tag.outline_size = 6
	tag.pixel_size = 0.01
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = accent
	root.add_child(tag)
	tag.position = Vector3(0, 1.55, 0)
	var hint := Label3D.new()
	MWFonts.apply_label3d(hint)
	hint.text = prompt
	hint.font_size = 24
	hint.outline_size = 4
	hint.pixel_size = 0.009
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.modulate = Color(0.9, 0.9, 0.95, 0.85)
	root.add_child(hint)
	hint.position = Vector3(0, 1.3, 0)
	interactables.append({
		"node": root,
		"id": "npc_%s" % npc_id,
		"prompt": prompt,
		"line": line,
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
	# Name tags sit just above scaled head (~1.1m after plant).
	for child in root.get_children():
		if child is Label3D:
			var lbl := child as Label3D
			if lbl.text.begins_with("F -"):
				lbl.position.y = 1.15
			else:
				lbl.position.y = 1.35


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
