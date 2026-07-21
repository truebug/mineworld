## Shared CJK font for Label3D (Godot default font has no Chinese glyphs).
extends Node

const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.ttf"

var _font: Font


func font() -> Font:
	"""Lazy-load Noto Sans SC (OFL)."""
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


func apply_label3d(label: Label3D) -> void:
	"""Assign CJK font so Chinese door/NPC tags render on Web + desktop."""
	if label == null:
		return
	var f := font()
	if f != null:
		label.font = f
