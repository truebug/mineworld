## Chess lounge: Hub FakeMech presence + multi-game tables (gomoku / checkers / junqi).
## Join demo_chessroom / room=chess; F sit; Esc → Hub.
extends Node3D

const MOVE_SPEED := 2.8
const TURN_SPEED := 2.2
const CMD_HZ := 20.0
const SIT_DIST := 2.4
const AVATAR_SCENE := preload("res://avatar_puppet.tscn")
const GomokuScript := preload("res://scripts/gomoku.gd")
const AUTO_EXIT_S := 2.4
const JUNQI_ROWS := 12
const JUNQI_COLS := 5
## Short labels for board chips (SSOT types).
const JUNQI_LABEL := {
	"junqi": "旗",
	"siling": "司",
	"junzhang": "军",
	"shizhang": "师",
	"lvzhang": "旅",
	"tuanzhang": "团",
	"yingzhang": "营",
	"lianzhang": "连",
	"paizhang": "排",
	"gongbing": "工",
	"zhadan": "炸",
	"dilei": "雷",
	"?": "?",
}
## Fallback meta until first chess_table_update arrives.
const TABLE_META := {
	"table_1": {"game": "gomoku", "title_zh": "五子棋 · 甲桌", "title_en": "Gomoku A", "accent": Color(0.95, 0.55, 0.2)},
	"table_2": {"game": "gomoku", "title_zh": "五子棋 · 乙桌", "title_en": "Gomoku B", "accent": Color(0.95, 0.7, 0.35)},
	"table_3": {"game": "checkers", "title_zh": "跳棋", "title_en": "Halma", "accent": Color(0.35, 0.75, 0.95)},
	"table_4": {"game": "junqi", "title_zh": "军棋", "title_en": "Junqi", "accent": Color(0.75, 0.45, 0.9)},
}

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
var _board_panel: PanelContainer = null
var _board_ctrl: Control = null
var _status_label: Label = null
var _title_label: Label = null
var _result_label: Label = null
var _tips_label: Label = null
var _layout_btn: Button = null
var _confirm_btn: Button = null
var _resign_btn: Button = null
var _hand_btn: Button = null
var _rules_btn: Button = null
var _rules_label: Label = null
var _rules_visible := false
var _tables: Dictionary = {}
var _view_table_id := ""
var _seated_table_id := ""
var _auto_exit_gen := 0
var _sel := Vector2i(-1, -1)


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_profile = _load_profile()
	if scene_avatar != null:
		scene_avatar.visible = false
	if camera_rig != null and "turn_drive_enabled" in camera_rig:
		camera_rig.turn_drive_enabled = true
	_label_tables()
	_push_chess_shell_tips()
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
	print("[MW] chessroom ready (gomoku + checkers + junqi)")


func _push_chess_shell_tips() -> void:
	"""Replace Hub DOM tips with chessroom guide."""
	var full := MWi18n.t(
		"棋牌室\n"
		+ "走近棋桌按 F 落座 · Esc 起身/回母港\n"
		+ "甲/乙桌：五子棋 · 丙桌：跳棋 · 丁桌：军棋\n"
		+ "WASD 平移 · Q/E 转向 · 人机可单人开局，第二人入座变对战",
		"Chess Lounge\n"
		+ "Walk to a table · F sit · Esc stand / Hub\n"
		+ "A/B Gomoku · C Halma · D Junqi\n"
		+ "WASD move · Q/E turn · solo vs AI; second sitter → PvP"
	)
	var collapsed := MWi18n.t("棋牌室 · 提示 ›（点击）", "Chess · tips › (click)")
	if _is_web:
		JavaScriptBridge.eval(
			(
				"(function(){var t=%s;var c=%s;"
				+ "if(typeof window.MW_SET_HUD==='function'){window.MW_SET_HUD(t,c);}"
				+ "})()"
			) % [JSON.stringify(full), JSON.stringify(collapsed)],
			true
		)
		return
	if _tips_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_tips_label = Label.new()
		_tips_label.position = Vector2(16, 16)
		_tips_label.size = Vector2(420, 160)
		_tips_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		layer.add_child(_tips_label)
		var f: Font = MWFonts.font() if MWFonts != null else null
		if f != null:
			_tips_label.add_theme_font_override("font", f)
	_tips_label.text = full


func _label_tables() -> void:
	"""3D nameplates so each table type is obvious at a glance."""
	var room_lab := get_node_or_null("RoomLabel") as Label3D
	if room_lab != null:
		room_lab.text = MWi18n.t(
			"棋牌室 · 走近棋桌按 F · 甲乙五子棋 / 丙跳棋 / 丁军棋",
			"Chess · F to sit · A/B Gomoku · C Halma · D Junqi"
		)
		MWFonts.apply_label3d(room_lab)
	for t in get_tree().get_nodes_in_group("chess_tables"):
		var node := t as Node3D
		if node == null:
			continue
		var tid := _table_id_for_node(node)
		var meta: Dictionary = TABLE_META.get(tid, {})
		var title := MWi18n.t(
			str(meta.get("title_zh", tid)),
			str(meta.get("title_en", tid))
		)
		var lab := node.get_node_or_null("TableName") as Label3D
		if lab == null:
			lab = Label3D.new()
			lab.name = "TableName"
			lab.position = Vector3(0, 0.55, 0)
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.font_size = 42
			lab.outline_size = 6
			lab.pixel_size = 0.01
			node.add_child(lab)
		lab.text = title
		lab.modulate = meta.get("accent", Color(1, 0.9, 0.75))
		MWFonts.apply_label3d(lab)


func _load_profile() -> Dictionary:
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
			_auto_exit_gen += 1
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
	_sel = Vector2i(-1, -1)
	_rules_visible = false
	ws.send_cmd({"action": "chess_sit", "table_id": _view_table_id})
	_board_layer.visible = true
	_fit_board_panel()
	_refresh_board_from_authority()


func _close_board() -> void:
	_auto_exit_gen += 1
	_board_layer.visible = false
	_sel = Vector2i(-1, -1)
	_rules_visible = false
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
	_board_panel = panel
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
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)
	_layout_btn = Button.new()
	_layout_btn.text = MWi18n.t("随机布阵", "Auto layout")
	_layout_btn.visible = false
	_layout_btn.pressed.connect(_on_junqi_auto_layout)
	btn_row.add_child(_layout_btn)
	_confirm_btn = Button.new()
	_confirm_btn.text = MWi18n.t("确认布阵", "Confirm")
	_confirm_btn.visible = false
	_confirm_btn.pressed.connect(_on_junqi_confirm_layout)
	btn_row.add_child(_confirm_btn)
	_resign_btn = Button.new()
	_resign_btn.text = MWi18n.t("认输", "Resign")
	_resign_btn.visible = false
	_resign_btn.pressed.connect(_on_chess_resign)
	btn_row.add_child(_resign_btn)
	_hand_btn = Button.new()
	_hand_btn.text = MWi18n.t("举手", "Hand")
	_hand_btn.visible = false
	_hand_btn.pressed.connect(_on_chess_hand)
	btn_row.add_child(_hand_btn)
	_rules_btn = Button.new()
	_rules_btn.text = MWi18n.t("规则说明", "Rules")
	_rules_btn.visible = false
	_rules_btn.pressed.connect(_toggle_junqi_rules)
	btn_row.add_child(_rules_btn)
	_rules_label = Label.new()
	_rules_label.visible = false
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_label.custom_minimum_size = Vector2(520, 0)
	_rules_label.add_theme_font_size_override("font_size", 14)
	_rules_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.82))
	_rules_label.text = MWi18n.t(
		"12×5 · 行营免战 · 铁路工兵可拐弯\n"
		+ "军旗必在大本营 · 地雷仅后两行 · 炸弹不上底线\n"
		+ "公路一步 · 铁路直线（工兵可拐）· 行营离营限一格\n"
		+ "任意己子走进对方军旗即胜（无需清雷）\n"
		+ "司令阵亡→公开该方军旗位置",
		"12×5 · camps safe · engineer turns on rail\n"
		+ "Flag in HQ · mines last 2 rows · bombs not on back row\n"
		+ "Road 1-step · rail straight (engineer bends)\n"
		+ "Any piece walking onto flag wins (no mine-clear)\n"
		+ "Commander lost → reveal that side's flag"
	)
	vbox.add_child(_rules_label)
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
	var f: Font = MWFonts.font() if MWFonts != null else null
	if f == null:
		return
	for lab in [_title_label, _status_label, _result_label, _rules_label]:
		if lab != null:
			lab.add_theme_font_override("font", f)
	for btn in [_layout_btn, _confirm_btn, _resign_btn, _hand_btn, _rules_btn]:
		if btn != null:
			btn.add_theme_font_override("font", f)


func _toggle_junqi_rules() -> void:
	"""Show / hide concise junqi rules (SSOT summary)."""
	_rules_visible = not _rules_visible
	if _rules_label != null:
		_rules_label.visible = _rules_visible and _view_game() == "junqi"
	if _rules_btn != null:
		_rules_btn.text = (
			MWi18n.t("隐藏规则", "Hide rules")
			if _rules_visible
			else MWi18n.t("规则说明", "Rules")
		)


func _on_junqi_auto_layout() -> void:
	"""Draft a random legal layout (not ready — may hand-tune)."""
	if _view_table_id == "" or _view_game() != "junqi":
		return
	_sel = Vector2i(-1, -1)
	ws.send_cmd({
		"action": "junqi_layout",
		"table_id": _view_table_id,
		"auto": true,
		"ready": false,
	})


func _on_junqi_confirm_layout() -> void:
	"""Lock current draft and start (AI fills red if vs_ai)."""
	if _view_table_id == "" or _view_game() != "junqi":
		return
	ws.send_cmd({
		"action": "junqi_layout",
		"table_id": _view_table_id,
		"ready": true,
	})


func _on_chess_resign() -> void:
	"""Resign current playing table."""
	if _view_table_id == "":
		return
	ws.send_cmd({"action": "chess_resign", "table_id": _view_table_id})


func _on_chess_hand() -> void:
	"""Raise hand signal for opponent / room."""
	if _view_table_id == "":
		return
	ws.send_cmd({
		"action": "chess_hand",
		"table_id": _view_table_id,
		"kind": "raise",
	})


func _board_px() -> float:
	if _board_ctrl != null and _board_ctrl.custom_minimum_size.x > 10.0:
		return _board_ctrl.custom_minimum_size.x
	return 540.0


func _junqi_board_size() -> Vector2:
	"""Fit 12×5 board into viewport so chrome + status stay on screen."""
	var vp := get_viewport().get_visible_rect().size
	var chrome := 176.0
	var max_h := clampf(vp.y - chrome, 260.0, 460.0)
	var max_w := clampf(vp.x - 56.0, 170.0, 280.0)
	var h := max_h
	var w := h * (5.0 / 12.2)
	if w > max_w:
		w = max_w
		h = w * (12.2 / 5.0)
	return Vector2(floorf(w), floorf(h))


func _junqi_flip() -> bool:
	"""Put local player's half at the bottom of the screen."""
	return _my_junqi_side() == "black"


func _junqi_view_r(model_r: int) -> int:
	return (JUNQI_ROWS - 1 - model_r) if _junqi_flip() else model_r


func _junqi_model_r(view_r: int) -> int:
	return (JUNQI_ROWS - 1 - view_r) if _junqi_flip() else view_r


func _fit_board_panel() -> void:
	"""Resize centered panel so board + chrome stay inside the viewport."""
	if _board_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if _view_game() == "junqi":
		var bs := _junqi_board_size()
		if _board_ctrl != null:
			_board_ctrl.custom_minimum_size = bs
		var pw := maxf(bs.x + 40.0, 300.0)
		var ph := minf(vp.y - 16.0, bs.y + 148.0)
		_board_panel.custom_minimum_size = Vector2(pw, ph)
		_board_panel.size = Vector2(pw, ph)
		_board_panel.position = Vector2(-pw * 0.5, -ph * 0.5)
		return
	var side := clampf(minf(vp.x - 64.0, vp.y - 168.0), 300.0, 520.0)
	if _board_ctrl != null:
		_board_ctrl.custom_minimum_size = Vector2(side, side)
	var pw2 := side + 40.0
	var ph2 := minf(vp.y - 16.0, side + 140.0)
	_board_panel.custom_minimum_size = Vector2(pw2, ph2)
	_board_panel.size = Vector2(pw2, ph2)
	_board_panel.position = Vector2(-pw2 * 0.5, -ph2 * 0.5)


func _draw_wood_frame(sz: Vector2, face: Color) -> void:
	"""Shared outer wood rim + inner playing surface."""
	_board_ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.38, 0.22, 0.1))
	var pad := 8.0
	var inner := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
	_board_ctrl.draw_rect(inner, face)
	# Subtle grain stripes
	var grain := Color(face.r * 0.92, face.g * 0.92, face.b * 0.9, 0.35)
	var y := inner.position.y + 4.0
	while y < inner.end.y:
		_board_ctrl.draw_line(
			Vector2(inner.position.x + 2.0, y),
			Vector2(inner.end.x - 2.0, y),
			grain,
			1.0
		)
		y += 7.0
	_board_ctrl.draw_rect(inner, Color(0.25, 0.14, 0.06, 0.55), false, 2.0)


func _draw_stone(center: Vector2, radius: float, black: bool) -> void:
	"""Glossy go/gomoku stone with rim highlight."""
	_board_ctrl.draw_circle(center + Vector2(1.2, 1.8), radius, Color(0, 0, 0, 0.28))
	if black:
		_board_ctrl.draw_circle(center, radius, Color(0.08, 0.07, 0.07))
		_board_ctrl.draw_circle(center - Vector2(radius * 0.28, radius * 0.32), radius * 0.28, Color(0.45, 0.45, 0.48, 0.55))
		_board_ctrl.draw_arc(center, radius, 0, TAU, 28, Color(0.02, 0.02, 0.02), 1.2)
	else:
		_board_ctrl.draw_circle(center, radius, Color(0.94, 0.93, 0.9))
		_board_ctrl.draw_circle(center - Vector2(radius * 0.25, radius * 0.3), radius * 0.22, Color(1, 1, 1, 0.7))
		_board_ctrl.draw_arc(center, radius, 0, TAU, 28, Color(0.45, 0.42, 0.38), 1.3)


func _draw_halma_pawn(center: Vector2, radius: float, red: bool) -> void:
	"""Plastic Halma pawn: cylinder-ish disc with bevel."""
	_board_ctrl.draw_circle(center + Vector2(1.4, 2.0), radius, Color(0, 0, 0, 0.3))
	var body := Color(0.82, 0.22, 0.16) if red else Color(0.22, 0.42, 0.88)
	var rim := Color(0.95, 0.5, 0.4) if red else Color(0.55, 0.7, 0.98)
	_board_ctrl.draw_circle(center, radius, body)
	_board_ctrl.draw_arc(center, radius, 0, TAU, 28, rim, 2.0)
	_board_ctrl.draw_circle(center - Vector2(radius * 0.2, radius * 0.25), radius * 0.35, Color(1, 1, 1, 0.28))
	_board_ctrl.draw_circle(center, radius * 0.38, Color(body.r * 1.15, body.g * 1.15, body.b * 1.1))


func _draw_board() -> void:
	var game := _view_game()
	if game == "junqi":
		_draw_junqi_board()
		return
	if game == "checkers":
		_draw_checkers_board()
		return
	_draw_gomoku_board()


func _draw_gomoku_board() -> void:
	"""Warm wood goban + glossy stones."""
	var s := _board_size()
	var px := _board_px()
	var c := px / float(s + 1)
	var detail := _view_detail()
	_draw_wood_frame(Vector2(px, px), Color(0.86, 0.7, 0.42))
	var margin := c
	# Grid
	for i in s:
		var p := margin + c * float(i)
		_board_ctrl.draw_line(Vector2(margin, p), Vector2(px - margin, p), Color(0.22, 0.14, 0.08), 1.6)
		_board_ctrl.draw_line(Vector2(p, margin), Vector2(p, px - margin), Color(0.22, 0.14, 0.08), 1.6)
	for star in [Vector2i(3, 3), Vector2i(11, 3), Vector2i(3, 11), Vector2i(11, 11), Vector2i(7, 7)]:
		_board_ctrl.draw_circle(_cell_center(star.x, star.y), 3.8, Color(0.18, 0.12, 0.07))
	var cells: Array = detail.get("cells", [])
	var win_set: Dictionary = {}
	for pt in detail.get("win_line", []):
		if typeof(pt) != TYPE_ARRAY:
			continue
		var arr := pt as Array
		if arr.size() < 2:
			continue
		win_set["%d,%d" % [int(arr[0]), int(arr[1])]] = true
	for y in s:
		for x in s:
			var idx := y * s + x
			var v := int(cells[idx]) if idx < cells.size() else 0
			var center := _cell_center(x, y)
			var key := "%d,%d" % [x, y]
			if win_set.has(key):
				_board_ctrl.draw_circle(center, c * 0.52, Color(1.0, 0.78, 0.2, 0.55))
			if v == GomokuScript.BLACK:
				_draw_stone(center, c * 0.38, true)
			elif v == GomokuScript.WHITE:
				_draw_stone(center, c * 0.38, false)


func _draw_checkers_board() -> void:
	"""Wood Halma board with camp tints + plastic pawns."""
	var s := _board_size()
	var px := _board_px()
	var c := px / float(s + 1)
	var detail := _view_detail()
	_draw_wood_frame(Vector2(px, px), Color(0.78, 0.62, 0.4))
	# Soft checker texture
	for y in s:
		for x in s:
			if (x + y) % 2 == 0:
				_board_ctrl.draw_rect(_cell_rect(x, y, c).grow(-1.0), Color(0.72, 0.56, 0.36, 0.55))
	for xy in [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [0, 2], [1, 2], [0, 3]]:
		_board_ctrl.draw_rect(_cell_rect(xy[0], xy[1], c).grow(-2.0), Color(0.9, 0.4, 0.28, 0.4))
	for xy in [[7, 7], [6, 7], [5, 7], [4, 7], [7, 6], [6, 6], [5, 6], [7, 5], [6, 5], [7, 4]]:
		_board_ctrl.draw_rect(_cell_rect(xy[0], xy[1], c).grow(-2.0), Color(0.3, 0.5, 0.92, 0.4))
	for i in s:
		var p := c * float(i + 1)
		_board_ctrl.draw_line(Vector2(c * 0.5, p), Vector2(px - c * 0.5, p), Color(0.3, 0.18, 0.08, 0.55), 1.2)
		_board_ctrl.draw_line(Vector2(p, c * 0.5), Vector2(p, px - c * 0.5), Color(0.3, 0.18, 0.08, 0.55), 1.2)
	var cells: Array = detail.get("cells", [])
	for y in s:
		for x in s:
			var idx := y * s + x
			var v := int(cells[idx]) if idx < cells.size() else 0
			var center := _cell_center(x, y)
			if _sel.x == x and _sel.y == y:
				_board_ctrl.draw_circle(center, c * 0.48, Color(0.95, 0.85, 0.2, 0.45))
			if v == GomokuScript.BLACK:
				_draw_halma_pawn(center, c * 0.36, true)
			elif v == GomokuScript.WHITE:
				_draw_halma_pawn(center, c * 0.36, false)


func _view_detail() -> Dictionary:
	var d: Dictionary = _tables.get(_view_table_id, {}) as Dictionary
	if d.is_empty() and TABLE_META.has(_view_table_id):
		var meta: Dictionary = TABLE_META[_view_table_id]
		return {
			"table_id": _view_table_id,
			"game": meta.get("game", "gomoku"),
			"title_zh": meta.get("title_zh", ""),
			"title_en": meta.get("title_en", ""),
			"status": "idle",
			"cells": [],
		}
	if str(d.get("game", "")) != "junqi" or _session_id == "":
		return d
	var views: Variant = d.get("junqi_views", {})
	if typeof(views) != TYPE_DICTIONARY or not views.has(_session_id):
		return d
	var mine: Dictionary = (views[_session_id] as Dictionary).duplicate(true)
	var out := d.duplicate(true)
	for k in mine.keys():
		out[k] = mine[k]
	if str(mine.get("phase", "")) != "":
		out["status"] = str(mine.get("phase"))
	return out


func _view_game() -> String:
	return str(_view_detail().get("game", "gomoku"))


func _board_size() -> int:
	if _view_game() == "checkers":
		return 8
	return GomokuScript.SIZE


func _cell_px() -> float:
	return _board_px() / float(_board_size() + 1)


func _my_color() -> int:
	var d := _view_detail()
	if str(d.get("black_sid", "")) == _session_id:
		return GomokuScript.BLACK
	if str(d.get("white_sid", "")) == _session_id and not bool(d.get("vs_ai", false)):
		return GomokuScript.WHITE
	return GomokuScript.EMPTY


func _my_junqi_side() -> String:
	var d := _view_detail()
	if str(d.get("black_sid", "")) == _session_id:
		return "black"
	if str(d.get("white_sid", "")) == _session_id and not bool(d.get("vs_ai", false)):
		return "red"
	return ""


func _sync_junqi_chrome(status: String) -> void:
	var is_jq := _view_game() == "junqi"
	var my := _my_junqi_side()
	var seated := my != "" or _my_color() != GomokuScript.EMPTY
	if _rules_btn != null:
		_rules_btn.visible = is_jq
		if is_jq:
			_rules_btn.text = (
				MWi18n.t("隐藏规则", "Hide rules")
				if _rules_visible
				else MWi18n.t("规则说明", "Rules")
			)
	if _rules_label != null:
		_rules_label.visible = is_jq and _rules_visible
	var draft := false
	if is_jq and status == "layout" and my != "":
		var ready: Dictionary = _view_detail().get("layout_ready", {}) as Dictionary
		var own_n := _junqi_own_piece_count()
		draft = own_n >= 25 and not bool(ready.get(my, false))
		if _layout_btn != null:
			_layout_btn.visible = true
			_layout_btn.text = (
				MWi18n.t("再随机", "Re-roll")
				if own_n > 0
				else MWi18n.t("随机布阵", "Auto layout")
			)
		if _confirm_btn != null:
			_confirm_btn.visible = draft
	else:
		if _layout_btn != null:
			_layout_btn.visible = false
		if _confirm_btn != null:
			_confirm_btn.visible = false
	if _resign_btn != null:
		_resign_btn.visible = seated and status == "playing"
	if _hand_btn != null:
		_hand_btn.visible = seated and status in ["layout", "playing"]
	_fit_board_panel()
	# Board ctrl size set inside _fit_board_panel.


func _junqi_own_piece_count() -> int:
	var my := _my_junqi_side()
	if my == "":
		return 0
	var n := 0
	for cell in _view_detail().get("cells", []):
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		var p: Variant = cell.get("piece", null)
		if typeof(p) != TYPE_DICTIONARY or p == null:
			continue
		if str(p.get("side", "")) == my and str(p.get("type", "?")) != "?":
			n += 1
	return n


func _junqi_layout_from_cells() -> Dictionary:
	"""Build layout dict from personal fog view (own typed pieces)."""
	var my := _my_junqi_side()
	var counts: Dictionary = {}
	var layout: Dictionary = {}
	for cell in _view_detail().get("cells", []):
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		var p: Variant = cell.get("piece", null)
		if typeof(p) != TYPE_DICTIONARY or p == null:
			continue
		if str(p.get("side", "")) != my:
			continue
		var ptype := str(p.get("type", ""))
		if ptype == "" or ptype == "?":
			continue
		var i := int(counts.get(ptype, 0))
		counts[ptype] = i + 1
		layout["%s_%d" % [ptype, i]] = [int(cell.get("r", 0)), int(cell.get("c", 0))]
	return layout


func _refresh_board_from_authority() -> void:
	var d := _view_detail()
	var game := str(d.get("game", "gomoku"))
	var vs_ai := bool(d.get("vs_ai", false))
	var title := MWi18n.t(str(d.get("title_zh", "")), str(d.get("title_en", "")))
	if title == "":
		title = _view_table_id
	if _title_label != null:
		if vs_ai:
			_title_label.text = title + MWi18n.t(" · 人机", " · vs AI")
		else:
			_title_label.text = title + MWi18n.t(" · 人对人", " · PvP")
	var status := str(d.get("status", "idle"))
	_sync_junqi_chrome(status)
	if _result_label != null:
		_result_label.visible = false
	if game == "junqi":
		_refresh_junqi_status(d, status, vs_ai)
		if _board_ctrl != null:
			_board_ctrl.queue_redraw()
		return
	var winner := int(d.get("winner", 0))
	var turn := int(d.get("turn", 1))
	var my := _my_color()
	if status == "finished":
		var result := ""
		if winner == GomokuScript.BLACK:
			result = MWi18n.t("● 黑/红方获胜", "● Black/Red wins")
		elif winner == GomokuScript.WHITE:
			result = MWi18n.t("○ 白/蓝方获胜", "○ White/Blue wins")
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
		if game == "checkers":
			_set_status(MWi18n.t("选己子再点目标格（邻步或跳）", "Pick your piece, then a target (step/jump)"))
		else:
			_set_status(MWi18n.t("轮到你了 · 点击落子", "Your move — click"))
	elif vs_ai:
		_set_status(MWi18n.t("AI 思考中…", "AI thinking…"))
	else:
		_set_status(MWi18n.t("等待对手…", "Waiting for opponent…"))
	if _board_ctrl != null:
		_board_ctrl.queue_redraw()


func _refresh_junqi_status(d: Dictionary, status: String, vs_ai: bool) -> void:
	"""Status line + endgame for junqi fog board."""
	var my := _my_junqi_side()
	var ready: Dictionary = d.get("layout_ready", {}) as Dictionary
	var hand: Variant = d.get("last_hand", null)
	var hand_note := ""
	if typeof(hand) == TYPE_DICTIONARY and hand != null:
		if str(hand.get("sid", "")) != _session_id:
			hand_note = MWi18n.t("\n对方举手", "\nOpponent raised hand")
		else:
			hand_note = MWi18n.t("\n已举手", "\nHand raised")
	if status == "layout" or status == "idle":
		if my == "":
			_set_status(MWi18n.t("旁观 · 等待入座布阵", "Spectating · waiting for layout") + hand_note)
			return
		var mine_ok := bool(ready.get(my, false))
		var own_n := _junqi_own_piece_count()
		if mine_ok:
			_set_status(MWi18n.t("已确认 · 等待对方就绪", "Confirmed · waiting for opponent") + hand_note)
		elif own_n >= 25:
			_set_status(MWi18n.t(
				"可拖换己子微调 · 点「确认布阵」开战",
				"Drag-swap to tune · tap Confirm to start"
			) + hand_note)
		else:
			_set_status(MWi18n.t("布阵 · 先「随机布阵」，可再手调", "Layout · Auto layout, then tune") + hand_note)
		return
	if status == "finished":
		var winner := str(d.get("winner", ""))
		var result := MWi18n.t("终局", "Game over")
		if winner == "black":
			result = MWi18n.t("黑方获胜", "Black wins")
		elif winner == "red":
			result = MWi18n.t("红方获胜", "Red wins")
		if my != "" and my == winner:
			result = MWi18n.t("你赢了！", "You win!") + "  " + result
		elif my != "" and winner != "" and my != winner:
			result = MWi18n.t("你输了", "You lose") + "  " + result
		_set_status(MWi18n.t("即将自动起身…", "Standing up shortly…"))
		if _result_label != null:
			_result_label.text = result
			_result_label.visible = true
		_schedule_auto_exit()
		return
	if my == "":
		_set_status(MWi18n.t("旁观中", "Spectating") + hand_note)
		return
	var turn := str(d.get("turn", ""))
	if turn == my:
		_set_status(MWi18n.t("轮到你 · 点己子再点目标格", "Your turn · pick piece, then target") + hand_note)
	elif vs_ai:
		_set_status(MWi18n.t("AI 思考中…", "AI thinking…") + hand_note)
	else:
		_set_status(MWi18n.t("等待对手…", "Waiting for opponent…") + hand_note)
	var battle: Variant = d.get("last_battle", null)
	if typeof(battle) == TYPE_DICTIONARY and battle != null:
		var res := str(battle.get("result", ""))
		if res != "" and _status_label != null:
			var atk := str(battle.get("attacker", "?"))
			var dfd := str(battle.get("defender", "?"))
			_set_status(
				_status_label.text
				+ "\n"
				+ MWi18n.t("碰撞：", "Clash: ")
				+ str(JUNQI_LABEL.get(atk, atk))
				+ " → "
				+ str(JUNQI_LABEL.get(dfd, dfd))
				+ " · "
				+ res
			)


func _schedule_auto_exit() -> void:
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


func _draw_junqi_board() -> void:
	"""Wood-framed green board + tile pieces; local side at bottom."""
	var detail := _view_detail()
	var sz := _junqi_board_size()
	_draw_wood_frame(sz, Color(0.52, 0.68, 0.42))
	var m: Dictionary = _junqi_layout_metrics()
	var cw: float = m["cw"]
	var ch: float = m["ch"]
	var origin: Vector2 = m["origin"]
	var cells: Array = detail.get("cells", [])
	var by_key: Dictionary = {}
	for cell in cells:
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		by_key["%d,%d" % [int(cell.get("r", -1)), int(cell.get("c", -1))]] = cell
	for c in JUNQI_COLS:
		var vr5 := _junqi_view_r(5)
		var vr6 := _junqi_view_r(6)
		var y_mid := origin.y + ch * (float(vr5 + vr6) * 0.5 + 0.5)
		if c in [1, 3]:
			var cx := origin.x + cw * (float(c) + 0.5)
			_board_ctrl.draw_rect(
				Rect2(cx - cw * 0.42, y_mid - ch * 0.22, cw * 0.84, ch * 0.44),
				Color(0.45, 0.36, 0.22)
			)
	for r in JUNQI_ROWS:
		for c in JUNQI_COLS:
			var vr := _junqi_view_r(r)
			var center := origin + Vector2(cw * (float(c) + 0.5), ch * (float(vr) + 0.5))
			var half := Vector2(cw, ch) * 0.42
			var rect := Rect2(center - half, half * 2.0)
			var cell: Dictionary = by_key.get("%d,%d" % [r, c], {})
			var kind := str(cell.get("kind", "station"))
			if kind == "hq":
				_board_ctrl.draw_rect(rect, Color(0.78, 0.62, 0.28))
				_board_ctrl.draw_rect(rect.grow(-2.0), Color(0.9, 0.78, 0.4), false, 1.5)
			elif kind == "camp":
				_board_ctrl.draw_circle(center, min(cw, ch) * 0.38, Color(0.62, 0.78, 0.92))
				_board_ctrl.draw_arc(center, min(cw, ch) * 0.38, 0, TAU, 28, Color(0.25, 0.4, 0.55), 1.6)
			else:
				_board_ctrl.draw_rect(rect, Color(0.58, 0.74, 0.48, 0.55))
				_board_ctrl.draw_rect(rect, Color(0.28, 0.38, 0.22), false, 1.0)
			if _sel.x == c and _sel.y == r:
				_board_ctrl.draw_rect(rect.grow(1.0), Color(0.95, 0.85, 0.2, 0.55), false, 2.5)
	_draw_junqi_rails(origin, cw, ch)
	for r in JUNQI_ROWS:
		for c in JUNQI_COLS:
			var cell2: Dictionary = by_key.get("%d,%d" % [r, c], {})
			var piece: Variant = cell2.get("piece", null)
			if typeof(piece) != TYPE_DICTIONARY or piece == null:
				continue
			var vr2 := _junqi_view_r(r)
			var center2 := origin + Vector2(cw * (float(c) + 0.5), ch * (float(vr2) + 0.5))
			_draw_junqi_tile(
				center2,
				min(cw, ch),
				str(piece.get("side", "")),
				str(piece.get("type", "?"))
			)


func _draw_junqi_rails(origin: Vector2, cw: float, ch: float) -> void:
	"""Sketch railway rings on both halves (visual cue, not authority)."""
	var col_rail := Color(0.2, 0.18, 0.12, 0.75)
	var segs: Array = [
		[[1, 0], [1, 4]], [[5, 0], [5, 4]], [[1, 0], [5, 0]], [[1, 4], [5, 4]],
		[[6, 0], [6, 4]], [[10, 0], [10, 4]], [[6, 0], [10, 0]], [[6, 4], [10, 4]],
		[[5, 0], [6, 0]], [[5, 4], [6, 4]],
	]
	for seg in segs:
		var a: Array = seg[0]
		var b: Array = seg[1]
		var p0 := origin + Vector2(
			cw * (float(a[1]) + 0.5),
			ch * (float(_junqi_view_r(int(a[0]))) + 0.5)
		)
		var p1 := origin + Vector2(
			cw * (float(b[1]) + 0.5),
			ch * (float(_junqi_view_r(int(b[0]))) + 0.5)
		)
		_board_ctrl.draw_line(p0, p1, col_rail, 2.0)


func _draw_junqi_tile(center: Vector2, cell: float, side: String, ptype: String) -> void:
	"""Draw a bevelled rectangular tile like physical junqi pieces."""
	var tw := cell * 0.72
	var th := cell * 0.58
	var rect := Rect2(center - Vector2(tw, th) * 0.5, Vector2(tw, th))
	_board_ctrl.draw_rect(Rect2(rect.position + Vector2(1.5, 2.0), rect.size), Color(0, 0, 0, 0.35))
	var body := Color(0.12, 0.12, 0.14) if side == "black" else Color(0.78, 0.18, 0.14)
	var rim := Color(0.35, 0.35, 0.38) if side == "black" else Color(0.95, 0.45, 0.35)
	_board_ctrl.draw_rect(rect, body)
	_board_ctrl.draw_rect(rect, rim, false, 1.4)
	_board_ctrl.draw_line(
		rect.position + Vector2(1, 1),
		rect.position + Vector2(rect.size.x - 1, 1),
		Color(1, 1, 1, 0.22),
		1.0
	)
	var label := str(JUNQI_LABEL.get(ptype, ptype))
	var font: Font = MWFonts.font() if MWFonts != null else ThemeDB.fallback_font
	var fs := int(clampf(min(tw, th) * 0.55, 10.0, 22.0))
	var text_col := Color(0.95, 0.92, 0.75) if side == "black" else Color(1.0, 0.96, 0.88)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_board_ctrl.draw_string(
		font,
		center - text_size * 0.5 + Vector2(0, text_size.y * 0.35),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		fs,
		text_col
	)


func _junqi_layout_metrics() -> Dictionary:
	"""Shared draw/hit metrics for junqi board."""
	var sz := _junqi_board_size()
	var pad := 8.0
	var inner := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
	var cw := inner.size.x / float(JUNQI_COLS + 0.35)
	var ch := inner.size.y / float(JUNQI_ROWS + 0.35)
	var origin := inner.position + Vector2(cw * 0.175, ch * 0.175)
	return {"origin": origin, "cw": cw, "ch": ch}


func _cell_rect(x: int, y: int, c: float) -> Rect2:
	var center := _cell_center(x, y)
	return Rect2(center - Vector2(c, c) * 0.5, Vector2(c, c))


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
	var game := str(d.get("game", "gomoku"))
	if game == "junqi":
		_on_junqi_board_click(mb.position, d)
		return
	if str(d.get("status", "")) != "playing":
		return
	var my := _my_color()
	if my == GomokuScript.EMPTY or int(d.get("turn", 0)) != my:
		return
	var c := _cell_px()
	var x := int(round(mb.position.x / c)) - 1
	var y := int(round(mb.position.y / c)) - 1
	var s := _board_size()
	if x < 0 or y < 0 or x >= s or y >= s:
		return
	if game == "gomoku":
		ws.send_cmd({
			"action": "chess_place",
			"table_id": _view_table_id,
			"x": x,
			"y": y,
		})
		return
	# Checkers: select then move.
	var cells: Array = d.get("cells", [])
	var idx := y * s + x
	var v := int(cells[idx]) if idx < cells.size() else 0
	if _sel.x < 0:
		if v == my:
			_sel = Vector2i(x, y)
			_board_ctrl.queue_redraw()
		return
	if v == my:
		_sel = Vector2i(x, y)
		_board_ctrl.queue_redraw()
		return
	ws.send_cmd({
		"action": "chess_move",
		"table_id": _view_table_id,
		"fx": _sel.x,
		"fy": _sel.y,
		"tx": x,
		"ty": y,
	})
	_sel = Vector2i(-1, -1)


func _on_junqi_board_click(pos: Vector2, d: Dictionary) -> void:
	"""Layout: swap own pieces; playing: move (fx/fy = row/col)."""
	var status := str(d.get("status", ""))
	var my := _my_junqi_side()
	if my == "":
		return
	var m: Dictionary = _junqi_layout_metrics()
	var origin: Vector2 = m["origin"]
	var cw: float = m["cw"]
	var ch: float = m["ch"]
	var col := int(floor((pos.x - origin.x) / cw))
	var view_r := int(floor((pos.y - origin.y) / ch))
	if col < 0 or view_r < 0 or col >= JUNQI_COLS or view_r >= JUNQI_ROWS:
		return
	var row := _junqi_model_r(view_r)
	if status == "layout":
		var ready: Dictionary = d.get("layout_ready", {}) as Dictionary
		if bool(ready.get(my, false)):
			return
		_on_junqi_layout_click(row, col, d, my)
		return
	if status != "playing":
		return
	if str(d.get("turn", "")) != my:
		return
	var cells: Array = d.get("cells", [])
	var piece_side := ""
	for cell in cells:
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		if int(cell.get("r", -1)) != row or int(cell.get("c", -1)) != col:
			continue
		var piece: Variant = cell.get("piece", null)
		if typeof(piece) == TYPE_DICTIONARY and piece != null:
			piece_side = str(piece.get("side", ""))
		break
	if _sel.x < 0:
		if piece_side == my:
			_sel = Vector2i(col, row)
			_board_ctrl.queue_redraw()
		return
	if piece_side == my:
		_sel = Vector2i(col, row)
		_board_ctrl.queue_redraw()
		return
	ws.send_cmd({
		"action": "chess_move",
		"table_id": _view_table_id,
		"fx": _sel.y,
		"fy": _sel.x,
		"tx": row,
		"ty": col,
	})
	_sel = Vector2i(-1, -1)


func _on_junqi_layout_click(row: int, col: int, d: Dictionary, my: String) -> void:
	"""Swap two own pieces (or move onto empty non-camp) then re-submit draft."""
	# Own half only.
	if my == "black" and row > 5:
		return
	if my == "red" and row < 6:
		return
	var cells: Array = d.get("cells", [])
	var kind := "station"
	var piece_side := ""
	var piece_type := ""
	for cell in cells:
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		if int(cell.get("r", -1)) != row or int(cell.get("c", -1)) != col:
			continue
		kind = str(cell.get("kind", "station"))
		var piece: Variant = cell.get("piece", null)
		if typeof(piece) == TYPE_DICTIONARY and piece != null:
			piece_side = str(piece.get("side", ""))
			piece_type = str(piece.get("type", ""))
		break
	if kind == "camp":
		return
	if _sel.x < 0:
		if piece_side == my and piece_type != "?":
			_sel = Vector2i(col, row)
			_board_ctrl.queue_redraw()
		return
	var sr := _sel.y
	var sc := _sel.x
	if sr == row and sc == col:
		_sel = Vector2i(-1, -1)
		_board_ctrl.queue_redraw()
		return
	# Build layout, swap (sr,sc) <-> (row,col) or move onto empty.
	var layout := _junqi_layout_from_cells()
	if layout.is_empty():
		return
	var key_a := ""
	var key_b := ""
	for k in layout.keys():
		var pos: Array = layout[k]
		if int(pos[0]) == sr and int(pos[1]) == sc:
			key_a = str(k)
		if int(pos[0]) == row and int(pos[1]) == col:
			key_b = str(k)
	if key_a == "":
		_sel = Vector2i(-1, -1)
		return
	if key_b != "":
		layout[key_a] = [row, col]
		layout[key_b] = [sr, sc]
	else:
		layout[key_a] = [row, col]
	_sel = Vector2i(-1, -1)
	ws.send_cmd({
		"action": "junqi_layout",
		"table_id": _view_table_id,
		"layout": layout,
		"ready": false,
	})


func _set_status(msg: String) -> void:
	if _status_label != null:
		_status_label.text = msg
