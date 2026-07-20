## UX2-v0: fade overlay then change_scene (Web DOM · desktop ColorRect).
extends Node

const FADE_S := 0.28

var _busy := false
var _layer: CanvasLayer
var _rect: ColorRect
var _label: Label


func _ready() -> void:
	"""Desktop-only overlay; Web uses shell.html #mw-transition."""
	if not OS.has_feature("web"):
		_ensure_desktop_overlay()


func go(scene_path: String, label: String = "") -> void:
	"""Fade out, then load scene_path. New scene must call notify_arrived()."""
	if _busy:
		return
	if scene_path == "":
		return
	_run_go(scene_path, label)


func notify_arrived() -> void:
	"""Call from each playable scene _ready after boot chrome is set."""
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_TRANSITION==='object'&&window.MW_TRANSITION.end){window.MW_TRANSITION.end();}",
			true
		)
	elif _rect != null:
		_desktop_set_alpha(0.0)
	_busy = false


func _run_go(scene_path: String, label: String) -> void:
	"""Async fade → change_scene (lives on autoload across scene swap)."""
	_busy = true
	if OS.has_feature("web"):
		var payload := JSON.stringify({"label": label})
		JavaScriptBridge.eval(
			"if(typeof window.MW_TRANSITION==='object'&&window.MW_TRANSITION.start){window.MW_TRANSITION.start(%s);}"
			% payload,
			true
		)
	else:
		_desktop_set_label(label)
		_desktop_set_alpha(1.0)
	await get_tree().create_timer(FADE_S).timeout
	get_tree().change_scene_to_file(scene_path)


func _ensure_desktop_overlay() -> void:
	"""Full-screen black fade for non-Web exports."""
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.name = "MWTransitionLayer"
	add_child(_layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0.02, 0.03, 0.06, 0.0)
	_layer.add_child(_rect)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.modulate = Color(0.85, 0.9, 1.0, 1.0)
	_rect.add_child(_label)


func _desktop_set_label(text: String) -> void:
	"""Show optional route label on desktop fade."""
	if _label != null:
		_label.text = text


func _desktop_set_alpha(a: float) -> void:
	"""Instant alpha (v0; CSS handles Web easing)."""
	if _rect == null:
		return
	var c := _rect.color
	c.a = a
	_rect.color = c
	_rect.mouse_filter = (
		Control.MOUSE_FILTER_STOP if a > 0.05 else Control.MOUSE_FILTER_IGNORE
	)
