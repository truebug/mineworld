## Chessroom viewer-only prop dress: Kenney furniture + PolyHaven Chinese set
## along the walls (room 32×22, tables at ±5/±4 and ±11/0 — keep centers clear).
extends Node3D

const KF := "res://assets/kenney_furniture/"
const PH := "res://assets/polyhaven_chinese_furniture/"

## {path, x, z, yaw_deg, scale} — Godot XZ plane; edges only.
const PLACEMENTS: Array = [
	# 中式茶座角（西南）
	{"path": PH + "chinese_tea_table/chinese_tea_table_1k.gltf", "x": -13.2, "z": 6.8, "yaw": 15.0, "s": 1.0},
	{"path": PH + "chinese_armchair/chinese_armchair_1k.gltf", "x": -12.4, "z": 8.0, "yaw": 205.0, "s": 1.0},
	{"path": PH + "chinese_armchair/chinese_armchair_1k.gltf", "x": -14.0, "z": 8.0, "yaw": 155.0, "s": 1.0},
	# 中式沙发 + 条案（南墙/北墙）
	{"path": PH + "chinese_sofa/chinese_sofa_1k.gltf", "x": 0.0, "z": 9.6, "yaw": 180.0, "s": 1.0},
	{"path": PH + "chinese_console_table/chinese_console_table_1k.gltf", "x": -8.0, "z": -10.0, "yaw": 0.0, "s": 1.0},
	# Kenney 家具点缀（东北角阅览角）
	{"path": KF + "bookcaseOpen.glb", "x": 13.8, "z": -9.6, "yaw": 225.0, "s": 1.2},
	{"path": KF + "loungeSofa.glb", "x": 12.8, "z": -7.2, "yaw": 235.0, "s": 1.2},
	{"path": KF + "rugRound.glb", "x": 12.0, "z": -8.4, "yaw": 0.0, "s": 1.6},
	{"path": KF + "lampRoundFloor.glb", "x": 14.6, "z": -8.0, "yaw": 0.0, "s": 1.2},
	{"path": KF + "rugRectangle.glb", "x": 0.0, "z": 8.6, "yaw": 0.0, "s": 1.8},
]


func _ready() -> void:
	call_deferred("_place_all")


func _place_all() -> void:
	var n := 0
	for d in PLACEMENTS:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if _spawn(str(d["path"]), float(d["x"]), float(d["z"]), float(d["yaw"]), float(d["s"]), n):
			n += 1
	print("[MW] chessroom dress props=%d (viewer_only)" % n)


func _spawn(path: String, x: float, z: float, yaw_deg: float, s: float, idx: int) -> bool:
	if not ResourceLoader.exists(path):
		push_warning("[MW] chessroom dress missing %s" % path)
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	node.name = "Dress_%d_%s" % [idx, path.get_file().get_basename()]
	node.transform = Transform3D(
		Basis.from_euler(Vector3(0.0, deg_to_rad(yaw_deg), 0.0)).scaled(Vector3(s, s, s)),
		Vector3(x, 0.0, z)
	)
	add_child(node)
	return true
