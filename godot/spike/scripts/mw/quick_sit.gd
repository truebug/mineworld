class_name MWQuickSit
extends Node
## Fun-Q: one-click seat helper for the chess lounge.
## Owns the free-seat pick strategy + the floating quick-sit button chrome;
## chessroom.gd keeps only dispatch glue (J key / board-open hooks).


static func build_button(parent: Node, on_pressed: Callable) -> Button:
	"""Floating bottom-right quick-sit button on its own CanvasLayer."""
	var layer := CanvasLayer.new()
	layer.layer = 10
	parent.add_child(layer)
	var btn := Button.new()
	btn.text = MWi18n.t("快速入座 (J)", "Quick sit (J)")
	var f: Font = MWFonts.font() if MWFonts != null else null
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2(-230, -64)
	btn.size = Vector2(200, 44)
	btn.pressed.connect(on_pressed)
	layer.add_child(btn)
	return btn


static func pick_table(tables: Dictionary, seated_tid: String) -> String:
	"""Joinable = free seat. Prefer mid-play AI solo (no reset) → idle tables."""
	var ids := tables.keys()
	ids.sort()
	var playing: Array = []
	var idle: Array = []
	for tid in ids:
		if seated_tid == str(tid):
			continue
		var d: Dictionary = tables[tid]
		var black := str(d.get("black_sid", "")).strip_edges()
		var white := str(d.get("white_sid", "")).strip_edges()
		if black != "" and white != "":
			continue
		if black == "" and white == "":
			idle.append(tid)
		elif str(d.get("status", "")) == "playing":
			playing.append(tid)
		else:
			idle.append(tid)
	if not playing.is_empty():
		return str(playing[0])
	if not idle.is_empty():
		return str(idle[0])
	return ""
