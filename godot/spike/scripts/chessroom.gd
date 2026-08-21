## Chess lounge: Hub FakeMech presence + multi-game tables (gomoku / checkers / junqi).
## Join demo_chessroom / room=chess; F sit; Esc → Hub.
extends Node3D

const MOVE_SPEED := 2.8
const TURN_SPEED := 2.2
const CMD_HZ := 20.0
const CMD_HZ_SPLAT := 10.0  ## dual-WebGL: slower cmd so JS socket can drain
const SIT_DIST := 2.4
const AVATAR_SCENE := preload("res://avatar_puppet.tscn")
const GomokuScript := preload("res://scripts/gomoku.gd")
const MWQuickSit := preload("res://scripts/mw/quick_sit.gd")
const MWEmotes := preload("res://scripts/mw/emotes.gd")
const MWInviteLink := preload("res://scripts/mw/invite_link.gd")
const MWSplatBridge := preload("res://scripts/mw/splat_bridge.gd")
const AUTO_EXIT_S := 2.4
const JUNQI_ROWS := MWJunqiGeom.ROWS
const JUNQI_COLS := MWJunqiGeom.COLS
## Short labels for board chips (SSOT types).
const JUNQI_LABEL := MWJunqiGeom.LABEL
## Fallback meta until first chess_table_update arrives.
const TABLE_META := {
	"table_1": {"game": "gomoku", "title_zh": "五子棋 · 甲桌", "title_en": "Gomoku A", "accent": Color(0.95, 0.55, 0.2)},
	"table_2": {"game": "blackjack", "title_zh": "21 点 · 乙桌", "title_en": "Blackjack", "accent": Color(0.95, 0.7, 0.35)},
	"table_3": {"game": "checkers", "title_zh": "跳棋", "title_en": "Halma", "accent": Color(0.35, 0.75, 0.95)},
	"table_4": {"game": "junqi", "title_zh": "军棋", "title_en": "Junqi", "accent": Color(0.75, 0.45, 0.9)},
	"table_5": {"game": "gomoku", "title_zh": "五子棋 · 丙桌", "title_en": "Gomoku C", "accent": Color(0.85, 0.6, 0.25)},
	"table_6": {"game": "wudui", "title_zh": "五对 · 双人桌", "title_en": "WuDui 2P", "accent": Color(0.95, 0.5, 0.6)},
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
var _last_idle_cmd := false
var _move_send_ctr := 0
var _puppets: Dictionary = {}
var _profile: Dictionary = {}
var _board_layer: CanvasLayer = null
var _board_panel: PanelContainer = null
var _board_ctrl: Control = null
var _status_label: Label = null
var _title_label: Label = null
var _result_label: Label = null
var _tips_label: Label = null
var _ai_fill_at := 0.0  # unix deadline for wudui AI-fill countdown (0 = none)
var _ai_countdown_label: Label = null
var _ai_countdown_timer: Timer = null
var _layout_btn: Button = null
var _confirm_btn: Button = null
var _resign_btn: Button = null
var _hand_btn: Button = null
var _rules_btn: Button = null
var _hit_btn: Button = null
var _stand_btn: Button = null
var _deal_btn: Button = null
var _quick_sit_btn: Button = null
var _wudui_sel := ""
var _wudui_btn_rect := Rect2()
var _wudui_anims: Dictionary = {}
var _wudui_prev: Dictionary = {}
var _wudui_celebrated := false
var _wudui_discard_btn: Button = null
var _wudui_eat_btn: Button = null
var _wudui_pass_btn: Button = null
var _rules_label: Label = null
var _rules_visible := false
var _tables: Dictionary = {}
var _view_table_id := ""
var _seated_table_id := ""
var _auto_exit_gen := 0
var _sel := Vector2i(-1, -1)
## Set while a junqi chess_move is in flight; cleared on table update / reject.
var _pending_junqi_move: Dictionary = {}
## Chess-FX: per-cell piece animation state. Key "x,y" → {kind, t, dur}.
## kind: "place" (scale bounce), "capture" (fade+sink), "flip" (junqi reveal).
var _piece_anims: Dictionary = {}
## Blackjack (21点): card anims keyed "P0"/"D1" → {kind, t, dur}; prev hands for diffing.
var _bj_anims: Dictionary = {}
var _bj_prev: Dictionary = {}
var _prev_cells: Array = []  ## previous board cells for diff detection
var _splat_on := false
var _splat_pose_timer := 0.0
var _splat_shell_hidden := false
var _splat_poll_n := 0


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_profile = _load_profile()
	if scene_avatar != null:
		scene_avatar.visible = false
	if camera_rig != null and "turn_drive_enabled" in camera_rig:
		camera_rig.turn_drive_enabled = true
	# docs/33: start Spark only after we push a camera pose (avoid boot race).
	# Use Callable.call_deferred — string call_deferred can report Method not found on Web.
	if MWSplatBridge.enabled(level_id):
		_splat_on = true
		MWSplatBridge.apply_chessroom_skin(self)
		_splat_boot_deferred.call_deferred()
	MWTutorial.attach(self, level_id)
	# Viewer-only prop dress (Kenney furniture + PolyHaven Chinese set).
	# Splat skin replaces the shell walls — skip dress there (props would float
	# against invisible geometry; placement assumes the 32x22 shell).
	if not _splat_on:
		var dress := Node3D.new()
		dress.name = "ChessroomDress"
		dress.set_script(load("res://scripts/chessroom_dress.gd"))
		add_child(dress)
	_label_tables()
	_push_chess_shell_tips()
	if _is_web:
		if not MWWebInput.web_key_event.is_connected(_on_web_key_event):
			MWWebInput.web_key_event.connect(_on_web_key_event)
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(true,false,true);}",
			true
		)
		# Room chat DOM bar (same shell chat as hub/city/race).
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_ROOM_CHAT==='function'){window.MW_SET_ROOM_CHAT(true);}",
			true
		)
	_build_board_ui()
	_build_quick_sit_button()
	_build_invite_button()
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
		+ "甲桌：五子棋 · 乙桌：21 点 · 丙桌：跳棋 · 丁桌：军棋\n"
		+ "WASD 平移 · Q/E 转向 · 人机可单人开局，第二人入座变对战",
		"Chess Lounge\n"
		+ "Walk to a table · F sit · Esc stand / Hub\n"
		+ "A Gomoku · B Blackjack · C Halma · D Junqi\n"
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
			"棋牌室 · 走近棋桌按 F · 甲乙丙五子棋 / 丁跳棋 / 戊军棋 / 己五对",
			"Chess · F to sit · A/B/C Gomoku · D Halma · E Junqi · F WuDui"
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
	var skin := ""
	if _is_web:
		var raw := str(JavaScriptBridge.eval(
			"(function(){try{var p=JSON.parse(localStorage.getItem('mw_profile')||'{}');return String(p.skin||'')}catch(e){return ''}})()",
			true
		)).strip_edges().to_lower()
		if raw.length() == 1 and "abcdefghijklmnopqr".find(raw) >= 0:
			skin = raw
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
	return {"nickname": nick, "accent": accent, "id": "", "skin": skin}


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
			"skin": str(_profile.get("skin", "")),
		}
	}
	ws.join(level_id, nick, _joined_room_id, {"mw": mw})


func _on_scene(payload: Dictionary) -> void:
	_controlled = false
	var ext: Dictionary = payload.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var mw: Variant = ext.get("mw", {})
		if typeof(mw) == TYPE_DICTIONARY:
			# P1-2: contract-declared splat skin (no URL param needed).
			var skin := str(mw.get("skin", ""))
			if not _splat_on and skin.begins_with("splat:") and OS.has_feature("web"):
				var ok: Variant = JavaScriptBridge.eval(
					"(function(){return (typeof window.MW_SPLAT_SET==='function')?window.MW_SPLAT_SET('%s'):false})()"
					% skin.trim_prefix("splat:"),
					true
				)
				if ok == true:
					_splat_on = true
					MWSplatBridge.apply_chessroom_skin(self)
					_splat_boot_deferred.call_deferred()
					# Async skin (contract-pushed) after dress attach: free props
					# — shell walls hide, furniture would float.
					var dress := get_node_or_null("ChessroomDress")
					if dress != null:
						dress.queue_free()
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
	"""Spawn paper dolls only for self or occupied remotes."""
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
		var is_self := eid == _controlled_entity_id
		if not is_self:
			var ext: Variant = entity.get("extensions", {})
			var occ := false
			if typeof(ext) == TYPE_DICTIONARY:
				var mw: Variant = ext.get("mw", {})
				if typeof(mw) == TYPE_DICTIONARY:
					occ = bool(mw.get("occupied", false))
			if not occ:
				continue
		var node: Node3D = AVATAR_SCENE.instantiate()
		node.name = eid
		node.set("entity_id", eid)
		node.visible = is_self
		if is_self:
			node.set("accent", Color(str(_profile.get("accent", "#9a5ae8"))))
			node.set("display_name", str(_profile.get("nickname", "Guest")))
			if str(_profile.get("skin", "")) != "":
				node.set("skin_letter", str(_profile.get("skin")))
			node.set("local_predict", true)
			node.set("interp_delay", 0.03)
		add_child(node)
		_puppets[eid] = node


func _own_avatar() -> Node3D:
	if _puppets.has(_controlled_entity_id):
		return _puppets[_controlled_entity_id]
	return null


func _on_state(_tick: int, t_sim: float, payload: Dictionary) -> void:
	"""Drive puppets; hide empty slots. Do NOT hide on delta miss (avoids flicker)."""
	for entity in payload.get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if not eid.begins_with("avatar_"):
			continue
		var ext: Variant = entity.get("extensions", {})
		var mw: Variant = {}
		if typeof(ext) == TYPE_DICTIONARY:
			mw = ext.get("mw", {})
		# Default false — empty FakeMech slots omit occupied; must stay hidden.
		var is_occ := false
		if typeof(mw) == TYPE_DICTIONARY and bool(mw.get("occupied", false)):
			is_occ = true
		var is_self := eid == _controlled_entity_id
		if not is_occ and not is_self:
			# Drop empty slot puppets if we already spawned them.
			if _puppets.has(eid):
				var ghost: Node3D = _puppets[eid]
				ghost.visible = false
			continue
		if not _puppets.has(eid):
			_ensure_puppets([entity])
		var puppet: Node3D = _puppets.get(eid)
		if puppet == null:
			continue
		puppet.visible = true
		if puppet.has_method("push_state"):
			puppet.call("push_state", entity, t_sim)
		if typeof(mw) == TYPE_DICTIONARY and not is_self:
			if str(mw.get("display_name", "")) != "":
				puppet.set("display_name", str(mw.get("display_name")))
			if str(mw.get("accent", "")) != "":
				puppet.set("accent", Color(str(mw.get("accent"))))


func _on_chat_event(payload: Dictionary) -> void:
	"""Room chat log + bubble on the speaker avatar (hub pattern)."""
	var detail: Variant = payload.get("detail", {})
	if typeof(detail) != TYPE_DICTIONARY:
		detail = {}
	var text := str((detail as Dictionary).get("text", "")).strip_edges()
	if text == "":
		return
	var from_name := str((detail as Dictionary).get("from", "Guest")).strip_edges()
	if from_name == "":
		from_name = "Guest"
	_append_chat_log(from_name, text)
	var eid := str(payload.get("entity_id", ""))
	if eid != "" and _puppets.has(eid):
		var puppet: Node = _puppets[eid]
		if puppet != null and puppet.has_method("show_chat"):
			puppet.call("show_chat", text)


func _append_chat_log(from_name: String, text: String) -> void:
	"""Push one line into DOM chat log (Web) or stdout (desktop dev)."""
	if _is_web:
		var payload := JSON.stringify({"from": from_name, "text": text})
		JavaScriptBridge.eval(
			"(function(){var p=%s;if(typeof window.MW_APPEND_HUB_CHAT==='function'){window.MW_APPEND_HUB_CHAT(p);}})()" % payload,
			true
		)
		return
	print("[MW] chess chat %s: %s" % [from_name, text])


func _poll_web_chat() -> void:
	"""Send pending DOM room chat as cmd.action=chat."""
	if not _is_web:
		return
	var raw := str(JavaScriptBridge.eval(
		"(function(){var n=window.MW_HUB_CHAT_PENDING;window.MW_HUB_CHAT_PENDING=null;return n||''})()",
		true
	))
	if raw == "":
		return
	_send_chat(raw)


func _send_chat(text: String) -> void:
	"""Gateway room chat cmd (any joined room)."""
	var s := text.strip_edges()
	if s == "" or ws == null:
		return
	if not _controlled:
		return
	if s.length() > 80:
		s = s.substr(0, 80)
	var payload := {"action": "chat", "text": s}
	if _controlled_entity_id != "":
		payload["entity_id"] = _controlled_entity_id
	ws.send_cmd(payload)


func _on_emote_pick(text: String) -> void:
	"""Fun-E: emote button → room chat (bubble + log handled by _on_chat_event)."""
	_send_chat(text)


func _on_event(payload: Dictionary) -> void:
	var et := str(payload.get("event_type", ""))
	if et == "player_take_control":
		_controlled = true
		return
	if et == "player_release_control":
		_controlled = false
		return
	if et == "chat":
		_on_chat_event(payload)
		return
	if et == "chess_reject":
		_on_chess_reject(payload.get("detail", {}))
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
	var sid := _effective_sid()
	if sid != "" and (
		str(detail.get("black_sid", "")).strip_edges() == sid
		or str(detail.get("white_sid", "")).strip_edges() == sid
	):
		_seated_table_id = tid
	elif _seated_table_id == tid:
		_seated_table_id = ""
	if _board_open() and _view_table_id == tid:
		if not _pending_junqi_move.is_empty():
			_pending_junqi_move = {}
			_sel = Vector2i(-1, -1)
		_ai_fill_at = float(detail.get("ai_fill_at", 0.0))
		_sync_ai_countdown()
		_refresh_board_from_authority()


func _on_chess_reject(detail: Variant) -> void:
	"""Illegal junqi move/layout — keep selection, show why."""
	_pending_junqi_move = {}
	var code := ""
	if typeof(detail) == TYPE_DICTIONARY:
		code = str(detail.get("code", ""))
	if code == "TABLE_FULL":
		# Fun-E: full table → stay in the opened board as spectator.
		_set_status(MWi18n.t("桌已满 · 旁观模式（可发快捷表情喝彩）", "Table full · spectating (emotes below)"))
	elif code.begins_with("JUNQI_MOVE"):
		_set_status(MWi18n.t("非法走子 · 再选己子与目标", "Illegal move · reselect"))
	elif code.begins_with("JUNQI_LAYOUT"):
		_set_status(MWi18n.t("布阵无效 · 先随机或调整己子", "Invalid layout · auto or adjust"))
	else:
		_set_status(MWi18n.t("操作被拒绝", "Action rejected"))
	if _board_ctrl != null:
		_board_ctrl.queue_redraw()


func _on_gateway_error(payload: Dictionary) -> void:
	print("[MW] chessroom gateway error: ", payload)


func _splat_boot_deferred() -> void:
	"""Push one pose, then ask JS to start Spark (no URL deep-link race)."""
	if not _splat_on:
		return
	MWSplatBridge.push_pose(get_viewport().get_camera_3d())
	# Small delay so Godot WebGL is past first frames.
	get_tree().create_timer(0.8).timeout.connect(_splat_start_js)


func _splat_start_js() -> void:
	"""Start JS Spark then poll for active / failure."""
	MWSplatBridge.start_js()
	_splat_poll_n = 0
	_splat_wait_active.call_deferred()


func _splat_wait_active() -> void:
	"""Poll JS: hide shell when drawing; restore shell if Spark failed."""
	if not _splat_on or not _is_web:
		return
	var failed := str(JavaScriptBridge.eval(
		"(function(){try{return window.MW_SPLAT_FAILED||''}catch(e){return ''}})()",
		true
	)).strip_edges()
	if failed != "":
		MWSplatBridge.show_chessroom_shell(self)
		_splat_shell_hidden = false
		print("[MW] chessroom splat failed (", failed, ") — shell restored, input OK")
		return
	var active := int(str(JavaScriptBridge.eval(
		"(function(){try{return window.MW_SPLAT_ACTIVE|0}catch(e){return 0}})()",
		true
	)).strip_edges())
	if active > 0 and not _splat_shell_hidden:
		var composite := str(JavaScriptBridge.eval(
			"(function(){try{return window.MW_SPLAT_COMPOSITE_OK||''}catch(e){return ''}})()",
			true
		)).strip_edges()
		if composite != "1":
			# No Godot canvas alpha → hiding shell = black void. Keep shell; JS peek shows splat.
			print("[MW] chessroom splat active=", active, " — keep shell (no canvas alpha); peek overlay")
			JavaScriptBridge.eval(
				"if(typeof window.MW_SPLAT_PEEK==='function'){window.MW_SPLAT_PEEK();}",
				true
			)
			_splat_shell_hidden = true  # stop re-entering; shell stays visible
			return
		MWSplatBridge.hide_chessroom_shell(self)
		_splat_shell_hidden = true
		print("[MW] chessroom splat active=", active, " — shell hidden (composite OK)")
	_splat_poll_n += 1
	if _splat_poll_n > 40:
		if not _splat_shell_hidden:
			print("[MW] chessroom splat still inactive — keeping procedural shell")
		return
	get_tree().create_timer(0.4).timeout.connect(_splat_wait_active)


func _process(delta: float) -> void:
	_poll_web_chat()
	_tick_piece_anims(delta)
	_tick_bj_anims(delta)
	_tick_wudui_anims(delta)
	if _splat_on:
		_splat_pose_timer += delta
		if _splat_pose_timer >= MWSplatBridge.pose_interval(get_viewport().get_camera_3d(), delta):
			_splat_pose_timer = 0.0
			MWSplatBridge.push_pose(get_viewport().get_camera_3d())
	_cmd_timer += delta
	var cmd_hz := CMD_HZ_SPLAT if _splat_on else CMD_HZ
	if _cmd_timer >= 1.0 / cmd_hz:
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
	var idle := vx == 0.0 and vy == 0.0 and yaw_rate == 0.0
	if idle and _last_idle_cmd:
		return
	if ws.outbound_full(0.35):
		return
	_last_idle_cmd = idle
	# Moving: 20→10 Hz (or 10→5 with splat) — same alternating ctr as hub/main.
	if idle:
		_move_send_ctr = 0
	elif _move_send_ctr == 0:
		_move_send_ctr = 1
	else:
		_move_send_ctr = 0
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
			"KeyH":
				if _view_game() == "blackjack":
					_on_bj_hit()
			"KeyS":
				if _view_game() == "blackjack":
					_on_bj_stand()
			"ArrowLeft":
				_wudui_cycle_sel(-1)
			"ArrowRight":
				_wudui_cycle_sel(1)
			"ArrowUp":
				_on_wudui_primary()
			"KeyJ":
				_on_quick_sit()
			"Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6":
				if _board_open():
					_on_emote_pick(MWEmotes.text_at(int(code.substr(5)) - 1))


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
		elif ek.keycode == KEY_H and _view_game() == "blackjack":
			_on_bj_hit()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_S and _view_game() == "blackjack":
			_on_bj_stand()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_LEFT or ek.physical_keycode == KEY_LEFT:
			_wudui_cycle_sel(-1)
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_RIGHT or ek.physical_keycode == KEY_RIGHT:
			_wudui_cycle_sel(1)
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_UP or ek.physical_keycode == KEY_UP:
			_on_wudui_primary()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_J or ek.physical_keycode == KEY_J:
			_on_quick_sit()
			get_viewport().set_input_as_handled()
		elif _board_open() and ek.keycode >= KEY_1 and ek.keycode <= KEY_6:
			_on_emote_pick(MWEmotes.text_at(ek.keycode - KEY_1))
			get_viewport().set_input_as_handled()


func _on_escape() -> void:
	if _board_open():
		_close_board()
		return
	_leave_to_hub()


func _leave_to_hub() -> void:
	_piece_anims.clear()
	if _seated_table_id != "":
		ws.send_cmd({"action": "chess_leave", "table_id": _seated_table_id})
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
	_ai_fill_at = float(_view_detail().get("ai_fill_at", 0.0))
	_sync_ai_countdown()
	_sync_quick_sit_button()


func _close_board() -> void:
	_auto_exit_gen += 1
	_board_layer.visible = false
	_ai_fill_at = 0.0
	_sync_ai_countdown()
	_wudui_anims.clear()
	_wudui_prev = {}
	_wudui_celebrated = false
	_sel = Vector2i(-1, -1)
	_pending_junqi_move = {}
	_rules_visible = false
	_piece_anims.clear()
	if _result_label != null:
		_result_label.visible = false
	if _seated_table_id != "":
		ws.send_cmd({"action": "chess_leave", "table_id": _seated_table_id})
	_view_table_id = ""
	_sync_quick_sit_button()


func _build_quick_sit_button() -> void:
	"""Fun-Q: one-click seat at the best table with a free seat."""
	_quick_sit_btn = MWQuickSit.build_button(self, _on_quick_sit)


func _build_invite_button() -> void:
	"""Fun-R: copy a private-room invite link (web only)."""
	if _is_web:
		MWInviteLink.build_button(self, _on_invite)


func _on_invite() -> void:
	"""Already in a private room → copy as-is; public room → new code + reload."""
	var code := MWInviteLink.current_room_code()
	if code != "":
		MWInviteLink.copy_url(code, false)
		_append_chat_log(
			"MW",
			MWi18n.t("已复制邀请链接，发给朋友即可同桌开黑", "Invite link copied — share it to play together")
		)
		return
	# Public room: mint a code, copy, then jump into the private room so
	# inviter + invitee actually meet.
	var new_code := MWInviteLink.gen_code()
	MWInviteLink.copy_url(new_code, true)


func _sync_quick_sit_button() -> void:
	if _quick_sit_btn != null:
		_quick_sit_btn.visible = not _board_open()


func _on_quick_sit() -> void:
	"""Pick the best free-seat table and sit without walking over."""
	if _board_open():
		return
	var tid := MWQuickSit.pick_table(_tables, _seated_table_id)
	if tid == "":
		_append_chat_log(
			"MW",
			MWi18n.t("所有牌桌已满，先逛逛或稍后再来", "All tables full — come back later")
		)
		return
	_view_table_id = tid
	_sel = Vector2i(-1, -1)
	_rules_visible = false
	ws.send_cmd({"action": "chess_sit", "table_id": tid})
	_board_layer.visible = true
	_fit_board_panel()
	_refresh_board_from_authority()
	_ai_fill_at = float(_view_detail().get("ai_fill_at", 0.0))
	_sync_ai_countdown()
	_sync_quick_sit_button()
	var meta: Dictionary = TABLE_META.get(tid, {})
	var title := MWi18n.t(
		str(meta.get("title_zh", tid)),
		str(meta.get("title_en", tid))
	)
	_append_chat_log("MW", MWi18n.t("已入座 %s", "Seated at %s") % title)


func _build_board_ui() -> void:
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 20
	_board_layer.visible = false
	add_child(_board_layer)
	# CanvasLayer children need a full-rect Control root or center anchors break.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var panel := PanelContainer.new()
	_board_panel = panel
	# Absolute position via _fit_board_panel (viewport-centered).
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 700)
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 6)
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
	_hit_btn = Button.new()
	_hit_btn.text = MWi18n.t("要牌 (H)", "Hit (H)")
	_hit_btn.visible = false
	_hit_btn.pressed.connect(_on_bj_hit)
	btn_row.add_child(_hit_btn)
	_stand_btn = Button.new()
	_stand_btn.text = MWi18n.t("停牌 (S)", "Stand (S)")
	_stand_btn.visible = false
	_stand_btn.pressed.connect(_on_bj_stand)
	btn_row.add_child(_stand_btn)
	_deal_btn = Button.new()
	_deal_btn.text = MWi18n.t("再来一局", "Deal again")
	_deal_btn.visible = false
	_deal_btn.pressed.connect(_on_bj_redeal)
	btn_row.add_child(_deal_btn)
	_wudui_discard_btn = Button.new()
	_wudui_discard_btn.text = MWi18n.t("出牌", "Discard")
	_wudui_discard_btn.visible = false
	_wudui_discard_btn.pressed.connect(_on_wudui_discard)
	btn_row.add_child(_wudui_discard_btn)
	_wudui_eat_btn = Button.new()
	_wudui_eat_btn.text = MWi18n.t("吃牌", "Eat")
	_wudui_eat_btn.visible = false
	_wudui_eat_btn.pressed.connect(_on_wudui_eat)
	btn_row.add_child(_wudui_eat_btn)
	_wudui_pass_btn = Button.new()
	_wudui_pass_btn.text = MWi18n.t("过牌", "Pass")
	_wudui_pass_btn.visible = false
	_wudui_pass_btn.pressed.connect(_on_wudui_pass)
	btn_row.add_child(_wudui_pass_btn)
	_rules_label = Label.new()
	_rules_label.visible = false
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_label.custom_minimum_size = Vector2(0, 0)
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
	# Fun-E: quick emotes/cheers through the room chat channel (spectators too).
	MWEmotes.build_row(vbox, _on_emote_pick)
	_ai_countdown_label = Label.new()
	_ai_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ai_countdown_label.visible = false
	_ai_countdown_label.add_theme_font_size_override("font_size", 22)
	_ai_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	vbox.add_child(_ai_countdown_label)
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.visible = false
	_result_label.add_theme_font_size_override("font_size", 28)
	_result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(_result_label)
	_apply_board_fonts()
	_ai_countdown_timer = Timer.new()
	_ai_countdown_timer.wait_time = 0.25
	_ai_countdown_timer.one_shot = false
	_ai_countdown_timer.timeout.connect(_tick_ai_countdown)
	add_child(_ai_countdown_timer)
	_fit_board_panel()
	if not get_viewport().size_changed.is_connected(_fit_board_panel):
		get_viewport().size_changed.connect(_fit_board_panel)


func _apply_board_fonts() -> void:
	var f: Font = MWFonts.font() if MWFonts != null else null
	if f == null:
		return
	for lab in [_title_label, _status_label, _ai_countdown_label, _result_label, _rules_label]:
		if lab != null:
			lab.add_theme_font_override("font", f)
	for btn in [_layout_btn, _confirm_btn, _resign_btn, _hand_btn, _rules_btn, _hit_btn, _stand_btn, _deal_btn]:
		if btn != null:
			btn.add_theme_font_override("font", f)
	# Compact the chrome row so 4+ buttons fit a 560px panel (wudui adds 3).
	for btn in [_layout_btn, _confirm_btn, _resign_btn, _hand_btn, _rules_btn, _hit_btn, _stand_btn, _deal_btn, _wudui_discard_btn, _wudui_eat_btn, _wudui_pass_btn]:
		if btn != null:
			btn.add_theme_font_size_override("font_size", 14)


func _rules_text_for(game: String) -> Dictionary:
	"""ADR-010: moved to MWRulesText (SSOT summaries)."""
	return MWRulesText.for_game(game)


func _apply_rules_text() -> void:
	"""Refresh label text for the currently-viewed game."""
	var pair := _rules_text_for(_view_game())
	if _rules_label != null and pair["zh"] != "":
		_rules_label.text = MWi18n.t(pair["zh"], pair["en"])


func _toggle_junqi_rules() -> void:
	"""Show / hide concise rules for the current game (SSOT summary)."""
	_rules_visible = not _rules_visible
	_apply_rules_text()
	if _rules_label != null:
		_rules_label.visible = _rules_visible
	if _rules_btn != null:
		_rules_btn.text = (
			MWi18n.t("隐藏规则", "Hide rules")
			if _rules_visible
			else MWi18n.t("规则说明", "Rules")
		)
	_fit_board_panel()


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
	"""Lock draft (auto-fill first if empty) and mark ready."""
	if _view_table_id == "" or _view_game() != "junqi":
		return
	_sel = Vector2i(-1, -1)
	var payload := {
		"action": "junqi_layout",
		"table_id": _view_table_id,
		"ready": true,
	}
	# One-click start: no draft yet → server auto_layout then ready.
	if _junqi_own_piece_count() < 25:
		payload["auto"] = true
	ws.send_cmd(payload)


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


func _on_bj_hit() -> void:
	if _view_table_id == "" or _view_game() != "blackjack":
		return
	ws.send_cmd({"action": "card_hit", "table_id": _view_table_id})


func _on_bj_stand() -> void:
	if _view_table_id == "" or _view_game() != "blackjack":
		return
	ws.send_cmd({"action": "card_stand", "table_id": _view_table_id})


func _on_bj_redeal() -> void:
	if _view_table_id == "" or _view_game() != "blackjack":
		return
	ws.send_cmd({"action": "chess_reset", "table_id": _view_table_id})

## --- WuDui (五对) board ---

func _wudui_my_side() -> String:
	"""black = first player seat, red = second."""
	var d := _view_detail()
	var my_sid := _effective_sid()
	if str(d.get("black_sid", "")).strip_edges() == my_sid:
		return "black"
	if str(d.get("white_sid", "")).strip_edges() == my_sid:
		return "red"
	return ""


func _wudui_rank(card: String) -> String:
	return MWWuduiUtil.rank(card)


func _wudui_can_eat(d: Dictionary) -> bool:
	return MWWuduiUtil.can_eat(d)


func _wudui_hand_origin(count: int, y: float, area: Vector2) -> Vector2:
	return MWWuduiUtil.hand_origin(count, y, area)


func _wudui_card_pos(index: int, count: int, y: float, area: Vector2) -> Vector2:
	return MWWuduiUtil.card_pos(index, count, y, area)


func _wudui_card_w(count: int, area: Vector2) -> float:
	return MWWuduiUtil.card_w(count, area)


func _wudui_gap(count: int, area: Vector2) -> float:
	return MWWuduiUtil.gap(count, area)


func _wudui_row_h(hand: Array, area: Vector2) -> float:
	return MWWuduiUtil.row_h(hand, area)


func _wudui_grouped_hand(hand: Array) -> Dictionary:
	return MWWuduiUtil.grouped_hand(hand)


func _wudui_hand_rects(hand: Array, area: Vector2, y: float) -> Array:
	return MWWuduiUtil.hand_rects(hand, area, y)


func _wudui_default_discard(d: Dictionary, hand: Array, opponent: Array) -> String:
	return MWWuduiUtil.default_discard(d, hand, opponent)


func _wudui_cycle_sel(dir: int) -> void:
	"""←/→ cycle the selected scattered card on my turn."""
	var d := _view_detail()
	if not _board_open() or str(d.get("game", "")) != "wudui":
		return
	if str(d.get("phase", "idle")) != "playing":
		return
	var my_side := _wudui_my_side()
	var turn := str(d.get("turn", "black"))
	if my_side == "" or not (
		(my_side == "black" and turn == "black")
		or (my_side == "red" and turn == "red")
	):
		return
	var hand: Array = d.get("black_cards", []) if my_side == "black" else d.get("red_cards", [])
	var scattered: Array = _wudui_grouped_hand(hand)["scattered"]
	if scattered.is_empty():
		return
	var opponent: Array = d.get("red_cards", []) if my_side == "black" else d.get("black_cards", [])
	if _wudui_sel == "" or not scattered.has(_wudui_sel):
		_wudui_sel = _wudui_default_discard(d, hand, opponent)
	else:
		var idx := scattered.find(_wudui_sel)
		idx = posmod(idx + dir, scattered.size())
		_wudui_sel = str(scattered[idx])
	_board_ctrl.queue_redraw()


func _on_wudui_primary() -> void:
	"""↑ / on-card button: play the selected scattered card (black discards;
	red eats when the pile pairs, else passes)."""
	if _wudui_sel == "" or _view_table_id == "":
		return
	var d := _view_detail()
	var my_side := _wudui_my_side()
	var turn := str(d.get("turn", "black"))
	if my_side == "black" and turn == "black":
		_on_wudui_discard()
	elif my_side == "red" and turn == "red":
		if _wudui_can_eat(d):
			_on_wudui_eat()
		else:
			_on_wudui_pass()


# ── 五对动画（diff → tick → draw 插值，与棋类/21 点同模式）────────────

func _wudui_rank_counts(hand: Array) -> Dictionary:
	return MWWuduiUtil.rank_counts(hand)


func _wudui_anim_for(card: String, side: String) -> Dictionary:
	"""Active wudui anim covering `card` on `side` ({} when none)."""
	for key in _wudui_anims:
		var a: Dictionary = _wudui_anims[key]
		if str(a.get("side", "")) == side and str(a.get("card", "")) == card:
			return a
	return {}


func _wudui_flying_out(card: String) -> bool:
	"""True while `card` is animating out of a hand toward the discard pile."""
	for key in _wudui_anims:
		var a: Dictionary = _wudui_anims[key]
		if str(a.get("kind", "")) == "fly_out" and str(a.get("card", "")) == card:
			return true
	return false


func _wudui_side_rects(hand: Array, area: Vector2, side: String) -> Array:
	return MWWuduiUtil.side_rects(hand, area, side)


func _wudui_slot_of(hand: Array, area: Vector2, side: String, card: String) -> Rect2:
	for e in _wudui_side_rects(hand, area, side):
		if str(e["card"]) == card:
			return e["rect"]
	return Rect2()


func _wudui_completed_pair_cards(prev_hand: Array, hand: Array) -> Array:
	return MWWuduiUtil.completed_pair_cards(prev_hand, hand)


func _detect_wudui_changes(d: Dictionary) -> void:
	"""Diff prev/new wudui state → _wudui_anims（发牌/摸牌/出牌/吃牌/配对闪光/五对达成）。"""
	var black: Array = d.get("black_cards", [])
	var red: Array = d.get("red_cards", [])
	var pile: Array = d.get("discard_pile", [])
	if _wudui_prev.is_empty():
		_wudui_prev = {"black": black.duplicate(), "red": red.duplicate(), "pile": pile.duplicate()}
		return
	var prev_black: Array = _wudui_prev.get("black", [])
	var prev_red: Array = _wudui_prev.get("red", [])
	var area: Vector2 = _board_ctrl.custom_minimum_size if _board_ctrl != null else Vector2(920.0, 520.0)
	var pile_pos := Vector2((area.x - _BJ_CARD_W) * 0.5, (area.y - _BJ_CARD_H) * 0.5)
	var last_action := str(d.get("last_action", ""))
	var is_deal := last_action == "deal" and (black.size() + red.size()) > 0
	if is_deal:
		_wudui_celebrated = false
	var played_deal := false
	var played_swoosh := false
	for side in ["black", "red"]:
		var hand: Array = black if side == "black" else red
		var prev_hand: Array = prev_black if side == "black" else prev_red
		var entered: Array = []
		for c in hand:
			if not prev_hand.has(c):
				entered.append(c)
		var left: Array = []
		for c in prev_hand:
			if not hand.has(c):
				left.append(c)
		var stagger := 0.0
		if is_deal:
			stagger = 0.06  # 发牌：整手牌从牌堆依次飞出（60ms 错峰）
		var entered_ranks := {}
		for c in entered:
			entered_ranks[_wudui_rank(str(c))] = true
		for i in entered.size():
			var card := str(entered[i])
			var idx := hand.find(card)
			var slot := _wudui_slot_of(hand, area, side, card)
			_wudui_anims["%s_in_%s" % [card, side]] = {
				"kind": "fly_in", "card": card, "side": side,
				"from": pile_pos, "to": slot.position, "size": slot.size,
				"t": -float(idx) * stagger, "dur": 0.32,
			}
			if not played_deal:
				_play_sfx("deal")
				played_deal = true
		for i in left.size():
			var card := str(left[i])
			var slot := _wudui_slot_of(prev_hand, area, side, card)
			_wudui_anims["%s_out_%s" % [card, side]] = {
				"kind": "fly_out", "card": card, "side": side,
				"from": slot.position, "to": pile_pos, "size": slot.size,
				"t": 0.0, "dur": 0.28,
			}
			if not played_swoosh:
				_play_sfx("swoosh")
				played_swoosh = true
		for card in _wudui_completed_pair_cards(prev_hand, hand):
			var delay := -0.28 if entered_ranks.has(_wudui_rank(str(card))) else 0.0
			_wudui_anims["%s_flash_%s" % [card, side]] = {
				"kind": "flash", "card": str(card), "side": side,
				"t": delay, "dur": 0.6,
			}
	if str(d.get("phase", "")) == "finished" and not _wudui_celebrated:
		_wudui_celebrated = true
		var winner := str(d.get("winner", ""))
		if winner == "black" or winner == "red":
			var win_hand: Array = black if winner == "black" else red
			for i in win_hand.size():
				_wudui_anims["win_%s_%d" % [winner, i]] = {
					"kind": "win", "card": str(win_hand[i]), "side": winner,
					"t": -float(i) * 0.08, "dur": 0.9,
				}
			_play_sfx("win")
	_wudui_prev = {"black": black.duplicate(), "red": red.duplicate(), "pile": pile.duplicate()}


func _tick_wudui_anims(delta: float) -> void:
	if _wudui_anims.is_empty():
		return
	var done: Array = []
	var dirty := false
	for key in _wudui_anims:
		var a: Dictionary = _wudui_anims[key]
		a["t"] = float(a.get("t", 0.0)) + delta
		if float(a["t"]) >= float(a.get("dur", 1.0)):
			done.append(key)
		else:
			dirty = true
	for key in done:
		_wudui_anims.erase(key)
	if dirty and _board_ctrl != null:
		_board_ctrl.queue_redraw()


func _draw_wudui_card_at(pos: Vector2, size: Vector2, card: String, rot_deg: float, alpha: float) -> void:
	"""Draw a card with rotation (flying overlay)."""
	if absf(rot_deg) < 0.5:
		_draw_card_sized(pos, size, card, 1.0, alpha)
		return
	var center := pos + size * 0.5
	_board_ctrl.draw_set_transform(center, deg_to_rad(rot_deg), Vector2.ONE)
	_draw_card_sized(-size * 0.5, size, card, 1.0, alpha)
	_board_ctrl.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wudui_anim_overlay(d: Dictionary, area: Vector2, pile_pos: Vector2) -> void:
	"""Flying cards + pair-flash / win pulse drawn on top of the static board."""
	for key in _wudui_anims:
		var a: Dictionary = _wudui_anims[key]
		var kind := str(a.get("kind", ""))
		var card := str(a.get("card", ""))
		if kind == "fly_in" or kind == "fly_out":
			var t := float(a.get("t", 0.0))
			if t < 0.0:
				continue
			var dur := float(a.get("dur", 1.0))
			var e := clampf(t / dur, 0.0, 1.0)
			var from: Vector2 = a.get("from", pile_pos)
			var to: Vector2 = a.get("to", pile_pos)
			var k := e * e if kind == "fly_out" else 1.0 - pow(1.0 - e, 3.0)
			var pos := from.lerp(to, k) + Vector2(0.0, -sin(e * PI) * 44.0)
			var rot := lerpf(-10.0, 0.0, k) if kind == "fly_out" else lerpf(8.0, 0.0, k)
			var size: Vector2 = a.get("size", Vector2(_BJ_CARD_W, _BJ_CARD_H))
			if kind == "fly_in":
				size *= lerpf(0.65, 1.0, k)
			_draw_wudui_card_at(pos, size, card, rot, 1.0)
		elif kind == "flash" or kind == "win":
			var side := str(a.get("side", ""))
			var hand: Array = d.get("black_cards", []) if side == "black" else d.get("red_cards", [])
			var slot := _wudui_slot_of(hand, area, side, card)
			if slot.size.x <= 0.0:
				continue
			var t := float(a.get("t", 0.0))
			if t < 0.0:
				continue
			var dur := float(a.get("dur", 1.0))
			var e := clampf(t / dur, 0.0, 1.0)
			var alpha := sin(e * PI)
			var grow := 5.0 + 12.0 * alpha
			var col := Color(1.0, 0.85, 0.2, 0.55 * alpha)
			if kind == "win":
				col = Color(1.0, 0.9, 0.35, 0.7 * alpha)
			_board_ctrl.draw_rect(slot.grow(grow), col, false, 3.0)


func _draw_wudui_board() -> void:
	_wudui_btn_rect = Rect2()
	var d := _view_detail()
	var sz: Vector2 = _board_ctrl.custom_minimum_size
	_board_ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.38, 0.22, 0.1))
	var pad := 8.0
	var felt := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
	_board_ctrl.draw_rect(felt, Color(0.12, 0.22, 0.42))
	_board_ctrl.draw_rect(felt, Color(0.07, 0.12, 0.26, 0.8), false, 2.0)
	var area := felt.size
	var black: Array = d.get("black_cards", [])
	var red: Array = d.get("red_cards", [])
	var pile: Array = d.get("discard_pile", [])
	var my_side := _wudui_my_side()
	# Rows are face up (pair race, both see all): pairs left, scattered right.
	var red_rects := _wudui_hand_rects(red, area, 14.0)
	_draw_wudui_hand_row(red_rects, "red", my_side == "red", d, area)
	var black_y := area.y - _wudui_row_h(black, area) - 14.0
	var black_rects := _wudui_hand_rects(black, area, black_y)
	_draw_wudui_hand_row(black_rects, "black", my_side == "black", d, area)
	# Discard pile (center) + turn marker.
	var pile_pos := Vector2((area.x - _BJ_CARD_W) * 0.5, (area.y - _BJ_CARD_H) * 0.5)
	if not pile.is_empty():
		var top := str(pile[-1])
		_draw_bj_card(pile_pos, top, 1.0, 0.25 if _wudui_flying_out(top) else 1.0)
	else:
		_draw_bj_card(pile_pos, "??", 1.0, 0.35)
	var turn := str(d.get("turn", "black"))
	var turn_txt := MWi18n.t("黑方行 · 弃散牌", "Black turn · discard") if turn == "black" else MWi18n.t("红方行 · 吃或过", "Red turn · eat or pass")
	var f: Font = MWFonts.font() if MWFonts != null else null
	_board_ctrl.draw_string(
		f if f != null else ThemeDB.fallback_font,
		Vector2(pile_pos.x + _BJ_CARD_W + 14.0, pile_pos.y + 30.0),
		turn_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.92, 0.85)
	)
	_board_ctrl.draw_string(
		f if f != null else ThemeDB.fallback_font,
		Vector2(pile_pos.x + _BJ_CARD_W + 14.0, pile_pos.y + 54.0),
		"黑 %d 对 · 红 %d 对" % [int(d.get("black_pairs", 0)), int(d.get("red_pairs", 0))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.85)
	)
	_draw_wudui_anim_overlay(d, area, pile_pos)


func _draw_wudui_hand_row(rects: Array, side: String, interactive: bool, d: Dictionary, area: Vector2) -> void:
	var sel_idx := -1
	for i in rects.size():
		var e: Dictionary = rects[i]
		var card := str(e["card"])
		var anim := _wudui_anim_for(card, side)
		var flying := not anim.is_empty() and str(anim.get("kind", "")) == "fly_in"
		_draw_card_sized(
			e["rect"].position, e["rect"].size, card,
			1.0, 0.0 if flying else (0.92 if interactive else 0.85)
		)
		if interactive and not flying and bool(e["scattered"]) and card == _wudui_sel:
			sel_idx = i
	# Divider between the pair block and the scattered block.
	var sep := 0
	for e in rects:
		if bool(e["scattered"]):
			break
		sep += 1
	if sep > 0 and sep < rects.size():
		var a: Dictionary = rects[sep - 1]
		var b: Dictionary = rects[sep]
		var mid_x: float = (a["rect"].end.x + b["rect"].position.x) * 0.5
		_board_ctrl.draw_line(
			Vector2(mid_x, a["rect"].position.y + 4.0),
			Vector2(mid_x, a["rect"].end.y - 4.0),
			Color(1, 1, 1, 0.28), 2.0
		)
	if sel_idx < 0:
		return
	var my_side := _wudui_my_side()
	var slot: Rect2 = rects[sel_idx]["rect"]
	var big := slot.size * 1.25
	var big_pos := Vector2(
		slot.position.x + (slot.size.x - big.x) * 0.5,
		slot.position.y - (16.0 if my_side == "black" else -16.0)
	)
	_draw_card_sized(big_pos, big, str(rects[sel_idx]["card"]), 1.0, 1.0)
	_board_ctrl.draw_rect(Rect2(big_pos, big).grow(3.0), Color(1, 0.85, 0.2), false, 3.0)
	# On-card action button: above the slot for black, below for red.
	var btn_h := 28.0
	var btn := Rect2(
		Vector2(
			slot.position.x,
			slot.position.y - btn_h - 6.0 if my_side == "black" else slot.position.y + slot.size.y + 6.0
		),
		Vector2(slot.size.x, btn_h)
	)
	_wudui_btn_rect = btn
	var txt := MWi18n.t("出牌", "Discard")
	if my_side == "red":
		txt = MWi18n.t("吃牌", "Eat") if _wudui_can_eat(d) else MWi18n.t("过牌", "Pass")
	var f: Font = MWFonts.font() if MWFonts != null else null
	_board_ctrl.draw_rect(btn, Color(0.16, 0.55, 0.28, 0.95))
	_board_ctrl.draw_rect(btn, Color(0.85, 1.0, 0.8, 1.0), false, 2.0)
	_board_ctrl.draw_string(
		f if f != null else ThemeDB.fallback_font,
		btn.position + Vector2(0.0, (btn_h + 18.0) * 0.5),
		txt, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, 18, Color(1, 1, 1)
	)


func _on_wudui_click(pos: Vector2, d: Dictionary) -> void:
	var my_side := _wudui_my_side()
	if my_side == "":
		return
	if str(d.get("phase", "idle")) != "playing":
		return
	if _wudui_btn_rect.size.x > 0.0 and _wudui_btn_rect.has_point(pos):
		_on_wudui_primary()
		return
	var area: Vector2 = _board_ctrl.custom_minimum_size
	var hand: Array = d.get("black_cards", []) if my_side == "black" else d.get("red_cards", [])
	var y := area.y - _wudui_row_h(hand, area) - 14.0 if my_side == "black" else 14.0
	for e in _wudui_hand_rects(hand, area, y):
		if not bool(e["scattered"]):
			continue
		if e["rect"].has_point(pos):
			_wudui_sel = str(e["card"])
			_board_ctrl.queue_redraw()
			return


func _refresh_wudui_status(d: Dictionary, status: String) -> void:
	var my_side := _wudui_my_side()
	var turn := str(d.get("turn", "black"))
	var phase := str(d.get("phase", "idle"))
	if phase != "playing":
		_wudui_sel = ""
	else:
		var hand: Array = d.get("black_cards", []) if my_side == "black" else d.get("red_cards", [])
		if _wudui_sel != "" and not hand.has(_wudui_sel):
			_wudui_sel = ""
		var my_turn := (my_side == "black" and turn == "black") or (my_side == "red" and turn == "red")
		if my_turn and _wudui_sel == "":
			var opponent: Array = d.get("red_cards", []) if my_side == "black" else d.get("black_cards", [])
			_wudui_sel = _wudui_default_discard(d, hand, opponent)
	_wudui_discard_btn.visible = phase == "playing" and my_side == "black" and turn == "black" and status == "playing"
	_wudui_eat_btn.visible = phase == "playing" and my_side == "red" and turn == "red" and status == "playing" and _wudui_can_eat(d)
	_wudui_pass_btn.visible = phase == "playing" and my_side == "red" and turn == "red" and status == "playing"
	_wudui_discard_btn.disabled = _wudui_sel == ""
	_wudui_eat_btn.disabled = _wudui_sel == ""
	_wudui_pass_btn.disabled = _wudui_sel == ""
	if phase != "playing" or status == "finished":
		var winner := str(d.get("winner", ""))
		var reason := str(d.get("reason", ""))
		var label := ""
		if winner == "black":
			label = MWi18n.t("黑方五对胜", "Black wins") + (" · 天和!" if reason == "tianhe" else "")
		elif winner == "red":
			label = MWi18n.t("红方五对胜", "Red wins")
		elif reason == "resign":
			label = MWi18n.t("认输终局", "Resign")
		if label != "":
			_set_status(MWi18n.t("再来一局？", "Deal again?"))
			if _result_label != null:
				_result_label.text = label
				_result_label.visible = true
		return
	if my_side == "":
		_set_status(MWi18n.t("旁观 · 坐下开局", "Spectating · sit to start"))
	elif my_side == "black" and turn == "black":
		if status != "playing":
			_set_status(MWi18n.t("等待对手加入… 5 秒后无人将匹配 AI", "Waiting… AI fills in after 5s"))
		else:
			_set_status(MWi18n.t("轮到你 · ←/→ 选散牌 · ↑ 出牌", "Your turn — ←/→ pick · ↑ discard"))
	elif my_side == "red" and turn == "red":
		_set_status(MWi18n.t("轮到你 · ←/→ 选散牌 · ↑ 吃/过牌", "Your turn — ←/→ pick · ↑ eat/pass"))
	else:
		_set_status(MWi18n.t("等待对手…", "Waiting for opponent…"))


func _on_wudui_discard() -> void:
	if _wudui_sel == "" or _view_table_id == "":
		return
	ws.send_cmd({"action": "card_discard", "table_id": _view_table_id, "card": _wudui_sel})


func _on_wudui_eat() -> void:
	if _wudui_sel == "" or _view_table_id == "":
		return
	var d := _view_detail()
	var pile: Array = d.get("discard_pile", [])
	if pile.is_empty():
		return
	ws.send_cmd({"action": "card_eat", "table_id": _view_table_id,
		"card": str(pile[-1]), "discard": _wudui_sel})


func _on_wudui_pass() -> void:
	if _wudui_sel == "" or _view_table_id == "":
		return
	ws.send_cmd({"action": "card_pass", "table_id": _view_table_id, "discard": _wudui_sel})


func _board_px() -> float:
	if _board_ctrl != null and _board_ctrl.custom_minimum_size.x > 10.0:
		return _board_ctrl.custom_minimum_size.x
	return 540.0


func _junqi_board_size() -> Vector2:
	return MWJunqiGeom.board_size(get_viewport().get_visible_rect().size)


func _junqi_flip() -> bool:
	"""Landscape: keep local player's half on the LEFT."""
	return _my_junqi_side() == "red"


func _junqi_view_r(model_r: int) -> int:
	return MWJunqiGeom.view_r(model_r, _junqi_flip())


func _junqi_model_r(view_r: int) -> int:
	return MWJunqiGeom.model_r(view_r, _junqi_flip())


func _fit_board_panel() -> void:
	"""Resize panel and center it in the viewport (top-left anchors)."""
	if _board_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 32.0 or vp.y < 32.0:
		return
	var pw := 560.0
	var ph := 700.0
	if _view_game() in ["blackjack", "wudui"]:
		var felt := Vector2(clampf(vp.x - 48.0, 420.0, 920.0), clampf(vp.y - 190.0, 260.0, 520.0))
		if _board_ctrl != null:
			_board_ctrl.custom_minimum_size = felt
		pw = clampf(felt.x + 48.0, 400.0, vp.x - 24.0)
		ph = clampf(felt.y + 170.0, 380.0, vp.y - 24.0)
	elif _view_game() == "junqi":
		var bs := _junqi_board_size()
		if _board_ctrl != null:
			_board_ctrl.custom_minimum_size = bs
		pw = clampf(bs.x + 48.0, 400.0, vp.x - 24.0)
		ph = clampf(bs.y + 140.0, 280.0, vp.y - 24.0)
	else:
		var side := clampf(minf(vp.x - 64.0, vp.y - 168.0), 300.0, 520.0)
		if _board_ctrl != null:
			_board_ctrl.custom_minimum_size = Vector2(side, side)
		pw = clampf(side + 40.0, 320.0, vp.x - 24.0)
		ph = clampf(side + 140.0, 360.0, vp.y - 24.0)
	if _rules_label != null:
		_rules_label.custom_minimum_size = Vector2(maxf(pw - 36.0, 120.0), 0.0)
	_board_panel.custom_minimum_size = Vector2(pw, ph)
	_board_panel.size = Vector2(pw, ph)
	_board_panel.position = Vector2(
		(vp.x - pw) * 0.5,
		(vp.y - ph) * 0.5
	)


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


func _draw_stone(center: Vector2, radius: float, black: bool, alpha: float = 1.0) -> void:
	"""Glossy go/gomoku stone with rim highlight."""
	_board_ctrl.draw_circle(center + Vector2(1.2, 1.8), radius, Color(0, 0, 0, 0.28 * alpha))
	if black:
		_board_ctrl.draw_circle(center, radius, Color(0.08, 0.07, 0.07, alpha))
		_board_ctrl.draw_circle(center - Vector2(radius * 0.28, radius * 0.32), radius * 0.28, Color(0.45, 0.45, 0.48, 0.55 * alpha))
		_board_ctrl.draw_arc(center, radius, 0, TAU, 28, Color(0.02, 0.02, 0.02, alpha), 1.2)
	else:
		_board_ctrl.draw_circle(center, radius, Color(0.94, 0.93, 0.9, alpha))
		_board_ctrl.draw_circle(center - Vector2(radius * 0.25, radius * 0.3), radius * 0.22, Color(1, 1, 1, 0.7 * alpha))
		_board_ctrl.draw_arc(center, radius, 0, TAU, 28, Color(0.45, 0.42, 0.38, alpha), 1.3)


func _draw_halma_pawn(center: Vector2, radius: float, red: bool, alpha: float = 1.0) -> void:
	"""Plastic Halma pawn: cylinder-ish disc with bevel."""
	_board_ctrl.draw_circle(center + Vector2(1.4, 2.0), radius, Color(0, 0, 0, 0.3 * alpha))
	var body := Color(0.82, 0.22, 0.16, alpha) if red else Color(0.22, 0.42, 0.88, alpha)
	var rim := Color(0.95, 0.5, 0.4, alpha) if red else Color(0.55, 0.7, 0.98, alpha)
	_board_ctrl.draw_circle(center, radius, body)
	_board_ctrl.draw_arc(center, radius, 0, TAU, 28, rim, 2.0)
	_board_ctrl.draw_circle(center - Vector2(radius * 0.2, radius * 0.25), radius * 0.35, Color(1, 1, 1, 0.28 * alpha))
	_board_ctrl.draw_circle(center, radius * 0.38, Color(body.r * 1.15, body.g * 1.15, body.b * 1.1, alpha))


func _draw_board() -> void:
	var game := _view_game()
	if game == "junqi":
		_draw_junqi_board()
		return
	if game == "blackjack":
		_draw_blackjack_board()
		return
	if game == "wudui":
		_draw_wudui_board()
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
				_draw_stone(center + Vector2(0, _anim_y_offset(x, y)), c * 0.38 * _anim_scale(x, y), true, _anim_alpha(x, y))
			elif v == GomokuScript.WHITE:
				_draw_stone(center + Vector2(0, _anim_y_offset(x, y)), c * 0.38 * _anim_scale(x, y), false, _anim_alpha(x, y))


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
				_draw_halma_pawn(center + Vector2(0, _anim_y_offset(x, y)), c * 0.36 * _anim_scale(x, y), true, _anim_alpha(x, y))
			elif v == GomokuScript.WHITE:
				_draw_halma_pawn(center + Vector2(0, _anim_y_offset(x, y)), c * 0.36 * _anim_scale(x, y), false, _anim_alpha(x, y))


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
	# Prefer server-personalized cells (to_detail(viewer_sid=…)).
	# Legacy fallback: merge junqi_views[sid] cells only — never clobber turn/status.
	var views: Variant = d.get("junqi_views", {})
	if typeof(views) != TYPE_DICTIONARY:
		return d
	var mine: Variant = views.get(_session_id, null)
	if typeof(mine) != TYPE_DICTIONARY:
		for k in views.keys():
			if str(k) == _session_id:
				mine = views[k]
				break
	if typeof(mine) != TYPE_DICTIONARY:
		return d
	var out := d.duplicate(true)
	var md: Dictionary = mine
	if md.has("cells"):
		out["cells"] = md["cells"]
	if md.has("last_battle"):
		out["last_battle"] = md["last_battle"]
	if md.has("flag_revealed"):
		out["flag_revealed"] = md["flag_revealed"]
	return out


func _view_game() -> String:
	return str(_view_detail().get("game", "gomoku"))


func _board_size() -> int:
	if _view_game() == "checkers":
		return 8
	return GomokuScript.SIZE


func _cell_px() -> float:
	return _board_px() / float(_board_size() + 1)


func _effective_sid() -> String:
	"""WS session id is SSOT for cmds; keep chessroom cache in sync."""
	var sid := ""
	if ws != null:
		sid = str(ws.session_id).strip_edges()
	if sid == "":
		sid = _session_id.strip_edges()
	if sid != "" and sid != _session_id:
		_session_id = sid
	return sid


func _my_color() -> int:
	var sid := _effective_sid()
	if sid == "":
		return GomokuScript.EMPTY
	var d := _view_detail()
	var black := str(d.get("black_sid", "")).strip_edges()
	var white := str(d.get("white_sid", "")).strip_edges()
	if black != "" and black == sid:
		return GomokuScript.BLACK
	if white != "" and white == sid and not bool(d.get("vs_ai", false)):
		return GomokuScript.WHITE
	return GomokuScript.EMPTY


func _my_junqi_side() -> String:
	"""Map session → black|red. Never match empty sid (str(null)==\"\")."""
	var sid := _effective_sid()
	if sid == "":
		return ""
	var d := _view_detail()
	var black := str(d.get("black_sid", "")).strip_edges()
	var white := str(d.get("white_sid", "")).strip_edges()
	if black != "" and black == sid:
		return "black"
	if white != "" and white == sid and not bool(d.get("vs_ai", false)):
		return "red"
	return ""


func _junqi_resolved_status(d: Dictionary) -> String:
	"""Align status with phase / both-ready (same rules as refresh)."""
	var status := str(d.get("status", "idle"))
	var phase := str(d.get("phase", ""))
	if phase in ["playing", "finished"]:
		return phase
	var ready: Dictionary = d.get("layout_ready", {}) as Dictionary
	if bool(ready.get("black", false)) and bool(ready.get("red", false)):
		return "playing"
	return status


func _junqi_is_my_turn(d: Dictionary) -> bool:
	"""Prefer turn_sid from server; fall back to turn vs side."""
	var sid := _effective_sid()
	if sid == "":
		return false
	var turn_sid := str(d.get("turn_sid", "")).strip_edges()
	if turn_sid != "" and turn_sid != "<null>":
		return turn_sid == sid
	var my := _my_junqi_side()
	if my == "":
		return false
	return str(d.get("turn", "")).strip_edges().to_lower() == my


func _sync_junqi_chrome(status: String) -> void:
	var is_jq := _view_game() == "junqi"
	var is_bj := _view_game() == "blackjack"
	var is_wd := _view_game() == "wudui"
	if not is_wd:
		if _wudui_discard_btn != null:
			_wudui_discard_btn.visible = false
		if _wudui_eat_btn != null:
			_wudui_eat_btn.visible = false
		if _wudui_pass_btn != null:
			_wudui_pass_btn.visible = false
	var my := _my_junqi_side()
	var seated := my != "" or _my_color() != GomokuScript.EMPTY
	if is_bj:
		var d := _view_detail()
		var my_sid := _effective_sid()
		seated = (
			str(d.get("black_sid", "")).strip_edges() == my_sid
			or str(d.get("white_sid", "")).strip_edges() == my_sid
		)
		var my_turn := str(d.get("active_sid", "")).strip_edges() == my_sid
		var playing := seated and status == "playing" and my_turn
		var finished := seated and status == "finished"
		if _hit_btn != null:
			_hit_btn.visible = playing
		if _stand_btn != null:
			_stand_btn.visible = playing
		if _deal_btn != null:
			_deal_btn.visible = finished
	if _rules_btn != null:
		_rules_btn.visible = true
		_rules_btn.text = (
			MWi18n.t("隐藏规则", "Hide rules")
			if _rules_visible
			else MWi18n.t("规则说明", "Rules")
		)
	if _rules_label != null:
		_apply_rules_text()
		_rules_label.visible = _rules_visible
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
		_resign_btn.visible = (seated and status == "playing") and not is_bj
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
	_detect_piece_changes(d, game)
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
	if game == "blackjack":
		# phase is authoritative for blackjack — status may lag one broadcast.
		var bj_phase := str(d.get("phase", ""))
		if bj_phase in ["playing", "finished"]:
			status = bj_phase
	if game == "junqi":
		status = _junqi_resolved_status(d)
	_sync_junqi_chrome(status)
	if _result_label != null:
		_result_label.visible = false
	if game == "junqi":
		_refresh_junqi_status(d, status, vs_ai)
		if _board_ctrl != null:
			_board_ctrl.queue_redraw()
		return
	if game == "blackjack":
		_detect_bj_changes(d)
		var my_sid := _effective_sid()
		var seated := (
			str(d.get("black_sid", "")).strip_edges() == my_sid
			or str(d.get("white_sid", "")).strip_edges() == my_sid
		)
		var phase := str(d.get("phase", "idle"))
		var results: Dictionary = d.get("results", {}) as Dictionary
		var result := str(results.get(my_sid, d.get("result", "")))
		if status == "finished":
			var label := ""
			if result == "blackjack":
				label = MWi18n.t("21 点！Blackjack！", "Blackjack!")
			elif result == "win":
				label = MWi18n.t("你赢了 🎉", "You win 🎉")
			elif result == "lose":
				label = MWi18n.t("你输了 · 爆牌/庄家更大", "You lose")
			elif result == "push":
				label = MWi18n.t("平局 · 点数相同", "Push")
			else:
				label = MWi18n.t("终局", "Game over")
			if _result_label != null:
				_result_label.text = label
				_result_label.visible = true
			if seated:
				_set_status(MWi18n.t("再来一局？", "Deal again?"))
			else:
				_set_status(MWi18n.t("旁观 · 等待新一局", "Spectating · next round"))
		elif not seated:
			_set_status(MWi18n.t("旁观 · 坐下开牌", "Spectating · sit to play"))
		elif phase == "playing":
			var active := str(d.get("active_sid", "")).strip_edges()
			if active == my_sid:
				_set_status(MWi18n.t("要牌 (H) 或 停牌 (S)", "Hit (H) or stand (S)"))
			else:
				_set_status(MWi18n.t("等待对手行动…", "Waiting for opponent…"))
		else:
			_set_status(MWi18n.t("等待发牌…", "Dealing…"))
		if _board_ctrl != null:
			_board_ctrl.queue_redraw()
		return
	if game == "wudui":
		_detect_wudui_changes(d)
		_refresh_wudui_status(d, status)
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
	var black_ok := bool(ready.get("black", false))
	var red_ok := bool(ready.get("red", false))
	# Both ready but status still layout → treat as playing (desync guard).
	if status in ["layout", "idle"] and black_ok and red_ok:
		status = "playing"
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
		var mine_ok := (my == "black" and black_ok) or (my == "red" and red_ok)
		var own_n := _junqi_own_piece_count()
		if mine_ok:
			if my == "black":
				_set_status(MWi18n.t(
					"已确认 · 等待红方确认布阵",
					"Confirmed · waiting for Red to confirm"
				) + hand_note)
			else:
				_set_status(MWi18n.t(
					"已确认 · 等待黑方确认布阵",
					"Confirmed · waiting for Black to confirm"
				) + hand_note)
		elif own_n >= 25:
			_set_status(MWi18n.t(
				"可拖换己子微调 · 点「确认布阵」开战",
				"Drag-swap to tune · tap Confirm to start"
			) + hand_note)
		else:
			_set_status(MWi18n.t(
				"布阵 · 先「随机布阵」，可再手调（本方在左）",
				"Layout · Auto layout, then tune (you on the left)"
			) + hand_note)
		return
	if status == "finished":
		_trigger_junqi_reveal(d)
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
	var turn := str(d.get("turn", "")).strip_edges().to_lower()
	var mine_turn := _junqi_is_my_turn(d)
	var turn_line := ""
	if mine_turn:
		turn_line = MWi18n.t("轮到你 · 点己子再点目标格", "Your turn · pick piece, then target")
	elif vs_ai:
		turn_line = MWi18n.t("AI 思考中…", "AI thinking…")
	elif turn == "black":
		turn_line = MWi18n.t("等待黑方行棋…", "Waiting for Black to move…")
	elif turn == "red":
		turn_line = MWi18n.t("等待红方行棋…", "Waiting for Red to move…")
	else:
		turn_line = (
			MWi18n.t("等待同步…", "Syncing…")
			+ " (turn=%s my=%s)" % [turn, my]
		)
	var battle: Variant = d.get("last_battle", null)
	var battle_line := ""
	if typeof(battle) == TYPE_DICTIONARY and battle != null:
		var res := str(battle.get("result", ""))
		if res != "":
			var atk := str(JUNQI_LABEL.get(str(battle.get("attacker", "?")), "?"))
			var dfd := str(JUNQI_LABEL.get(str(battle.get("defender", "?")), "?"))
			var res_zh := res
			match res:
				"win":
					res_zh = MWi18n.t("吃掉", "captures")
				"lose":
					res_zh = MWi18n.t("阵亡", "falls")
				"draw":
					res_zh = MWi18n.t("同尽", "both fall")
				"flag_win":
					res_zh = MWi18n.t("扛旗", "takes flag")
			battle_line = "%s %s %s" % [atk, res_zh, dfd]
	if battle_line != "":
		# Clash first, turn last — avoids “双方都在等” misread after capture.
		_set_status(battle_line + "\n" + turn_line + hand_note)
	else:
		_set_status(turn_line + hand_note)


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


const HIGHWAY_SEGS: Array = [
	[[0,0],[0,1]],
	[[0,0],[1,0]],
	[[0,1],[0,2]],
	[[0,1],[1,1]],
	[[0,2],[0,3]],
	[[0,2],[1,2]],
	[[0,3],[0,4]],
	[[0,3],[1,3]],
	[[0,4],[1,4]],
	[[1,0],[1,1]],
	[[1,0],[2,0]],
	[[1,0],[2,1]],
	[[1,1],[1,2]],
	[[1,1],[2,1]],
	[[1,2],[1,3]],
	[[1,2],[2,1]],
	[[1,2],[2,2]],
	[[1,2],[2,3]],
	[[1,3],[1,4]],
	[[1,3],[2,3]],
	[[1,4],[2,3]],
	[[1,4],[2,4]],
	[[2,0],[2,1]],
	[[2,0],[3,0]],
	[[2,1],[2,2]],
	[[2,1],[3,0]],
	[[2,1],[3,1]],
	[[2,1],[3,2]],
	[[2,2],[2,3]],
	[[2,2],[3,2]],
	[[2,3],[2,4]],
	[[2,3],[3,2]],
	[[2,3],[3,3]],
	[[2,3],[3,4]],
	[[2,4],[3,4]],
	[[3,0],[3,1]],
	[[3,0],[4,0]],
	[[3,0],[4,1]],
	[[3,1],[3,2]],
	[[3,1],[4,1]],
	[[3,2],[3,3]],
	[[3,2],[4,1]],
	[[3,2],[4,2]],
	[[3,2],[4,3]],
	[[3,3],[3,4]],
	[[3,3],[4,3]],
	[[3,4],[4,3]],
	[[3,4],[4,4]],
	[[4,0],[4,1]],
	[[4,0],[5,0]],
	[[4,1],[4,2]],
	[[4,1],[5,0]],
	[[4,1],[5,1]],
	[[4,1],[5,2]],
	[[4,2],[4,3]],
	[[4,2],[5,2]],
	[[4,3],[4,4]],
	[[4,3],[5,2]],
	[[4,3],[5,3]],
	[[4,3],[5,4]],
	[[4,4],[5,4]],
	[[5,0],[5,1]],
	[[5,0],[6,0]],
	[[5,1],[5,2]],
	[[5,2],[5,3]],
	[[5,2],[6,2]],
	[[5,3],[5,4]],
	[[5,4],[6,4]],
	[[6,0],[6,1]],
	[[6,0],[7,0]],
	[[6,0],[7,1]],
	[[6,1],[6,2]],
	[[6,1],[7,1]],
	[[6,2],[6,3]],
	[[6,2],[7,1]],
	[[6,2],[7,2]],
	[[6,2],[7,3]],
	[[6,3],[6,4]],
	[[6,3],[7,3]],
	[[6,4],[7,3]],
	[[6,4],[7,4]],
	[[7,0],[7,1]],
	[[7,0],[8,0]],
	[[7,1],[7,2]],
	[[7,1],[8,0]],
	[[7,1],[8,1]],
	[[7,1],[8,2]],
	[[7,2],[7,3]],
	[[7,2],[8,2]],
	[[7,3],[7,4]],
	[[7,3],[8,2]],
	[[7,3],[8,3]],
	[[7,3],[8,4]],
	[[7,4],[8,4]],
	[[8,0],[8,1]],
	[[8,0],[9,0]],
	[[8,0],[9,1]],
	[[8,1],[8,2]],
	[[8,1],[9,1]],
	[[8,2],[8,3]],
	[[8,2],[9,1]],
	[[8,2],[9,2]],
	[[8,2],[9,3]],
	[[8,3],[8,4]],
	[[8,3],[9,3]],
	[[8,4],[9,3]],
	[[8,4],[9,4]],
	[[9,0],[9,1]],
	[[9,0],[10,0]],
	[[9,1],[9,2]],
	[[9,1],[10,0]],
	[[9,1],[10,1]],
	[[9,1],[10,2]],
	[[9,2],[9,3]],
	[[9,2],[10,2]],
	[[9,3],[9,4]],
	[[9,3],[10,2]],
	[[9,3],[10,3]],
	[[9,3],[10,4]],
	[[9,4],[10,4]],
	[[10,0],[10,1]],
	[[10,0],[11,0]],
	[[10,1],[10,2]],
	[[10,1],[11,1]],
	[[10,2],[10,3]],
	[[10,2],[11,2]],
	[[10,3],[10,4]],
	[[10,3],[11,3]],
	[[10,4],[11,4]],
	[[11,0],[11,1]],
	[[11,1],[11,2]],
	[[11,2],[11,3]],
	[[11,3],[11,4]]
]

const RAILWAY_SEGS: Array = [
	[[1,0],[1,1]],
	[[1,0],[2,0]],
	[[1,1],[1,2]],
	[[1,2],[1,3]],
	[[1,3],[1,4]],
	[[1,4],[2,4]],
	[[2,0],[3,0]],
	[[2,4],[3,4]],
	[[3,0],[4,0]],
	[[3,4],[4,4]],
	[[4,0],[5,0]],
	[[4,4],[5,4]],
	[[5,0],[5,1]],
	[[5,0],[6,0]],
	[[5,1],[5,2]],
	[[5,2],[5,3]],
	[[5,3],[5,4]],
	[[5,4],[6,4]],
	[[6,0],[6,1]],
	[[6,0],[7,0]],
	[[6,1],[6,2]],
	[[6,2],[6,3]],
	[[6,3],[6,4]],
	[[6,4],[7,4]],
	[[7,0],[8,0]],
	[[7,4],[8,4]],
	[[8,0],[9,0]],
	[[8,4],[9,4]],
	[[9,0],[10,0]],
	[[9,4],[10,4]],
	[[10,0],[10,1]],
	[[10,1],[10,2]],
	[[10,2],[10,3]],
	[[10,3],[10,4]]
]

func _draw_junqi_board() -> void:
	"""Reference-style junqi board: grid lines + railways + camps + pieces."""
	var detail := _view_detail()
	var sz := _junqi_board_size()
	_draw_wood_frame(sz, Color(0.52, 0.68, 0.42))
	var m: Dictionary = _junqi_layout_metrics()
	var cw: float = m["cw"]
	var ch: float = m["ch"]
	var origin: Vector2 = m["origin"]
	var gap: float = m["gap"]
	var cells: Array = detail.get("cells", [])
	var by_key: Dictionary = {}
	for cell in cells:
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		by_key["%d,%d" % [int(cell.get("r", -1)), int(cell.get("c", -1))]] = cell

	# === Cell backgrounds ===
	for r in JUNQI_ROWS:
		for c in JUNQI_COLS:
			var center := _junqi_cell_center(r, c, origin, cw, ch, gap)
			var half := Vector2(cw, ch) * 0.46
			var rect := Rect2(center - half, half * 2.0)
			var cell: Dictionary = by_key.get("%d,%d" % [r, c], {})
			var kind := str(cell.get("kind", "station"))
			if kind == "hq":
				_board_ctrl.draw_rect(rect, Color(0.82, 0.68, 0.32))
				_board_ctrl.draw_rect(rect.grow(-2.0), Color(0.92, 0.8, 0.44), false, 1.5)
			elif kind == "camp":
				_board_ctrl.draw_rect(rect, Color(0.58, 0.72, 0.5, 0.6))
			else:
				_board_ctrl.draw_rect(rect, Color(0.58, 0.74, 0.48, 0.5))
			if _sel.x == c and _sel.y == r:
				_board_ctrl.draw_rect(rect.grow(1.0), Color(0.95, 0.85, 0.2, 0.55), false, 2.5)

	# === Highway lines (thin, all road connections) ===
	var col_hw := Color(0.35, 0.48, 0.28, 0.65)
	for seg in HIGHWAY_SEGS:
		var a: Array = seg[0]
		var b: Array = seg[1]
		var p0 := _junqi_cell_center(int(a[0]), int(a[1]), origin, cw, ch, gap)
		var p1 := _junqi_cell_center(int(b[0]), int(b[1]), origin, cw, ch, gap)
		_board_ctrl.draw_line(p0, p1, col_hw, 1.2)

	# === Mountain strip ===
	_draw_junqi_mountains(origin, cw, ch, gap)

	# === Railway lines (thick dark, prominent) ===
	_draw_junqi_rails(origin, cw, ch, gap)

	# === Camps (small circles with X) ===
	var camp_col := Color(0.55, 0.72, 0.88)
	var camp_rim := Color(0.18, 0.32, 0.55)
	var camp_x := Color(0.12, 0.28, 0.5, 0.85)
	for r in JUNQI_ROWS:
		for c in JUNQI_COLS:
			var cell: Dictionary = by_key.get("%d,%d" % [r, c], {})
			if str(cell.get("kind", "")) != "camp":
				continue
			var center := _junqi_cell_center(r, c, origin, cw, ch, gap)
			var rad: float = min(cw, ch) * 0.3
			_board_ctrl.draw_circle(center, rad, camp_col)
			_board_ctrl.draw_arc(center, rad, 0, TAU, 28, camp_rim, 1.8)
			var arm: float = rad * 0.65
			_board_ctrl.draw_line(center + Vector2(-arm, -arm), center + Vector2(arm, arm), camp_x, 1.8)
			_board_ctrl.draw_line(center + Vector2(-arm, arm), center + Vector2(arm, -arm), camp_x, 1.8)

	# === Pieces ===
	for r in JUNQI_ROWS:
		for c in JUNQI_COLS:
			var cell2: Dictionary = by_key.get("%d,%d" % [r, c], {})
			var piece: Variant = cell2.get("piece", null)
			if typeof(piece) != TYPE_DICTIONARY or piece == null:
				continue
			var jx := c
			var jy := r
			var jscale := _anim_scale(jx, jy)
			var jalpha := _anim_alpha(jx, jy)
			var jflip := 1.0
			var jkey := "%d,%d" % [jx, jy]
			if _piece_anims.has(jkey) and str(_piece_anims[jkey].get("kind", "")) == "flip":
				var jt := float(_piece_anims[jkey].get("t", 0.0)) / float(_piece_anims[jkey].get("dur", 1.0))
				jflip = absf(cos(jt * PI))
			_draw_junqi_tile(
				_junqi_cell_center(r, c, origin, cw, ch, gap),
				min(cw, ch) * jscale,
				str(piece.get("side", "")),
				str(piece.get("type", "?")),
				jalpha,
				jflip
			)


func _junqi_cell_center(r: int, c: int, origin: Vector2, cw: float, ch: float, gap: float = 0.0) -> Vector2:
	"""Map model (r,c) → landscape screen center (row→X, col→Y)."""
	var vr := _junqi_view_r(r)
	var x := origin.x + cw * (float(vr) + 0.5)
	if vr >= 6:
		x += gap
	return Vector2(x, origin.y + ch * (float(c) + 0.5))


func _draw_junqi_mountains(origin: Vector2, cw: float, ch: float, gap: float) -> void:
	"""山界 strip between halves — two impassable circles (cols 1 & 3)."""
	var x_mid := origin.x + cw * 6.0 + gap * 0.5
	var strip := Rect2(
		Vector2(x_mid - gap * 0.48, origin.y + ch * 0.08),
		Vector2(gap * 0.96, ch * float(JUNQI_COLS) - ch * 0.16)
	)
	_board_ctrl.draw_rect(strip, Color(0.42, 0.34, 0.22, 0.55))
	_board_ctrl.draw_rect(strip.grow(-1.5), Color(0.28, 0.22, 0.14, 0.35), false, 1.2)
	# Passable frontline corridors (cols 0 / 2 / 4).
	for c in [0, 2, 4]:
		var cy := origin.y + ch * (float(c) + 0.5)
		var lane := Rect2(x_mid - gap * 0.42, cy - ch * 0.16, gap * 0.84, ch * 0.32)
		_board_ctrl.draw_rect(lane, Color(0.62, 0.72, 0.48, 0.7))
		_board_ctrl.draw_line(
			Vector2(x_mid - gap * 0.4, cy),
			Vector2(x_mid + gap * 0.4, cy),
			Color(0.22, 0.18, 0.1, 0.85),
			2.0 if c == 2 else 2.8
		)
	var font: Font = MWFonts.font() if MWFonts != null else ThemeDB.fallback_font
	var rad := minf(gap * 0.42, ch * 0.42)
	for c in [1, 3]:
		var cy := origin.y + ch * (float(c) + 0.5)
		var center := Vector2(x_mid, cy)
		_board_ctrl.draw_circle(center + Vector2(1.0, 1.2), rad, Color(0, 0, 0, 0.22))
		_board_ctrl.draw_circle(center, rad, Color(0.48, 0.4, 0.28))
		_board_ctrl.draw_circle(center, rad * 0.78, Color(0.58, 0.5, 0.34))
		_board_ctrl.draw_arc(center, rad, 0.0, TAU, 32, Color(0.28, 0.2, 0.12), 2.0)
		_board_ctrl.draw_line(
			center + Vector2(-rad * 0.35, rad * 0.1),
			center + Vector2(0.0, -rad * 0.45),
			Color(0.32, 0.26, 0.16, 0.7),
			1.4
		)
		_board_ctrl.draw_line(
			center + Vector2(rad * 0.35, rad * 0.1),
			center + Vector2(0.0, -rad * 0.45),
			Color(0.32, 0.26, 0.16, 0.7),
			1.4
		)
		var label := "山界"
		var fs := int(clampf(rad * 0.55, 9.0, 14.0))
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_board_ctrl.draw_string(
			font,
			center - text_size * 0.5 + Vector2(0, text_size.y * 0.35),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			Color(0.95, 0.9, 0.75)
		)


func _draw_junqi_rails(origin: Vector2, cw: float, ch: float, gap: float) -> void:
	"""Railway lines along actual rail paths."""
	var col_rail := Color(0.15, 0.12, 0.06, 0.9)
	for seg in RAILWAY_SEGS:
		var a: Array = seg[0]
		var b: Array = seg[1]
		var p0 := _junqi_cell_center(int(a[0]), int(a[1]), origin, cw, ch, gap)
		var p1 := _junqi_cell_center(int(b[0]), int(b[1]), origin, cw, ch, gap)
		_board_ctrl.draw_line(p0, p1, col_rail, 3.5)


func _draw_junqi_tile(center: Vector2, cell: float, side: String, ptype: String, alpha: float = 1.0, flip_x: float = 1.0) -> void:
	"""Draw a bevelled rectangular tile. flip_x<1 simulates card-flip rotation."""
	var tw := cell * 0.78
	var th := cell * 0.62
	# flip: squash X to simulate Y-axis rotation; hide text when edge-on
	var eff_tw := tw * flip_x
	var rect := Rect2(center - Vector2(eff_tw, th) * 0.5, Vector2(eff_tw, th))
	var shadow_col := Color(0, 0, 0, 0.35 * alpha)
	_board_ctrl.draw_rect(Rect2(rect.position + Vector2(1.5, 2.0), rect.size), shadow_col)
	var body := Color(0.12, 0.12, 0.14, alpha) if side == "black" else Color(0.78, 0.18, 0.14, alpha)
	var rim := Color(0.35, 0.35, 0.38, alpha) if side == "black" else Color(0.95, 0.45, 0.35, alpha)
	_board_ctrl.draw_rect(rect, body)
	_board_ctrl.draw_rect(rect, rim, false, 1.4)
	if flip_x > 0.15:
		_board_ctrl.draw_line(
			rect.position + Vector2(1, 1),
			rect.position + Vector2(rect.size.x - 1, 1),
			Color(1, 1, 1, 0.22 * alpha),
			1.0
		)
		var label := str(JUNQI_LABEL.get(ptype, ptype))
		var font: Font = MWFonts.font() if MWFonts != null else ThemeDB.fallback_font
		var fs := int(clampf(min(eff_tw, th) * 0.55, 10.0, 22.0))
		var text_col := Color(0.95, 0.92, 0.75, alpha) if side == "black" else Color(1.0, 0.96, 0.88, alpha)
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


func _junqi_view_r_at_x(x: float, origin_x: float, cw: float, gap: float) -> int:
	"""Hit-test landscape X → view row; mountain gap returns -1."""
	var rel := x - origin_x
	var left_w := cw * 6.0
	if rel < 0.0:
		return -1
	if rel < left_w:
		return int(floor(rel / cw))
	if rel < left_w + gap:
		return -1
	var right := int(floor((rel - left_w - gap) / cw))
	if right < 0:
		return -1
	return 6 + right


func _junqi_layout_metrics() -> Dictionary:
	"""Landscape metrics: cell width along rows (12), height along cols (5)."""
	var sz := _junqi_board_size()
	var pad := 8.0
	var inner := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
	var gap := clampf(inner.size.x * 0.07, 22.0, 40.0)
	var cw := (inner.size.x - gap) / float(JUNQI_ROWS)
	var ch := inner.size.y / float(JUNQI_COLS)
	var origin := inner.position
	return {"origin": origin, "cw": cw, "ch": ch, "gap": gap}


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
	if game == "wudui":
		_on_wudui_click(mb.position, d)
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
	var status := _junqi_resolved_status(d)
	var my := _my_junqi_side()
	if my == "":
		return
	var m: Dictionary = _junqi_layout_metrics()
	var origin: Vector2 = m["origin"]
	var cw: float = m["cw"]
	var ch: float = m["ch"]
	var gap: float = m["gap"]
	var view_r := _junqi_view_r_at_x(pos.x, origin.x, cw, gap)
	var col := int(floor((pos.y - origin.y) / ch))
	if col < 0 or view_r < 0 or col >= JUNQI_COLS or view_r >= JUNQI_ROWS:
		return
	var row := _junqi_model_r(view_r)
	if status == "layout" or status == "idle":
		var ready: Dictionary = d.get("layout_ready", {}) as Dictionary
		if bool(ready.get(my, false)):
			return
		_on_junqi_layout_click(row, col, d, my)
		return
	if status != "playing":
		return
	if not _junqi_is_my_turn(d):
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
	_pending_junqi_move = {
		"fx": _sel.y,
		"fy": _sel.x,
		"tx": row,
		"ty": col,
	}
	ws.send_cmd({
		"action": "chess_move",
		"table_id": _view_table_id,
		"fx": _sel.y,
		"fy": _sel.x,
		"tx": row,
		"ty": col,
	})
	# Keep _sel until chess_table_update or chess_reject (avoids "ghost move").
	_board_ctrl.queue_redraw()


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


func _sync_ai_countdown() -> void:
	"""Show/hide the wudui AI-fill countdown for the open board."""
	if _ai_countdown_label == null or _ai_countdown_timer == null:
		return
	if not _board_open() or _ai_fill_at <= 0.0:
		_ai_countdown_label.visible = false
		_ai_countdown_timer.stop()
		return
	_ai_countdown_timer.start()
	_tick_ai_countdown()


func _tick_ai_countdown() -> void:
	if _ai_countdown_label == null or _ai_fill_at <= 0.0:
		return
	var remain := int(ceili(_ai_fill_at - Time.get_unix_time_from_system()))
	if remain <= 0:
		# AI fills momentarily; hide until the next broadcast confirms.
		_ai_fill_at = 0.0
		_sync_ai_countdown()
		return
	_ai_countdown_label.text = MWi18n.t(
		"无人加入 · %d 秒后自动匹配 AI", "No player — AI joins in %ds"
	) % remain
	_ai_countdown_label.visible = true


# ── Chess-FX ──────────────────────────────────────────────────────────

const _BJ_CARD_W := 64.0
const _BJ_CARD_H := 92.0
const _BJ_GAP := 10.0
var _card_tex: Dictionary = {}


func _bj_hand_origin(count: int, row_y: float, area: Vector2) -> Vector2:
	"""Center a hand of `count` cards horizontally at row_y."""
	var total := count * _BJ_CARD_W + maxi(count - 1, 0) * _BJ_GAP
	return Vector2((area.x - total) * 0.5, row_y)


func _bj_deck_pos(area: Vector2) -> Vector2:
	"""Shoe stub at top-right corner of the felt."""
	return Vector2(area.x - _BJ_CARD_W - 14.0, 14.0)


func _card_tex_path(card: String) -> String:
	"""Wire card ('AS' / '10H' / 'JOKER' / '??') → Kenney texture path."""
	if card == "??":
		return "res://assets/kenney_cards/card_back.png"
	if card.begins_with("JOKER"):
		return "res://assets/kenney_cards/card_joker_black.png"
	var suit := card.right(1)
	var rank := card.left(card.length() - 1)
	var suit_name: String = str({"S": "spades", "H": "hearts", "D": "diamonds", "C": "clubs"}.get(suit, ""))
	if suit_name == "":
		return ""
	if rank.length() == 1 and rank.is_valid_int():
		rank = "0" + rank
	return "res://assets/kenney_cards/card_%s_%s.png" % [suit_name, rank]


func _card_texture(card: String) -> Texture2D:
	if _card_tex.has(card):
		return _card_tex[card]
	var tex: Texture2D = load(_card_tex_path(card)) as Texture2D if _card_tex_path(card) != "" else null
	_card_tex[card] = tex
	return tex


func _draw_bj_card(pos: Vector2, card: String, scale_x: float = 1.0, alpha: float = 1.0) -> void:
	_draw_card_sized(pos, Vector2(_BJ_CARD_W, _BJ_CARD_H), card, scale_x, alpha)


func _draw_card_sized(pos: Vector2, size: Vector2, card: String, scale_x: float = 1.0, alpha: float = 1.0) -> void:
	"""Code-drawn card face; '??' = face-down back. scale_x<1 fakes the flip."""
	var w := size.x * maxf(scale_x, 0.02)
	var h := size.y
	var rect := Rect2(pos + Vector2((size.x - w) * 0.5, 0), Vector2(w, h))
	var tex := _card_texture(card)
	if tex != null:
		# Contain-fit: Kenney textures are square 64x64; keep aspect inside the
		# portrait slot so card art isn't stretched (scale_x<1 fakes the flip).
		var tr := rect
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		if tw > 0.0 and th > 0.0:
			var fit := minf(rect.size.x / tw, rect.size.y / th)
			var fw := tw * fit
			var fh := th * fit
			tr = Rect2(rect.position + Vector2((rect.size.x - fw) * 0.5, (rect.size.y - fh) * 0.5), Vector2(fw, fh))
		_board_ctrl.draw_texture_rect(tex, tr, false, Color(1, 1, 1, alpha))
		return
	if card == "??":
		_board_ctrl.draw_rect(rect, Color(0.16, 0.3, 0.52, alpha))
		_board_ctrl.draw_rect(rect.grow(-4.0), Color(0.24, 0.42, 0.66, alpha))
		_board_ctrl.draw_rect(rect.grow(-4.0), Color(0.1, 0.18, 0.32, alpha), false, 1.5)
		_board_ctrl.draw_rect(rect, Color(0.06, 0.1, 0.2, alpha), false, 2.0)
		return
	_board_ctrl.draw_rect(rect, Color(0.96, 0.95, 0.92, alpha))
	_board_ctrl.draw_rect(rect, Color(0.55, 0.5, 0.45, alpha), false, 1.5)
	var suit := card.right(1)
	var rank := card.left(card.length() - 1)
	var red := suit == "H" or suit == "D"
	var ink := Color(0.78, 0.16, 0.14, alpha) if red else Color(0.12, 0.12, 0.14, alpha)
	var suit_glyphs: Dictionary = {"S": "♠", "H": "♥", "D": "♦", "C": "♣"}
	var glyph: String = str(suit_glyphs.get(suit, "?"))
	if scale_x > 0.55:
		var f: Font = MWFonts.font() if MWFonts != null else null
		_board_ctrl.draw_string(
			f if f != null else ThemeDB.fallback_font,
			rect.position + Vector2(7.0, 22.0),
			rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink
		)
		_board_ctrl.draw_string(
			f if f != null else ThemeDB.fallback_font,
			rect.position + Vector2(7.0, 42.0),
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink
		)
		_board_ctrl.draw_string(
			f if f != null else ThemeDB.fallback_font,
			rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.62),
			glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, 30, Color(ink.r, ink.g, ink.b, alpha * 0.35)
		)


func _bj_anim_for(key: String) -> Dictionary:
	return _bj_anims.get(key, {})


func _draw_blackjack_board() -> void:
	"""Green felt: dealer (top) / opponents (mid) / my hand (bottom) + anims."""
	var d := _view_detail()
	var sz: Vector2 = _board_ctrl.custom_minimum_size
	_board_ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.38, 0.22, 0.1))
	var pad := 8.0
	var felt := Rect2(Vector2(pad, pad), sz - Vector2(pad, pad) * 2.0)
	_board_ctrl.draw_rect(felt, Color(0.1, 0.38, 0.24))
	_board_ctrl.draw_rect(felt, Color(0.05, 0.2, 0.12, 0.8), false, 2.0)
	var area := felt.size
	var deck := _bj_deck_pos(area)
	# Shoe stub.
	_draw_bj_card(deck, "??", 1.0, 0.85)
	var my_sid := _effective_sid()
	var hands: Dictionary = d.get("hands", {}) as Dictionary
	var values: Dictionary = d.get("hand_values", {}) as Dictionary
	var players: Array = d.get("players", []) as Array
	var results: Dictionary = d.get("results", {}) as Dictionary
	var active := str(d.get("active_sid", "")).strip_edges()
	var dealer: Array = d.get("dealer_cards", [])
	# Row layout: dealer top, other players middle (top-down), my hand bottom.
	var rows: Array = []
	rows.append({"key": "D", "cards": dealer, "y": 22.0})
	var others: Array = []
	for sid in players:
		if str(sid) != my_sid:
			others.append(str(sid))
	for i in others.size():
		rows.append({"key": "O%d" % i, "cards": hands.get(others[i], []), "y": 96.0 + i * 86.0})
	# Spectator: no own hand — all hands render as opponent rows (no fake "你").
	var mine: Array = []
	if hands.has(my_sid):
		mine = hands.get(my_sid, [])
	elif hands.is_empty():
		mine = d.get("player_cards", [])  # legacy single-hand payload
	rows.append({"key": "P", "cards": mine, "y": area.y - _BJ_CARD_H - 22.0})
	for side in rows:
		var cards: Array = side["cards"]
		var origin := _bj_hand_origin(cards.size(), float(side["y"]), area)
		for i in cards.size():
			var key := "%s%d" % [str(side["key"]), i]
			var target := origin + Vector2(i * (_BJ_CARD_W + _BJ_GAP), 0)
			var card := str(cards[i])
			var anim := _bj_anim_for(key)
			var pos := target
			var sx := 1.0
			if not anim.is_empty():
				var t := clampf(float(anim.get("t", 1.0)) / float(anim.get("dur", 1.0)), 0.0, 1.0)
				match str(anim.get("kind", "")):
					"deal":
						pos = deck.lerp(target, ease(t, -1.6))
					"flip":
						sx = absf(cos(t * PI))
						if t < 0.5:
							card = "??"
			_draw_bj_card(pos, card, sx)
	# Hand values next to each row + result/active markers.
	var f: Font = MWFonts.font() if MWFonts != null else null
	var font := f if f != null else ThemeDB.fallback_font
	if not dealer.is_empty():
		var dv := int(d.get("dealer_value", 0))
		var dhide := false
		for c in dealer:
			if str(c) == "??":
				dhide = true
		var dtext := ("%s: %s" % [MWi18n.t("庄家", "Dealer"), "?" if dhide else str(dv)])
		_board_ctrl.draw_string(font, Vector2(16.0, 40.0), dtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.94, 0.9))
	for i in others.size():
		var osid: String = others[i]
		var ocards: Array = hands.get(osid, [])
		if ocards.is_empty():
			continue
		var otext := "%s: %s" % [MWi18n.t("对手", "Opponent"), str(values.get(osid, 0))]
		if active == osid:
			otext += MWi18n.t(" ⏳", " ⏳")
		var ores := str(results.get(osid, ""))
		if ores != "":
			otext += "  " + _bj_result_text(ores)
		_board_ctrl.draw_string(font, Vector2(16.0, 96.0 + i * 86.0 + 18.0), otext, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.94, 0.9))
	if not mine.is_empty():
		var ptext := "%s: %s" % [MWi18n.t("你", "You"), str(values.get(my_sid, d.get("player_value", 0)))]
		if active == my_sid:
			ptext += MWi18n.t(" ⏳", " ⏳")
		var mres := str(results.get(my_sid, ""))
		if mres != "":
			ptext += "  " + _bj_result_text(mres)
		_board_ctrl.draw_string(font, Vector2(16.0, area.y - 30.0), ptext, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.94, 0.9))


func _bj_result_text(result: String) -> String:
	match result:
		"blackjack":
			return MWi18n.t("21点！", "Blackjack!")
		"win":
			return MWi18n.t("胜 🎉", "Win 🎉")
		"lose":
			return MWi18n.t("负", "Lose")
		"push":
			return MWi18n.t("平", "Push")
	return ""


func _detect_piece_changes(d: Dictionary, game: String) -> void:
	"""Diff prev/new board cells → populate _piece_anims for animations."""
	var cells: Array = d.get("cells", [])
	var s := _board_size() if game != "junqi" else JUNQI_ROWS * JUNQI_COLS
	if _prev_cells.is_empty() or _prev_cells.size() != cells.size():
		_prev_cells = cells.duplicate()
		return
	# J2: collect moves for slide animation (from → to).
	var moves: Array = []
	for idx in mini(cells.size(), _prev_cells.size()):
		var old_v := _cell_val_at(_prev_cells, idx, game)
		var new_v := _cell_val_at(cells, idx, game)
		if old_v == new_v:
			continue
		var xy := _idx_to_xy(idx, game)
		var key := "%d,%d" % [xy.x, xy.y]
		if old_v == 0 and new_v != 0:
			_piece_anims[key] = {"kind": "place", "t": 0.0, "dur": 0.35}
			_play_sfx("place")
		elif old_v != 0 and new_v == 0:
			# Check if this is the "from" of a move (piece moved to empty → capture anim at destination).
			moves.append({"from": xy, "key": key})
			_piece_anims[key] = {"kind": "capture", "t": 0.0, "dur": 0.25}
			_play_sfx("capture")
		elif old_v != new_v:
			_piece_anims[key] = {"kind": "flip", "t": 0.0, "dur": 0.3}
			_play_sfx("flip")
	# J2: attach "move" anim at destination cells (from cell captured, to cell placed).
	for m in moves:
		var from_xy: Vector2i = m["from"]
		# Find the cell that changed from 0→non-zero and is not yet animated.
		for idx2 in cells.size():
			var ov := _cell_val_at(_prev_cells, idx2, game)
			var nv := _cell_val_at(cells, idx2, game)
			if ov != 0 or nv == 0:
				continue
			var to_xy := _idx_to_xy(idx2, game)
			var to_key := "%d,%d" % [to_xy.x, to_xy.y]
			if _piece_anims.has(to_key):
				continue
			_piece_anims[to_key] = {
				"kind": "move",
				"t": 0.0,
				"dur": 0.2,
				"from_x": from_xy.x,
				"from_y": from_xy.y,
			}
			break
	_prev_cells = cells.duplicate()


func _detect_bj_changes(d: Dictionary) -> void:
	"""Diff player/dealer hands → deal-in anims + hole-card flip."""
	var my_sid := _effective_sid()
	var hands: Dictionary = d.get("hands", {}) as Dictionary
	var players: Array = d.get("players", []) as Array
	var mine: Array = []
	if hands.has(my_sid):
		mine = hands.get(my_sid, [])
	elif hands.is_empty():
		mine = d.get("player_cards", [])
	var dealer: Array = d.get("dealer_cards", [])
	var prev_hands: Dictionary = _bj_prev.get("hands", {}) as Dictionary
	var prev_p: Array = prev_hands.get(my_sid, _bj_prev.get("player", []))
	var prev_d: Array = _bj_prev.get("dealer", [])
	for i in mine.size():
		var key := "P%d" % i
		if i >= prev_p.size():
			_bj_anims[key] = {"kind": "deal", "t": 0.0, "dur": 0.4}
	var oi := 0
	for sid in players:
		var osid := str(sid)
		if osid == my_sid:
			continue
		var ocards: Array = hands.get(osid, [])
		var prev_o: Array = prev_hands.get(osid, [])
		for i in ocards.size():
			if i >= prev_o.size():
				_bj_anims["O%d%d" % [oi, i]] = {"kind": "deal", "t": 0.0, "dur": 0.4}
		oi += 1
	for i in dealer.size():
		var key := "D%d" % i
		if i >= prev_d.size():
			_bj_anims[key] = {"kind": "deal", "t": 0.0, "dur": 0.4}
	if prev_d.size() >= 2 and dealer.size() >= 2 and str(prev_d[1]) == "??" and str(dealer[1]) != "??":
		_bj_anims["D1"] = {"kind": "flip", "t": 0.0, "dur": 0.45}
	var new_hands := {}
	for sid in hands:
		new_hands[str(sid)] = (hands[sid] as Array).duplicate()
	_bj_prev = {"hands": new_hands, "dealer": dealer.duplicate()}


func _tick_bj_anims(delta: float) -> void:
	if _bj_anims.is_empty():
		return
	var dirty := false
	var done: Array[String] = []
	for key in _bj_anims:
		var a: Dictionary = _bj_anims[key]
		a["t"] = float(a.get("t", 0.0)) + delta
		if float(a["t"]) >= float(a.get("dur", 1.0)):
			done.append(key)
		else:
			dirty = true
	for key in done:
		_bj_anims.erase(key)
	if dirty and _board_ctrl != null:
		_board_ctrl.queue_redraw()


func _cell_val_at(cells: Array, idx: int, game: String) -> int:
	if idx >= cells.size():
		return 0
	if game == "junqi":
		var cell: Variant = cells[idx]
		if typeof(cell) != TYPE_DICTIONARY:
			return 0
		var piece: Variant = cell.get("piece", null)
		if typeof(piece) != TYPE_DICTIONARY or piece == null:
			return 0
		var ptype := str(piece.get("type", ""))
		if ptype == "":
			return 0
		# Encode side+type so capture replacement (工兵→军长) triggers anim.
		var side := str(piece.get("side", ""))
		return 10 + (1 if side == "black" else 2) * 100 + ptype.hash() % 97
	return int(cells[idx])


func _idx_to_xy(idx: int, game: String) -> Vector2i:
	if game == "junqi":
		return Vector2i(idx % JUNQI_COLS, idx / JUNQI_COLS)
	var s := _board_size()
	return Vector2i(idx % s, idx / s)


func _tick_piece_anims(delta: float) -> void:
	if _piece_anims.is_empty():
		return
	var done: Array = []
	var needs_redraw := false
	for key in _piece_anims.keys():
		var a: Dictionary = _piece_anims[key]
		a["t"] = float(a["t"]) + delta
		var t := float(a["t"])
		var dur := float(a.get("dur", 1.0))
		if t >= dur:
			done.append(key)
		elif t >= 0.0:
			needs_redraw = true
	for key in done:
		_piece_anims.erase(key)
	if _board_ctrl != null and (needs_redraw or not _piece_anims.is_empty()):
		_board_ctrl.queue_redraw()


func _anim_scale(x: int, y: int) -> float:
	var key := "%d,%d" % [x, y]
	if not _piece_anims.has(key):
		return 1.0
	var a: Dictionary = _piece_anims[key]
	var t_raw := float(a.get("t", 0.0))
	if t_raw < 0.0:
		return 1.0  ## stagger delay — not yet animating
	var kind := str(a.get("kind", ""))
	var t := t_raw / float(a.get("dur", 1.0))
	if kind == "place":
		if t < 0.5:
			return lerpf(0.0, 1.15, t * 2.0)
		return lerpf(1.15, 1.0, (t - 0.5) * 2.0)
	if kind == "capture":
		return lerpf(1.0, 0.0, t)
	if kind == "flip":
		# flip: scale 1→0.5→1 with slight overshoot
		if t < 0.5:
			return lerpf(1.0, 0.3, t * 2.0)
		return lerpf(0.3, 1.0, (t - 0.5) * 2.0)
	if kind == "move":
		# J2: quick pop-in from smaller (slide feel without position interp)
		if t < 0.6:
			return lerpf(0.4, 1.05, t / 0.6)
		return lerpf(1.05, 1.0, (t - 0.6) / 0.4)
	return 1.0


func _anim_alpha(x: int, y: int) -> float:
	var key := "%d,%d" % [x, y]
	if not _piece_anims.has(key):
		return 1.0
	var a: Dictionary = _piece_anims[key]
	var t_raw := float(a.get("t", 0.0))
	if t_raw < 0.0:
		return 1.0
	if str(a.get("kind", "")) == "capture":
		return lerpf(1.0, 0.0, t_raw / float(a.get("dur", 1.0)))
	return 1.0


func _anim_y_offset(x: int, y: int) -> float:
	var key := "%d,%d" % [x, y]
	if not _piece_anims.has(key):
		return 0.0
	var a: Dictionary = _piece_anims[key]
	var t_raw := float(a.get("t", 0.0))
	if t_raw < 0.0:
		return 0.0
	if str(a.get("kind", "")) == "capture":
		return lerpf(0.0, 20.0, t_raw / float(a.get("dur", 1.0)))
	return 0.0


func _play_sfx(name: String) -> void:
	if not _is_web:
		return
	var freq := 800
	var dur := 0.08
	match name:
		"place":
			freq = 900
			dur = 0.06
		"capture":
			freq = 400
			dur = 0.12
		"flip":
			freq = 600
			dur = 0.08
		"deal":
			freq = 520
			dur = 0.1
		"swoosh":
			freq = 640
			dur = 0.09
		"win":
			freq = 1200
			dur = 0.3
	JavaScriptBridge.eval(
		"(function(){try{"
		+ "var c=new (window.AudioContext||window.webkitAudioContext)();"
		+ "var o=c.createOscillator();var g=c.createGain();"
		+ "o.connect(g);g.connect(c.destination);"
		+ "o.type='sine';o.frequency.value=%d;"
		+ "g.gain.setValueAtTime(0.15,c.currentTime);"
		+ "g.gain.exponentialRampToValueAtTime(0.001,c.currentTime+%.2f);"
		+ "o.start();o.stop(c.currentTime+%.2f);"
		+ "}catch(e){}})()" % [freq, dur, dur],
		true
	)


func _trigger_junqi_reveal(d: Dictionary) -> void:
	"""End-game: flip all junqi pieces with staggered wave + gold pulse on winner."""
	var cells: Array = d.get("cells", [])
	var winner := str(d.get("winner", ""))
	for idx in cells.size():
		var cell: Variant = cells[idx]
		if typeof(cell) != TYPE_DICTIONARY:
			continue
		var piece: Variant = cell.get("piece", null)
		if typeof(piece) != TYPE_DICTIONARY or piece == null:
			continue
		var ptype := str(piece.get("type", ""))
		if ptype == "":
			continue
		var c: int = idx % JUNQI_COLS
		var r: int = idx / JUNQI_COLS
		var key := "%d,%d" % [c, r]
		# Stagger by Manhattan distance from board center for wave effect
		var dist := absf(float(r) - 5.5) + absf(float(c) - 2.0)
		_piece_anims[key] = {
			"kind": "flip",
			"t": -dist * 0.05,
			"dur": 0.4,
			"winner_pulse": str(piece.get("side", "")) == winner,
		}
	_play_sfx("win")
