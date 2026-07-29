## MWWebInput — autoload singleton for Web keyboard input.
## Installs DOM keydown/keyup listeners once (survives scene changes).
## All scenes share the same _held_codes dict via is_pressed().
## Scene-specific special keys connect to web_key_event signal.
extends Node

signal web_key_event(code: String, down: bool)

## Blocked codes that get preventDefault in the DOM listener.
const WEB_BLOCK_CODES := {
	"Space": true, "ArrowUp": true, "ArrowDown": true,
	"ArrowLeft": true, "ArrowRight": true,
}

var _held_codes: Dictionary = {}
var _web_key_cb
var _web_blur_cb
var _initialized := false


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_install()
	_initialized = true


func _install() -> void:
	_web_key_cb = JavaScriptBridge.create_callback(_on_dom_key_event)
	_web_blur_cb = JavaScriptBridge.create_callback(_on_dom_blur)
	var doc = JavaScriptBridge.get_interface("document")
	var win = JavaScriptBridge.get_interface("window")
	if doc == null or win == null:
		push_warning("[MWWebInput] document/window unavailable")
		return
	# DOM listener (primary path).
	doc.addEventListener("keydown", _web_key_cb)
	doc.addEventListener("keyup", _web_key_cb)
	win.addEventListener("blur", _web_blur_cb)
	# Poll window._mw_keys (redundant path — same as scene-installed bridge).
	# Installed here too so hub/main/chessroom removed code is fully replaced.
	_mw_poll_setup()


func _mw_poll_setup() -> void:
	"""Start poll timer for window._mw_keys mirror (belt-and-suspenders)."""
	if not OS.has_feature("web"):
		return
	set_process(true)


func _process(_delta: float) -> void:
	"""Each frame: merge window._mw_keys into _held_codes (false releases included)."""
	if not _initialized:
		return
	var raw := str(JavaScriptBridge.eval(
		"(function(){try{return JSON.stringify(window._mw_keys||{})}catch(e){return '{}'}}())",
		true
	))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# Only codes present in the mirror — do not wipe DOM-listener keys when
	# _mw_keys is empty/uninstalled (would cancel all Web WASD).
	for k in (parsed as Dictionary).keys():
		_held_codes[str(k)] = bool((parsed as Dictionary)[k])


func _on_dom_key_event(args: Array) -> void:
	if args.is_empty():
		return
	var event = args[0]
	var code := str(event.code)
	var down := str(event.type) == "keydown"
	_held_codes[code] = down
	web_key_event.emit(code, down)
	if WEB_BLOCK_CODES.has(code):
		event.preventDefault()


func _on_dom_blur(_args: Array) -> void:
	_held_codes.clear()


func is_pressed(code: String) -> bool:
	"""True while DOM key is down; ignore while typing in an input field."""
	if OS.has_feature("web") and _typing_in_field():
		return false
	return bool(_held_codes.get(code, false))


func _typing_in_field() -> bool:
	"""True when focus is on INPUT / TEXTAREA / contentEditable."""
	return bool(JavaScriptBridge.eval(
		"(function(){var t=document.activeElement;if(!t)return false;var n=(t.tagName||'').toUpperCase();return n==='INPUT'||n==='TEXTAREA'||!!t.isContentEditable})()",
		true
	))


func clear() -> void:
	_held_codes.clear()


func get_axis(positive: String, negative: String) -> float:
	var v := 0.0
	if is_pressed(positive):
		v += 1.0
	if is_pressed(negative):
		v -= 1.0
	return v
