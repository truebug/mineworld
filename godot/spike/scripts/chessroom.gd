## Chess lounge: Hub-mode FakeMech presence + thin gateway gomoku tables.
## Join demo_chessroom / room=chess; F sit → chess_sit; Esc → Hub.
extends Node3D

const MOVE_SPEED := 2.8
const TURN_SPEED := 2.2
const CMD_HZ := 20.0
const SIT_DIST := 2.4
const AVATAR_SCENE := preload("res://avatar_puppet.tscn")
const GomokuScript := preload("res://scripts/gomoku.gd")

@export var level_id := "demo_chessroom"
@export var gateway_url := "ws://127.0.0.1:8765"
@export var room_id := "chess"

@onready var ws = $WsClient
@onready var camera_rig: Node3D = $CameraRig
@onready var scene_avatar: Node3D = $Avatar

var _is_web := false
var _session_id := ""
var _joined_room_id := "chess"
var _controlled_entity_id := "avatar_0"
var _controlled := false
var _cmd_timer := 0.0
var _puppets: Dictionary = {}
var _profile: Dictionary = {}
var _board_layer: CanvasLayer = null
var _board_ctrl: Control = null
var _status_label: Label = null
var _title_label: Label = null
var _result_label: Label = null
## table_id → last chess_table_update detail
var _tables: Dictionary = {}
var _view_table_id := ""
var _seated_table_id := ""
var _auto_exit_gen := 0
const AUTO_EXIT_S := 2.4


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_profile = _load_profile()
	if scene_avatar != null:
		scene_avatar.visible = false
	if camera_rig != null and "turn_drive_enabled" in camera_rig:
		camera_rig.turn_drive_enabled = true
	if _is_web:
		if not MWWebInput.web_key_event.is_connected(_on_web_key_event):
			MWWebInput.web_key_event.connect(_on_web_key_event)
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(true,false,true);}",
			true
		)
	_build_board_ui()
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.connect_to_gateway(_resolve_gateway_url())
	MWTransition.notify_arrived()
	print("[MW] chessroom ready (online presence + table FSM)")


func _load_profile() -> Dictionary:
	"""Reuse portal nick / accent from MWi18n meta or URL."""
	var nick := "Guest"
	var accent := "#9a5ae8"
	if MWi18n.has_meta("mw_nick"):
		var saved := str(MWi18n.get_meta("mw_nick")).strip_edges()
		if saved != "":
			nick = saved
	if _is_web:
		var url_nick := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('nick')||''}catch(e){return ''}})()",
			true
		)).strip_edges()
		if url_nick != "":
			nick = url_nick
	return {"nickname": nick, "accent": accent, "id": ""}


func _resolve_gateway_url() -> String:
	if _is_web:
		var from_js := str(JavaScriptBridge.eval("window.MINEWORLD_GATEWAY || ''", true))
		if from_js != "":
			return from_js
	return gateway_url


func _resolve_room_id() -> String:
	if _is_web:
		var from_q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('room')||''}catch(e){return ''}})()",
			true
		)).strip_edges()
		if from_q != "":
			return from_q
	return room_id if room_id != "" else "chess"


func _on_hello(_payload: Dictionary) -> void:
	_session_id = ws.session_id
	_joined_room_id = _resolve_room_id()
	var nick := str(_profile.get("nickname", "Guest"))
	var mw := {
		"profile": {
			"id": str(_profile.get("id", "")),
			"nickname": nick,
			"accent": str(_profile.get("accent", "#9a5ae8")),
		}
	}
	ws.join(level_id, nick, _joined_room_id, {"mw": mw})


func _on_scene(payload: Dictionary) -> void:
	_controlled = false
	var ext: Dictionary = payload.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var mw: Variant = ext.get("mw", {})
		if typeof(mw) == TYPE_DICTIONARY:
			if str(mw.get("controlled_entity_id", "")) != "":
				_controlled_entity_id = str(mw.get("controlled_entity_id"))
			if str(mw.get("room_id", "")) != "":
				_joined_room_id = str(mw.get("room_id"))
	_ensure_puppets(payload.get("entities", []) as Array)
	var own := _own_avatar()
	if camera_rig != null and own != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(own)
	ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})


func _ensure_puppets(entities: Array) -> void:
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		if str(entity.get("kind", "mech")) not in ["mech", "avatar"]:
			continue
		var eid := str(entity.get("entity_id", ""))
		if not eid.begins_with("avatar_"):
			continue
		if _puppets.has(eid):
			continue
		var node: Node3D = AVATAR_SCENE.instantiate()
		node.name = eid
		node.set("entity_id", eid)
		if eid == _controlled_entity_id:
			node.set("accent", Color(str(_profile.get("accent", "#9a5ae8"))))
			node.set("display_name", str(_profile.get("nickname", "Guest")))
			node.set("local_predict", true)
			node.set("interp_delay", 0.03)
		add_child(node)
		_puppets[eid] = node


func _own_avatar() -> Node3D:
	if _puppets.has(_controlled_entity_id):
		return _puppets[_controlled_entity_id]
	return null


func _on_state(_tick: int, t_sim: float, payload: Dictionary) -> void:
	var entities: Array = payload.get("entities", [])
	var occupied: Dictionary = {}
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if not eid.begins_with("avatar_"):
			continue
		if not _puppets.has(eid):
			_ensure_puppets([entity])
		var puppet: Node3D = _puppets.get(eid)
		if puppet == null:
			continue
		var mw: Variant = {}
		var ext: Variant = entity.get("extensions", {})
		if typeof(ext) == TYPE_DICTIONARY:
			mw = ext.get("mw", {})
		var is_occ := true
		if typeof(mw) == TYPE_DICTIONARY and mw.has("occupied"):
			is_occ = bool(mw.get("occupied"))
		occupied[eid] = true
		puppet.visible = is_occ or eid == _controlled_entity_id
		if puppet.has_method("push_state"):
			puppet.call("push_state", entity, t_sim)
		if typeof(mw) == TYPE_DICTIONARY and eid != _controlled_entity_id:
			if str(mw.get("display_name", "")) != "":
				puppet.set("display_name", str(mw.get("display_name")))
	for eid in _puppets.keys():
		if eid == _controlled_entity_id:
			continue
		if not occupied.has(eid):
			(_puppets[eid] as Node3D).visible = false


func _on_event(payload: Dictionary) -> void:
	var et := str(payload.get("event_type", ""))
	if et == "player_take_control":
		_controlled = true
		return
	if et == "player_release_control":
		_controlled = false
		return
	if et != "chess_table_update":
		return
	var detail: Variant = payload.get("detail", {})
	if typeof(detail) != TYPE_DICTIONARY:
		return
	var tid := str(detail.get("table_id", ""))
	if tid == "":
		return
	_tables[tid] = detail
	if _session_id != "" and (
		str(detail.get("black_sid", "")) == _session_id
		or str(detail.get("white_sid", "")) == _session_id
	):
		_seated_table_id = tid
	elif _seated_table_id == tid:
		_seated_table_id = ""
	if _board_open() and _view_table_id == tid:
		_refresh_board_from_authority()


func _on_gateway_error(payload: Dictionary) -> void:
	print("[MW] chessroom gateway error: ", payload)


func _process(delta: float) -> void:
	_cmd_timer += delta
	if _cmd_timer >= 1.0 / CMD_HZ:
		_cmd_timer = 0.0
		_send_velocity_cmd()


func _send_velocity_cmd() -> void:
	var vx := 0.0
	var vy := 0.0
	var yaw_rate := 0.0
	if not _board_open():
		if _is_web:
			if MWWebInput.is_pressed("KeyW"):
				vx += MOVE_SPEED
			if MWWebInput.is_pressed("KeyS"):
				vx -= MOVE_SPEED
			if MWWebInput.is_pressed("KeyA"):
				vy += MOVE_SPEED
			if MWWebInput.is_pressed("KeyD"):
				vy -= MOVE_SPEED
			if MWWebInput.is_pressed("KeyQ"):
				yaw_rate += TURN_SPEED
			if MWWebInput.is_pressed("KeyE"):
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
	var own := _own_avatar()
	if own != null and own.has_method("set_local_cmd"):
		own.call("set_local_cmd", vx, vy, yaw_rate)
	if _session_id == "":
		return
	ws.send_cmd({
		"entity_id": _controlled_entity_id,
		"control_mode": "velocity",
		"vx": vx,
		"vy": vy,
		"yaw_rate": yaw_rate,
	})
	_controlled = true


func _on_web_key_event(code: String, down: bool) -> void:
	if down:
		match code:
			"KeyF":
				_toggle_board()
			"Escape":
				_on_escape()


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
	if _board_open():
		_close_board()
		return
	_leave_to_hub()


func _leave_to_hub() -> void:
	"""Esc → Hub; strip ?room= so Hub does not join play rooms."""
	if ws != null:
		ws.close_link()
	if _is_web:
		JavaScriptBridge.eval(
			"(function(){try{"
			+ "window._mw_keys=Object.create(null);"
			+ "var u=new URL(location.href);"
			+ "u.searchParams.delete('room');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);"
			+ "}catch(e){}})()",
			true
		)
	MWWebInput.clear()
	MWTransition.go("res://demo_hub.tscn", MWi18n.t("母港", "Hub"), "#8a93a3")


func _table_id_for_node(node: Node) -> String:
	var n := str(node.name)
	if n.begins_with("Table"):
		return "table_" + n.substr(5)
	return n.to_lower()


func _nearest_table() -> Node3D:
	var own := _own_avatar()
	if own == null:
		return null
	var best: Node3D = null
	var best_d := SIT_DIST
	for t in get_tree().get_nodes_in_group("chess_tables"):
		var d: float = (t as Node3D).global_position.distance_to(own.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best


func _board_open() -> bool:
	return _board_layer != null and _board_layer.visible


func _toggle_board() -> void:
	if _board_open():
		var detail: Dictionary = _tables.get(_view_table_id, {})
		var status := str(detail.get("status", ""))
		if status == "finished" and _seated_table_id == _view_table_id:
			_auto_exit_gen += 1  # cancel pending auto-stand
			if _result_label != null:
				_result_label.visible = false
			ws.send_cmd({"action": "chess_reset", "table_id": _view_table_id})
			return
		_close_board()
		return
	var nearest := _nearest_table()
	if nearest == null:
		return
	_view_table_id = _table_id_for_node(nearest)
	ws.send_cmd({"action": "chess_sit", "table_id": _view_table_id})
	_board_layer.visible = true
	_refresh_board_from_authority()


func _close_board() -> void:
	_auto_exit_gen += 1
	_board_layer.visible = false
	if _result_label != null:
		_result_label.visible = false
	if _seated_table_id != "":
		ws.send_cmd({"action": "chess_leave", "table_id": _seated_table_id})
	_view_table_id = ""


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
	panel.custom_minimum_size = Vector2(560, 700)
	panel.position = Vector2(-280, -350)
	_board_layer.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	_board_ctrl = Control.new()
	_board_ctrl.custom_minimum_size = Vector2(540, 540)
	_board_ctrl.draw.connect(_draw_board)
	_board_ctrl.gui_input.connect(_on_board_input)
	vbox.add_child(_board_ctrl)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(_result_label)
	_apply_board_fonts()


func _apply_board_fonts() -> void:
	"""Noto SC so win text is not tofu (only Latin F/Esc visible)."""
	var f: Font = MWFonts.font() if MWFonts != null else null
	if f == null:
		return
	for lab in [_title_label, _status_label, _result_label]:
		if lab != null:
			lab.add_theme_font_override("font", f)


func _board_px() -> float:
	return 540.0


func _cell_px() -> float:
	return _board_px() / float(GomokuScript.SIZE + 1)


func _view_detail() -> Dictionary:
	return _tables.get(_view_table_id, {}) as Dictionary


func _my_color() -> int:
	var d := _view_detail()
	if str(d.get("black_sid", "")) == _session_id:
		return GomokuScript.BLACK
	if str(d.get("white_sid", "")) == _session_id and not bool(d.get("vs_ai", false)):
		return GomokuScript.WHITE
	return GomokuScript.EMPTY


func _refresh_board_from_authority() -> void:
	var d := _view_detail()
	var vs_ai := bool(d.get("vs_ai", false))
	if _title_label != null:
		if vs_ai:
			_title_label.text = MWi18n.t(
				"五子棋 · 人机（起身：Esc）",
				"Gomoku vs AI (Esc to stand)"
			)
		else:
			_title_label.text = MWi18n.t(
				"五子棋 · 人对人（起身：Esc）",
				"Gomoku PvP (Esc to stand)"
			)
	var status := str(d.get("status", "idle"))
	var winner := int(d.get("winner", 0))
	var turn := int(d.get("turn", 1))
	var my := _my_color()
	if _result_label != null:
		_result_label.visible = false
	if status == "finished":
		var result := ""
		if winner == GomokuScript.BLACK:
			result = MWi18n.t("● 黑棋获胜", "● Black wins")
		elif winner == GomokuScript.WHITE:
			result = MWi18n.t("○ 白棋获胜", "○ White wins")
		elif bool(d.get("full", false)):
			result = MWi18n.t("△ 平局", "△ Draw")
		else:
			result = MWi18n.t("终局", "Game over")
		if my == winner and winner != GomokuScript.EMPTY:
			result = MWi18n.t("你赢了！", "You win!") + "  " + result
		elif my != GomokuScript.EMPTY and winner != GomokuScript.EMPTY and my != winner:
			result = MWi18n.t("你输了", "You lose") + "  " + result
		_set_status(MWi18n.t("即将自动起身…", "Standing up shortly…"))
		if _result_label != null:
			_result_label.text = result
			_result_label.visible = true
		_schedule_auto_exit()
	elif my == GomokuScript.EMPTY:
		_set_status(MWi18n.t("旁观中", "Spectating"))
	elif turn == my:
		_set_status(MWi18n.t("轮到你了 · 点击落子", "Your move — click"))
	elif vs_ai:
		_set_status(MWi18n.t("AI 思考中…", "AI thinking…"))
	else:
		_set_status(MWi18n.t("等待对手…", "Waiting for opponent…"))
	if _board_ctrl != null:
		_board_ctrl.queue_redraw()


func _schedule_auto_exit() -> void:
	"""After a short win beat, leave the seat and close the board."""
	_auto_exit_gen += 1
	var gen := _auto_exit_gen
	get_tree().create_timer(AUTO_EXIT_S).timeout.connect(
		func() -> void:
			if gen != _auto_exit_gen:
				return
			if not _board_open():
				return
			_close_board()
	)


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
	var detail := _view_detail()
	var cells: Array = detail.get("cells", [])
	var win_set: Dictionary = {}
	var win_line: Array = detail.get("win_line", [])
	for pt in win_line:
		if typeof(pt) != TYPE_ARRAY:
			continue
		var arr := pt as Array
		if arr.size() < 2:
			continue
		win_set["%d,%d" % [int(arr[0]), int(arr[1])]] = true
	for y in s:
		for x in s:
			var idx := y * s + x
			var v := 0
			if idx < cells.size():
				v = int(cells[idx])
			var center := _cell_center(x, y)
			var key := "%d,%d" % [x, y]
			if win_set.has(key):
				_board_ctrl.draw_circle(center, c * 0.55, Color(1.0, 0.75, 0.15, 0.85))
			if v == GomokuScript.BLACK:
				_board_ctrl.draw_circle(center, c * 0.42, Color(0.08, 0.08, 0.1))
			elif v == GomokuScript.WHITE:
				_board_ctrl.draw_circle(center, c * 0.42, Color(0.95, 0.95, 0.93))
				_board_ctrl.draw_arc(center, c * 0.42, 0, TAU, 24, Color(0.3, 0.3, 0.3), 1.2)


func _cell_center(x: int, y: int) -> Vector2:
	var c := _cell_px()
	return Vector2(c * float(x + 1), c * float(y + 1))


func _on_board_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	var d := _view_detail()
	if str(d.get("status", "")) != "playing":
		return
	var my := _my_color()
	if my == GomokuScript.EMPTY or int(d.get("turn", 0)) != my:
		return
	var c := _cell_px()
	var x := int(round(mb.position.x / c)) - 1
	var y := int(round(mb.position.y / c)) - 1
	ws.send_cmd({
		"action": "chess_place",
		"table_id": _view_table_id,
		"x": x,
		"y": y,
	})


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
