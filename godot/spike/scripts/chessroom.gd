## Chess room (棋牌室) phase 1: offline scene — 4 tables, F to sit, gomoku vs AI.
## No gateway link (multiplayer tables arrive in phase 2); Esc returns to Hub.
extends Node3D

const MOVE_SPEED := 2.8
const TURN_SPEED := 2.2
const SIT_DIST := 2.4
const GomokuScript := preload("res://scripts/gomoku.gd")

@onready var avatar: Node3D = $Avatar
@onready var camera_rig: Node3D = $CameraRig

var _is_web := false
var _held_codes := {}
var _web_key_cb
var _web_blur_cb
var _web_mw_bridge := false
var _board_layer: CanvasLayer = null
var _board_ctrl: Control = null
var _status_label: Label = null
var _game: RefCounted = null
var _thinking := false


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_game = GomokuScript.new()
	if avatar != null:
		avatar.set("local_predict", true)
	if camera_rig != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(avatar)
	if _is_web:
		_install_web_key_bridge()
		_web_mw_bridge = true
		# Switch DOM shell to play chrome (hub keeps its own overlay set).
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(true,false,true);}",
			true
		)
	_build_board_ui()
	MWTransition.notify_arrived()
	print("[MW] chessroom ready (offline, gomoku vs AI)")
	# Recover nick from hub (MWi18n meta survives scene change).
	var own_tag := avatar.get_node_or_null("NameTag") as Label3D
	if own_tag != null and MWi18n.has_meta("mw_nick"):
		var saved := str(MWi18n.get_meta("mw_nick"))
		if saved != "":
			own_tag.text = saved


func _install_web_key_bridge() -> void:
	_web_key_cb = JavaScriptBridge.create_callback(_on_dom_key_event)
	_web_blur_cb = JavaScriptBridge.create_callback(_on_dom_blur)
	var document = JavaScriptBridge.get_interface("document")
	var window_obj = JavaScriptBridge.get_interface("window")
	if document == null or window_obj == null:
		return
	document.addEventListener("keydown", _web_key_cb)
	document.addEventListener("keyup", _web_key_cb)
	window_obj.addEventListener("blur", _web_blur_cb)


func _on_dom_key_event(args: Array) -> void:
	if args.is_empty():
		return
	var event = args[0]
	var code := str(event.code)
	var down := str(event.type) == "keydown"
	_held_codes[code] = down
	if down and code == "KeyF":
		_toggle_board()
	elif down and code == "Escape":
		_on_escape()
	if code in ["Space", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"]:
		event.preventDefault()


func _on_dom_blur(_args: Array) -> void:
	_held_codes.clear()


func _key(code: String) -> bool:
	return bool(_held_codes.get(code, false))


func _unhandled_input(event: InputEvent) -> void:
	if _is_web:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_F or ek.physical_keycode == KEY_F:
			_toggle_board()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_ESCAPE:
			_on_escape()
			get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if _board_layer != null and _board_layer.visible:
		_close_board()
	else:
		MWTransition.go("res://demo_hub.tscn", MWi18n.t("母港", "Hub"), "#8a93a3")


func _process(_delta: float) -> void:
	if _is_web and _web_mw_bridge:
		_held_codes = _held_codes.duplicate()
		var raw := str(JavaScriptBridge.eval(
			"(function(){try{return JSON.stringify(window._mw_keys||{})}catch(e){return '{}'}}())",
			true
		))
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in (parsed as Dictionary).keys():
				_held_codes[str(k)] = bool((parsed as Dictionary)[k])
	var vx := 0.0
	var vy := 0.0
	var yaw_rate := 0.0
	if not _board_open():
		if _is_web:
			if _key("KeyW"):
				vx += MOVE_SPEED
			if _key("KeyS"):
				vx -= MOVE_SPEED
			if _key("KeyA"):
				vy += MOVE_SPEED
			if _key("KeyD"):
				vy -= MOVE_SPEED
			if _key("KeyQ"):
				yaw_rate += TURN_SPEED
			if _key("KeyE"):
				yaw_rate -= TURN_SPEED
		else:
			if Input.is_physical_key_pressed(KEY_W):
				vx += MOVE_SPEED
			if Input.is_physical_key_pressed(KEY_S):
				vx -= MOVE_SPEED
			if Input.is_physical_key_pressed(KEY_A):
				vy += MOVE_SPEED
			if Input.is_physical_key_pressed(KEY_D):
				vy -= MOVE_SPEED
			if Input.is_physical_key_pressed(KEY_Q):
				yaw_rate += TURN_SPEED
			if Input.is_physical_key_pressed(KEY_E):
				yaw_rate -= TURN_SPEED
	if avatar != null and avatar.has_method("set_local_cmd"):
		avatar.call("set_local_cmd", vx, vy, yaw_rate)


func _nearest_table() -> Node3D:
	var best: Node3D = null
	var best_d := SIT_DIST
	for t in get_tree().get_nodes_in_group("chess_tables"):
		var d: float = (t as Node3D).global_position.distance_to(avatar.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _board_open() -> bool:
	return _board_layer != null and _board_layer.visible


func _toggle_board() -> void:
	if _board_open():
		if _game.winner != GomokuScript.EMPTY or _game.is_full():
			_open_board()  ## game over → F restarts instead of standing up
		else:
			_close_board()
		return
	if _nearest_table() == null:
		return
	_open_board()


func _open_board() -> void:
	_game.reset()
	_thinking = false
	_board_layer.visible = true
	_set_status(MWi18n.t("你执黑先行 · 点击棋盘落子", "Black to move — click the board"))
	_board_ctrl.queue_redraw()


func _close_board() -> void:
	_board_layer.visible = false


func _build_board_ui() -> void:
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 20
	_board_layer.visible = false
	add_child(_board_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 660)
	panel.position = Vector2(-280, -330)
	_board_layer.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = MWi18n.t("五子棋 · 人机对弈（F/Esc 起身）", "Gomoku vs AI (F/Esc to stand up)")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_board_ctrl = Control.new()
	_board_ctrl.custom_minimum_size = Vector2(540, 540)
	_board_ctrl.draw.connect(_draw_board)
	_board_ctrl.gui_input.connect(_on_board_input)
	vbox.add_child(_board_ctrl)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)


func _board_px() -> float:
	return 540.0


func _cell_px() -> float:
	return _board_px() / float(GomokuScript.SIZE + 1)


func _draw_board() -> void:
	var s := GomokuScript.SIZE
	var c := _cell_px()
	_board_ctrl.draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * _board_px()), Color(0.87, 0.72, 0.47))
	for i in s:
		var p := c * float(i + 1)
		_board_ctrl.draw_line(Vector2(c, p), Vector2(_board_px() - c, p), Color(0.25, 0.18, 0.1), 1.5)
		_board_ctrl.draw_line(Vector2(p, c), Vector2(p, _board_px() - c), Color(0.25, 0.18, 0.1), 1.5)
	for star in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7)]:
		_board_ctrl.draw_circle(_cell_center(star.x, star.y), 4.0, Color(0.25, 0.18, 0.1))
	for y in s:
		for x in s:
			var v: int = _game.at(x, y)
			if v == GomokuScript.BLACK:
				_board_ctrl.draw_circle(_cell_center(x, y), c * 0.42, Color(0.08, 0.08, 0.1))
			elif v == GomokuScript.WHITE:
				_board_ctrl.draw_circle(_cell_center(x, y), c * 0.42, Color(0.95, 0.95, 0.93))
				_board_ctrl.draw_arc(_cell_center(x, y), c * 0.42, 0, TAU, 24, Color(0.3, 0.3, 0.3), 1.2)


func _cell_center(x: int, y: int) -> Vector2:
	var c := _cell_px()
	return Vector2(c * float(x + 1), c * float(y + 1))


func _on_board_input(event: InputEvent) -> void:
	if _thinking or _game.winner != GomokuScript.EMPTY:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var c := _cell_px()
	var x := int(round(mb.position.x / c)) - 1
	var y := int(round(mb.position.y / c)) - 1
	if not _game.place(x, y, GomokuScript.BLACK):
		return
	_board_ctrl.queue_redraw()
	if _game.winner == GomokuScript.BLACK:
		_set_status(MWi18n.t("你赢了！按 F 再来一局", "You win! F for a new game"))
		return
	if _game.is_full():
		_set_status(MWi18n.t("平局 · 按 F 再来一局", "Draw · F for a new game"))
		return
	_thinking = true
	_set_status(MWi18n.t("AI 思考中…", "AI thinking…"))
	await get_tree().create_timer(0.35).timeout
	var mv: Vector2i = _game.ai_move()
	_game.place(mv.x, mv.y, GomokuScript.WHITE)
	_thinking = false
	_board_ctrl.queue_redraw()
	if _game.winner == GomokuScript.WHITE:
		_set_status(MWi18n.t("AI 获胜 · 按 F 再来一局", "AI wins · F for a new game"))
	else:
		_set_status(MWi18n.t("轮到你了", "Your move"))


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
