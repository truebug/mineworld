## UX2 / UX2b: fade overlay then change_scene (Web DOM · desktop ColorRect).
## UX2b: optional accent tint, skip (Enter/click), desktop Tween ~280ms.
extends Node

const FADE_S := 0.28
## If the next scene never calls notify_arrived(), tear down the overlay
## so Hub doors are not permanently blocked (go() no-ops while _busy).
const ARRIVE_WATCHDOG_S := 2.5

var _busy := false
var _layer: CanvasLayer
var _rect: ColorRect
var _label: Label
var _pending_scene := ""
var _skip_requested := false
var _fade_tween: Tween
var _watchdog_gen := 0


func _ready() -> void:
	"""Desktop-only overlay; Web uses shell.html #mw-transition."""
	if not OS.has_feature("web"):
		_ensure_desktop_overlay()
	set_process_unhandled_input(true)
	set_process(true)


func _process(_delta: float) -> void:
	"""UX2b Web: poll shell skip flag (DOM overlay eats clicks)."""
	if not _busy or not OS.has_feature("web"):
		return
	var flag := str(JavaScriptBridge.eval(
		"(function(){if(window._MW_SKIP_TRANSITION){window._MW_SKIP_TRANSITION=false;return '1';}return '0';})()",
		true
	))
	if flag == "1":
		_request_skip()


func go(scene_path: String, label: String = "", accent: String = "") -> bool:
	"""Fade out, then load scene_path. New scene must call notify_arrived().

	Returns false if path empty. If a previous transition left `_busy` stuck
	(overlay up, no notify_arrived), force-clear then proceed so doors work.
	"""
	if scene_path == "":
		return false
	if _busy:
		push_warning("[MW] transition: clearing stuck busy before go(%s)" % scene_path)
		_force_clear()
	_run_go(scene_path, label, accent)
	return true


func notify_arrived() -> void:
	"""Call from each playable scene _ready after boot chrome is set."""
	_watchdog_gen += 1
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_TRANSITION==='object'&&window.MW_TRANSITION.end){window.MW_TRANSITION.end();}",
			true
		)
	elif _rect != null:
		_desktop_set_alpha(0.0, false)
	_busy = false
	_pending_scene = ""
	_skip_requested = false


func _force_clear() -> void:
	"""Drop overlay + busy without changing scene (recovery path)."""
	_watchdog_gen += 1
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_TRANSITION==='object'&&window.MW_TRANSITION.end){window.MW_TRANSITION.end();}",
			true
		)
	elif _rect != null:
		_desktop_set_alpha(0.0, false)
	_busy = false
	_pending_scene = ""
	_skip_requested = false


func _unhandled_input(event: InputEvent) -> void:
	"""UX2b: skip fade with Enter / ui_accept / mouse click while busy."""
	if not _busy:
		return
	var skip := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			skip = true
		elif event.is_action_pressed("ui_accept"):
			skip = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		skip = true
	if skip:
		_request_skip()
		get_viewport().set_input_as_handled()


func _request_skip() -> void:
	"""Jump to change_scene immediately."""
	if not _busy or _pending_scene == "":
		return
	_skip_requested = true
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_finish_go()


func _run_go(scene_path: String, label: String, accent: String) -> void:
	"""Async fade → change_scene (lives on autoload across scene swap)."""
	_busy = true
	_pending_scene = scene_path
	_skip_requested = false
	if OS.has_feature("web"):
		var payload := JSON.stringify({"label": label, "accent": accent})
		JavaScriptBridge.eval(
			"if(typeof window.MW_TRANSITION==='object'&&window.MW_TRANSITION.start){window.MW_TRANSITION.start(%s);}"
			% payload,
			true
		)
		await get_tree().create_timer(FADE_S).timeout
		# Skip already called _finish_go; only bail if pending was consumed.
		if _pending_scene == "":
			return
		_finish_go()
		return
	_desktop_set_label(label)
	_desktop_apply_accent(accent)
	await _desktop_fade_to(1.0)
	if _pending_scene == "":
		return
	_finish_go()


func _finish_go() -> void:
	"""Load pending scene once (skip-safe)."""
	var path := _pending_scene
	if path == "":
		return
	_pending_scene = ""
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[MW] transition: change_scene_to_file(%s) failed err=%s" % [path, err])
		_force_clear()
		return
	_arm_arrive_watchdog()


func _arm_arrive_watchdog() -> void:
	"""If next scene never calls notify_arrived, clear overlay so Hub recovers."""
	_watchdog_gen += 1
	var gen := _watchdog_gen
	await get_tree().create_timer(ARRIVE_WATCHDOG_S).timeout
	if gen != _watchdog_gen or not _busy:
		return
	push_warning("[MW] transition: arrive watchdog — forcing overlay clear")
	_force_clear()


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
	_rect.gui_input.connect(_on_desktop_rect_input)
	_layer.add_child(_rect)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_label.modulate = Color(0.85, 0.9, 1.0, 1.0)
	_rect.add_child(_label)


func _on_desktop_rect_input(event: InputEvent) -> void:
	"""Click overlay to skip while fading."""
	if not _busy:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_request_skip()


func _desktop_set_label(text: String) -> void:
	"""Show optional route label on desktop fade."""
	if _label != null:
		_label.text = text


func _desktop_apply_accent(accent: String) -> void:
	"""Tint fade base color from hex (#rrggbb) when provided."""
	if _rect == null:
		return
	var base := Color(0.02, 0.03, 0.06, _rect.color.a)
	if accent != "" and accent.begins_with("#") and accent.length() >= 7:
		var parsed := Color.from_string(accent, Color(0.9, 0.55, 0.25))
		base = Color(
			lerpf(0.02, parsed.r, 0.35),
			lerpf(0.03, parsed.g, 0.35),
			lerpf(0.06, parsed.b, 0.35),
			_rect.color.a,
		)
	_rect.color = base


func _desktop_set_alpha(a: float, animate: bool = true) -> void:
	"""Set overlay alpha; animate with Tween when requested (UX2b)."""
	if _rect == null:
		return
	if animate:
		# Fire-and-forget helper for notify_arrived fade-out.
		_desktop_fade_to(a)
		return
	var c := _rect.color
	c.a = a
	_rect.color = c
	_rect.mouse_filter = (
		Control.MOUSE_FILTER_STOP if a > 0.05 else Control.MOUSE_FILTER_IGNORE
	)


func _desktop_fade_to(a: float) -> void:
	"""Tween alpha over FADE_S (awaitable)."""
	if _rect == null:
		return
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_property(_rect, "color:a", a, FADE_S)
	await _fade_tween.finished
	if a <= 0.05 and _rect != null:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
