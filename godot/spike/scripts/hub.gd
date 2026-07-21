## 3D dungeon-gate Hub: walk, see others, enter doors A/B (docs/18).
## No MuJoCo — Gateway FakeMech presence only. ?menu=1 → text lobby.
extends Node3D

const MOVE_SPEED := 5.5
const TURN_SPEED := 2.2
const CMD_HZ := 20.0
const WORKSHOP_SCENE := "res://demo_workshop.tscn"
const CITY_SCENE := "res://demo_city.tscn"
const LOBBY_SCENE := "res://demo_lobby.tscn"
const AVATAR_SCENE := preload("res://avatar_puppet.tscn")
const _WEB_BLOCK_CODES := {
	"KeyW": true, "KeyA": true, "KeyS": true, "KeyD": true,
	"KeyQ": true, "KeyE": true, "KeyV": true, "KeyF": true, "KeyC": true,
	"ArrowUp": true, "ArrowDown": true, "ArrowLeft": true, "ArrowRight": true,
}

@export var level_id := "demo_hub"
@export var gateway_url := "ws://127.0.0.1:8765"
@export var room_id := "hub"

@onready var ws = $WsClient
@onready var camera_rig = $CameraRig
@onready var tips_label: Label = $HUD/LeftTips
@onready var map_panel: Control = $HUD/MapPanel
@onready var minimap: Control = $HUD/MapPanel/MapVBox/MiniMap
@onready var map_coords: Label = $HUD/MapPanel/MapVBox/MapCoords
@onready var profile_card: Control = $HUD/ProfileCard
@onready var profile_label: Label = $HUD/ProfileCard/VBox/ProfileText
@onready var nick_edit: LineEdit = $HUD/ProfileCard/VBox/NickEdit
@onready var door_workshop: Node3D = $World/DoorWorkshop
@onready var door_city: Node3D = $World/DoorCity
@onready var door_stub_c: Node3D = $World/DoorStubC
@onready var door_stub_d: Node3D = $World/DoorStubD
@onready var door_stub_e: Node3D = $World/DoorStubE
@onready var hub_life: Node3D = $HubLife
@onready var map_title: Label = $HUD/MapPanel/MapVBox/MapTitle

var _session_id := ""
var _cmd_timer := 0.0
var _controlled := false
var _is_web := false
var _web_key_cb
var _web_blur_cb
var _held_codes: Dictionary = {}
var _puppets: Dictionary = {}
var _controlled_entity_id := "avatar_0"
var _joined_room_id := "hub"
var _profile: Dictionary = {}
var _entering_door := false
var _tips_full := ""
var _tips_collapsed := true
var _nearby_prompt := ""
var _lore_body := ""
var _door_context := ""
var _link_banner := "Connecting to gateway…"
var _last_door_key := ""
const DOOR_ENTER_DIST := 2.4
const DOOR_STUB_DIST := 3.2
## Matches hub_dress FLOOR2_Y — thin elevator ride (viewer offset).
const FLOOR2_Y := 8.5

var _hub_floor := 1
var _party_looking := false
var _vendor_accent_i := 0
## H11: Arena gate stub — cycle mode + LFM (no matchmaking).
var _arena_state_i := 0
## H7c: Design / Edge stub status cycles (no editor / no edge link).
var _design_state_i := 0
var _edge_state_i := 0
const ARENA_STATES := [
	{"mode": "1v1", "looking": false},
	{"mode": "1v1", "looking": true},
	{"mode": "party", "looking": false},
	{"mode": "party", "looking": true},
]
const DESIGN_STATES := [
	"sealed",
	"catalog",
	"exhibits",
]
const EDGE_STATES := [
	"offline",
	"pending",
	"camera_stub",
]
const VENDOR_ACCENTS := ["#4aa3ff", "#e8873a", "#6ecf8e", "#d4a24c", "#c46ecf", "#e06c75"]


func _party_posts() -> PackedStringArray:
	"""Stub LFG lines (locale-aware)."""
	return PackedStringArray([
		MWi18n.t("玛雅 · 工坊 IL · 再要一只爪", "Maya · Workshop IL · need one more claw"),
		MWi18n.t("雷克斯 · 街区热身 · 有空位", "Rex · City warm-up · open seat"),
		MWi18n.t("金 · 找展厅同行", "Jin · Looking for Gallery buddy"),
	])


func _ready() -> void:
	"""Boot Hub, divert ?menu=1, or route ?replay= to playable scene (R3)."""
	_is_web = OS.has_feature("web")
	if _wants_text_menu():
		MWTransition.go(LOBBY_SCENE, "Debug menu")
		return
	if _try_route_replay():
		return
	_start_hub_session()


func _start_hub_session() -> void:
	"""Normal Hub presence boot (WS FakeMech + chrome)."""
	MWTransition.notify_arrived()
	_profile = _load_profile()
	_apply_profile_ui()
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	if ws.has_signal("link_phase_changed"):
		ws.link_phase_changed.connect(_on_link_phase)
	if camera_rig != null:
		camera_rig.distance = 22.0
		camera_rig.pitch = -0.62
		camera_rig.max_distance = 90.0
		if camera_rig.has_signal("view_mode_changed"):
			camera_rig.view_mode_changed.connect(_on_camera_view_changed)
	if map_title != null:
		map_title.text = MWi18n.t(
			"母港图 · 东A橙 · 西B蓝 · 北C · 西偏北D · 南E",
			"Hub map · A orange · B blue · C north · D NW · E south"
		)
	_link_banner = MWi18n.t("正在连接网关…", "Connecting to gateway…")
	_lore_body = MWi18n.t(
		"你已抵达数聚球母港。\n东翼本仓关卡 · 北翼卡片通道 · 西翼边缘坞。",
		"You have reached the mothership hangar.\nEast native · North cards · West edge."
	)
	_compose_and_push_tips()
	if _is_web:
		_install_web_keyboard_bridge()
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(false,true);}"
			+ "if(typeof window.MW_LAYOUT_HUB_CHROME==='function'){window.MW_LAYOUT_HUB_CHROME();}",
			true
		)
		# Godot CanvasLayer HUD clips on Web — use DOM chrome instead.
		var hud := get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			hud.visible = false
	ws.connect_to_gateway(_resolve_gateway_url())
	_push_web_profile()
	if tips_label != null and tips_label.visible:
		tips_label.gui_input.connect(_on_tips_gui_input)
		tips_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if nick_edit != null:
		nick_edit.focus_mode = Control.FOCUS_CLICK
		nick_edit.release_focus()
	if not _is_web:
		get_viewport().size_changed.connect(_layout_hub_hud)
		call_deferred("_layout_hub_hud")


func _wants_text_menu() -> bool:
	"""True when URL has ?menu=1 (debug text lobby)."""
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('menu')||''}catch(e){return ''}})()",
			true
		))
		return q == "1" or q.to_lower() == "true"
	return false


func _try_route_replay() -> bool:
	"""R3: main_scene is Hub; fetch header.level_id and load workshop/city (keep ?replay=)."""
	if not _is_web:
		return false
	var rid := str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('replay')||''}catch(e){return ''}})()",
		true
	)).strip_edges()
	if rid == "":
		return false
	_refresh_tips("Loading 3D replay…")
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	if origin == "":
		_refresh_tips("Replay: no origin")
		return false
	var http := HTTPRequest.new()
	http.name = "ReplayRouteHttp"
	add_child(http)
	http.request_completed.connect(_on_replay_route_header.bind(http, rid))
	var err := http.request("%s/api/recordings/%s" % [origin, rid.uri_encode()])
	if err != OK:
		_refresh_tips("Replay route HTTP err %s" % err)
		http.queue_free()
		return false
	return true


func _on_replay_route_header(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
	_rid: String,
) -> void:
	"""Map recording level_id → playable scene; URL query stays for main.gd."""
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_refresh_tips("Replay: header load fail — opening Hub")
		JavaScriptBridge.eval(
			"(function(){try{var u=new URL(location.href);u.searchParams.delete('replay');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);}catch(e){}})()",
			true
		)
		_start_hub_session()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_refresh_tips("Replay: bad header — opening Hub")
		_start_hub_session()
		return
	var level_id := str((parsed as Dictionary).get("level_id", "")).strip_edges()
	var scene := WORKSHOP_SCENE
	var label := "Replay · Workshop"
	var accent := "#e8873a"
	if level_id == "demo_city":
		scene = CITY_SCENE
		label = "Replay · Training"
		accent = "#4aa3ff"
	elif level_id == "demo_hub" or level_id == "":
		# Hub recordings are presence-only; fall back to workshop puppet stage.
		scene = WORKSHOP_SCENE
	MWTransition.go(scene, label, accent)


func _load_profile() -> Dictionary:
	"""Local nickname card — no login (docs/18 H6)."""
	if OS.has_feature("web"):
		var raw := str(JavaScriptBridge.eval(
			"(function(){try{return JSON.stringify(window.MW_GET_PROFILE?window.MW_GET_PROFILE():null)}catch(e){return 'null'}})()",
			true
		))
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	var path := "user://mw_profile.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed2: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed2) == TYPE_DICTIONARY:
				return parsed2
	return {
		"id": _new_local_id(),
		"nickname": "Guest",
		"accent": "#4aa3ff",
	}


func _save_profile() -> void:
	"""Persist profile to localStorage (Web) or user:// (desktop)."""
	var payload := JSON.stringify(_profile)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_PROFILE==='function'){window.MW_SET_PROFILE(%s);}" % payload,
			true
		)
		return
	var f := FileAccess.open("user://mw_profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(payload)


func _new_local_id() -> String:
	"""Generate a local-only profile id."""
	return "local-%s" % str(Time.get_unix_time_from_system()).replace(".", "")


func _apply_profile_ui() -> void:
	"""Refresh top-right pilot card from _profile."""
	var nick := str(_profile.get("nickname", "Guest"))
	var pid := str(_profile.get("id", "?"))
	if nick_edit != null:
		nick_edit.text = nick
	if profile_label != null:
		profile_label.text = MWi18n.t("飞行员卡\n%s\nID %s", "Pilot card\n%s\nID %s") % [
			nick, pid.substr(0, 14)
		]
	_push_web_profile()


func _push_web_profile() -> void:
	"""Sync local profile into DOM hub card."""
	if not _is_web:
		return
	var payload := JSON.stringify({
		"id": str(_profile.get("id", "")),
		"nickname": str(_profile.get("nickname", "Guest")),
		"accent": str(_profile.get("accent", "#4aa3ff")),
	})
	JavaScriptBridge.eval(
		"(function(){var p=%s;if(typeof window.MW_SET_HUB_PROFILE==='function'){window.MW_SET_HUB_PROFILE(p);}})()" % payload,
		true
	)


func _poll_web_nick() -> void:
	"""Apply nickname typed in DOM input (Enter)."""
	if not _is_web:
		return
	var raw := str(JavaScriptBridge.eval(
		"(function(){var n=window.MW_HUB_NICK_PENDING;window.MW_HUB_NICK_PENDING=null;return n||''})()",
		true
	))
	if raw == "":
		return
	_on_nick_submitted(raw)


func _on_nick_submitted(new_text: String) -> void:
	"""Commit nickname from LineEdit."""
	var nick := new_text.strip_edges()
	if nick == "":
		nick = "Guest"
	_profile["nickname"] = nick
	if not _profile.has("id") or str(_profile["id"]) == "":
		_profile["id"] = _new_local_id()
	_save_profile()
	_apply_profile_ui()
	# Re-join so others see the new name (KISS).
	if _session_id != "" and ws != null:
		_send_join()


func _resolve_gateway_url() -> String:
	"""Prefer window.MINEWORLD_GATEWAY on Web."""
	if _is_web:
		var from_js := str(JavaScriptBridge.eval("window.MINEWORLD_GATEWAY || ''", true))
		if from_js != "":
			return from_js
	return gateway_url


func _resolve_room_id() -> String:
	"""Web ?room= overrides; default hub public room."""
	if _is_web:
		var from_q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('room')||''}catch(e){return ''}})()",
			true
		))
		if from_q != "":
			return from_q
	return room_id if room_id != "" else "hub"


func _on_hello(_payload: Dictionary) -> void:
	"""Join hub after hello."""
	_session_id = ws.session_id
	_joined_room_id = _resolve_room_id()
	_send_join()


func _send_join() -> void:
	"""Join demo_hub with local profile extensions."""
	var nick := str(_profile.get("nickname", "Guest"))
	var mw := {
		"profile": {
			"id": str(_profile.get("id", "")),
			"nickname": nick,
			"accent": str(_profile.get("accent", "#4aa3ff")),
		}
	}
	var space_id := _resolve_space_id()
	if space_id != "":
		mw["space_id"] = space_id
		mw["route_kind"] = "pms_space"
	ws.join(level_id, nick, _joined_room_id, {"mw": mw})


func _resolve_space_id() -> String:
	"""E3: optional ?space_id= for session attribution (Hub rarely sets it)."""
	if not _is_web:
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('space_id')||''}catch(e){return ''}})()",
		true
	)).strip_edges()


func _on_scene(payload: Dictionary) -> void:
	"""Assign avatar slot and take control."""
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
	_link_banner = ""
	_lore_body = MWi18n.t(
		"飞行员 %s · 母港\n东翼本仓 A/B · 北翼卡片 C · 西翼边缘 D · 南翼竞技 E",
		"Pilot %s · Hangar Core\nEast A/B · North C · West Edge D · South Arena E"
	) % str(_profile.get("nickname", "Guest"))
	_compose_and_push_tips()


func _ensure_puppets(entities: Array) -> void:
	"""Spawn paper dolls for avatar_* entities."""
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
			node.set("accent", Color(str(_profile.get("accent", "#4aa3ff"))))
			node.set("display_name", str(_profile.get("nickname", "Guest")))
		add_child(node)
		_puppets[eid] = node
		if eid == _controlled_entity_id:
			_apply_hub_floor()


func _own_avatar() -> Node3D:
	"""Return the puppet for our controlled slot."""
	if _puppets.has(_controlled_entity_id):
		return _puppets[_controlled_entity_id]
	return null


func _on_state(tick: int, t_sim: float, payload: Dictionary) -> void:
	"""Drive puppets; hide empty slots; refresh minimap."""
	var occupied: Dictionary = {}
	var actors: Array = []
	for entity in payload.get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if not _puppets.has(eid):
			continue
		var puppet: Node3D = _puppets[eid]
		var ext: Variant = entity.get("extensions", {})
		var is_occ := false
		if typeof(ext) == TYPE_DICTIONARY:
			var mw: Variant = ext.get("mw", {})
			if typeof(mw) == TYPE_DICTIONARY and bool(mw.get("occupied", false)):
				is_occ = true
		puppet.visible = is_occ or eid == _controlled_entity_id
		if puppet.visible and puppet.has_method("push_state"):
			puppet.call("push_state", entity, t_sim)
		if puppet.visible:
			occupied[eid] = puppet
			var mx := 0.0
			var my := 0.0
			if "last_mw_x" in puppet:
				mx = float(puppet.get("last_mw_x"))
				my = float(puppet.get("last_mw_y"))
			actors.append({
				"x": mx,
				"y": my,
				"is_self": eid == _controlled_entity_id,
			})
	if minimap != null and minimap.has_method("set_actors"):
		minimap.call("set_actors", actors)
	if map_coords != null:
		var self_txt := MWi18n.t("独自", "alone")
		for a in actors:
			if bool(a.get("is_self", false)):
				self_txt = MWi18n.t("你 (%.1f, %.1f)", "you (%.1f, %.1f)") % [
					float(a.get("x", 0.0)), float(a.get("y", 0.0))
				]
				break
		map_coords.text = "%s · n=%d" % [self_txt, actors.size()]
	if _is_web:
		_push_web_map(actors)
	if tick % 100 == 0 and not _controlled and _session_id != "":
		ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})


func _push_web_map(actors: Array) -> void:
	"""Draw hub minimap in DOM canvas."""
	var self_txt := MWi18n.t("独自", "alone")
	for a in actors:
		if typeof(a) == TYPE_DICTIONARY and bool(a.get("is_self", false)):
			self_txt = MWi18n.t("你 (%.1f, %.1f)", "you (%.1f, %.1f)") % [
				float(a.get("x", 0.0)), float(a.get("y", 0.0))
			]
			break
	var payload := JSON.stringify({"actors": actors, "self": self_txt})
	JavaScriptBridge.eval(
		"(function(){var p=%s;if(typeof window.MW_SET_HUB_MAP==='function'){window.MW_SET_HUB_MAP(p);}})()" % payload,
		true
	)


func _on_event(payload: Dictionary) -> void:
	"""Track take/release control from Gateway."""
	var et := str(payload.get("event_type", ""))
	match et:
		"player_take_control":
			_controlled = true
		"player_release_control":
			_controlled = false


func _on_gateway_error(payload: Dictionary) -> void:
	"""Surface join errors in tips."""
	_link_banner = "Gateway error: %s — %s" % [payload.get("code", "?"), payload.get("message", "")]
	_compose_and_push_tips()


func _on_link_state(connected: bool) -> void:
	"""Legacy connected bool — phase handler owns copy."""
	if connected:
		_link_banner = ""
	elif _link_banner == "" or _link_banner.begins_with("Connected"):
		_link_banner = "Disconnected · reconnecting…"
	_compose_and_push_tips()


func _on_link_phase(phase: String) -> void:
	"""UX3: explicit connect / reconnect / drop banners (no silent hang)."""
	match phase:
		"connecting":
			_link_banner = "Connecting to gateway…"
		"reconnecting":
			_link_banner = "Disconnected · reconnecting…"
		"connected":
			_link_banner = "Connected · joining Hub room…"
		"disconnected":
			if _entering_door:
				_link_banner = ""
			else:
				_link_banner = "Offline — start gateway: echo_server.py"
		_:
			_link_banner = "Link: %s" % phase
	_compose_and_push_tips()


func _layout_hub_hud() -> void:
	"""Keep map/profile fully inside the visible viewport (Web often clips corners)."""
	var vr := get_viewport().get_visible_rect().size
	if vr.x < 32.0 or vr.y < 32.0:
		return
	var m := 16.0
	if map_panel != null:
		var map_w := minf(260.0, vr.x * 0.32)
		var map_h := minf(200.0, vr.y * 0.34)
		map_panel.anchor_left = 1.0
		map_panel.anchor_top = 1.0
		map_panel.anchor_right = 1.0
		map_panel.anchor_bottom = 1.0
		map_panel.offset_left = -(map_w + m)
		map_panel.offset_top = -(map_h + m)
		map_panel.offset_right = -m
		map_panel.offset_bottom = -m
		if minimap != null:
			minimap.custom_minimum_size = Vector2(maxf(120.0, map_w - 28.0), maxf(90.0, map_h - 52.0))
			minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if profile_card != null:
		var pw := minf(240.0, vr.x * 0.3)
		profile_card.anchor_left = 1.0
		profile_card.anchor_top = 0.0
		profile_card.anchor_right = 1.0
		profile_card.anchor_bottom = 0.0
		profile_card.offset_left = -(pw + m)
		profile_card.offset_top = m
		profile_card.offset_right = -m
		profile_card.offset_bottom = m + 110.0
	if tips_label != null and tips_label.visible:
		tips_label.clip_contents = true
		var tw := minf(300.0, vr.x * 0.36)
		var th := minf(200.0, vr.y * 0.36)
		tips_label.anchor_left = 0.0
		tips_label.anchor_top = 0.0
		tips_label.anchor_right = 0.0
		tips_label.anchor_bottom = 0.0
		tips_label.position = Vector2(m, m)
		tips_label.size = Vector2(tw, th)


func _push_web_tips(full_text: String) -> void:
	"""Push hub tips into DOM #mw-hud (avoids Godot Control clip on Web)."""
	var payload := JSON.stringify(full_text)
	var collapsed := JSON.stringify(MWi18n.t("母港 · 提示 ›（点击）", "Hangar · tips › (click)"))
	JavaScriptBridge.eval(
		(
			"(function(){var t=%s;var c=%s;"
			+ "if(typeof window.MW_SET_HUD==='function'){window.MW_SET_HUD(t,c);}"
			+ "})()"
		) % [payload, collapsed],
		true
	)


func _compose_and_push_tips() -> void:
	"""Build left lore panel from link banner + lore + door context + controls."""
	var chunks: PackedStringArray = []
	chunks.append(MWi18n.t("母港", "Hangar Core"))
	if _link_banner != "":
		chunks.append(_link_banner)
	chunks.append(_lore_body)
	if _door_context != "":
		chunks.append(_door_context)
	chunks.append(
		MWi18n.t(
			"WSQE 移动 | A/D 转向 | F 交互\n"
			+ "右键视角 · 滚轮缩放 · V 切换相机 · C 回正\n"
			+ "A 工坊 · B 训练 · C 卡片 · D 边缘 · E 竞技\n"
			+ "（点击折叠）",
			"WSQE move | A/D turn | F interact\n"
			+ "RMB look · wheel zoom · V camera · C recenter\n"
			+ "A Workshop · B Training · C Cards · D Edge · E Arena\n"
			+ "(click to collapse)"
		)
	)
	_tips_full = "\n\n".join(chunks)
	if _is_web:
		_push_web_tips(_tips_full)
		return
	_apply_tips_view()


func _refresh_tips(msg: String) -> void:
	"""Compat: set lore body and rebuild panel."""
	_lore_body = msg
	_compose_and_push_tips()


func _apply_tips_view() -> void:
	"""Show collapsed one-liner or full tip block."""
	if tips_label == null:
		return
	if _tips_collapsed:
		var head := _link_banner if _link_banner != "" else MWi18n.t("母港 · 提示 ›（点击）", "Hangar · tips › (click)")
		tips_label.text = head
	else:
		tips_label.text = _tips_full


func _on_tips_gui_input(event: InputEvent) -> void:
	"""Toggle tip panel like shell HUD collapse."""
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_tips_collapsed = not _tips_collapsed
			_apply_tips_view()
			tips_label.accept_event()


func _process(delta: float) -> void:
	"""Match play-level controls: WSQE/AD drive; arrows pan camera (Web)."""
	if _entering_door:
		return
	_check_doors()
	_update_door_context()
	_update_interact_prompt()
	if _is_web:
		_sync_mw_keys()
	if _is_web and camera_rig != null and camera_rig.has_method("pan_axes"):
		var pan_r := 0.0
		var pan_f := 0.0
		if _web_key("ArrowRight"):
			pan_r += 1.0
		if _web_key("ArrowLeft"):
			pan_r -= 1.0
		if _web_key("ArrowUp"):
			pan_f += 1.0
		if _web_key("ArrowDown"):
			pan_f -= 1.0
		camera_rig.pan_axes(pan_r, pan_f, delta)
	_sync_first_person_mesh()
	if _is_web:
		_poll_web_nick()
	_cmd_timer += delta
	if _cmd_timer < 1.0 / CMD_HZ:
		return
	_cmd_timer = 0.0
	_send_velocity_cmd()


func _sync_first_person_mesh() -> void:
	"""Hide own chassis in FP so the camera is not inside the hull."""
	var own := _own_avatar()
	if own == null:
		return
	var bot := own.get_node_or_null("WheelBot") as Node3D
	if bot == null:
		return
	var fp := false
	if camera_rig != null and "view_mode" in camera_rig:
		fp = int(camera_rig.view_mode) == 1  ## ViewMode.FIRST
	bot.visible = not fp
	var tag := own.get_node_or_null("NameTag") as Node3D
	if tag != null:
		tag.visible = not fp


func _sync_mw_keys() -> void:
	"""Merge shell mw_key_bridge window._mw_keys into _held_codes."""
	var raw := str(JavaScriptBridge.eval(
		"(function(){try{return JSON.stringify(window._mw_keys||{})}catch(e){return '{}'}}())",
		true
	))
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for k in (parsed as Dictionary).keys():
		_held_codes[str(k)] = bool((parsed as Dictionary)[k])


func _web_key(code: String) -> bool:
	"""Web KeyboardEvent.code held (hub listeners + shell bridge)."""
	return bool(_held_codes.get(code, false))


func _send_velocity_cmd() -> void:
	"""Same mapping as main.gd: W/S forward, Q/E strafe, A/D yaw."""
	var vx := 0.0
	var vy := 0.0
	var yaw_rate := 0.0
	if _is_web:
		if _web_key("KeyW"):
			vx += MOVE_SPEED
		if _web_key("KeyS"):
			vx -= MOVE_SPEED
		if _web_key("KeyQ"):
			vy += MOVE_SPEED
		if _web_key("KeyE"):
			vy -= MOVE_SPEED
		if _web_key("KeyA"):
			yaw_rate += TURN_SPEED
		if _web_key("KeyD"):
			yaw_rate -= TURN_SPEED
	else:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_W):
			vx += MOVE_SPEED
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_S):
			vx -= MOVE_SPEED
		if Input.is_physical_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_Q):
			vy += MOVE_SPEED
		if Input.is_physical_key_pressed(KEY_E) or Input.is_key_pressed(KEY_E):
			vy -= MOVE_SPEED
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_A):
			yaw_rate += TURN_SPEED
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_D):
			yaw_rate -= TURN_SPEED
		if vx == 0.0 and vy == 0.0 and yaw_rate == 0.0:
			vx = Input.get_axis("move_back", "move_forward") * MOVE_SPEED
			vy = Input.get_axis("strafe_left", "strafe_right") * -MOVE_SPEED
			yaw_rate = Input.get_axis("turn_cw", "turn_ccw") * TURN_SPEED
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


func _check_doors() -> void:
	"""Enter a route when own avatar is close to an open door (A/B only)."""
	if _hub_floor != 1:
		return
	var own := _own_avatar()
	if own == null or not own.visible:
		return
	if door_workshop != null and own.global_position.distance_to(door_workshop.global_position) < DOOR_ENTER_DIST:
		_enter_level(WORKSHOP_SCENE)
		return
	if door_city != null and own.global_position.distance_to(door_city.global_position) < DOOR_ENTER_DIST:
		_enter_level(CITY_SCENE)


func _update_door_context() -> void:
	"""H7: left-lore line for nearest door (stubs never enter)."""
	var own := _own_avatar()
	if own == null:
		return
	var best_key := ""
	var best_dist := DOOR_STUB_DIST
	var best_msg := ""
	var candidates: Array = [
		[door_workshop, "a", MWi18n.t(
			"门 A · 仿真工坊 — 进入本仓精细遥操 / IL。",
			"Door A · Workshop — native teleop / IL."
		)],
		[door_city, "b", MWi18n.t(
			"门 B · 机甲训练场 — 进入本仓城市场景。",
			"Door B · Training Yard — native city drive."
		)],
		[door_stub_c, "c", MWi18n.t(
			"门 C · 设计室 — 卡片通道。走近按 F 看状态。",
			"Door C · Design Lab — F for stub status."
		)],
		[door_stub_d, "d", MWi18n.t(
			"门 D · 边缘坞 — 真机/边缘入口。走近按 F 看链路。",
			"Door D · Edge Dock — F for link stub."
		)],
		[door_stub_e, "e", MWi18n.t(
			"门 E · 竞技场 — 走近按 F 切换 1v1/组队。",
			"Door E · Arena — F for match stub."
		)],
	]
	for row in candidates:
		var node: Node3D = row[0]
		if node == null:
			continue
		var d := own.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best_key = str(row[1])
			best_msg = str(row[2])
	if best_key == _last_door_key:
		return
	_last_door_key = best_key
	_door_context = best_msg
	_compose_and_push_tips()


func _update_interact_prompt() -> void:
	"""Show nearby F-prompt in collapsed tips line when close to a station/NPC."""
	var own := _own_avatar()
	if own == null or hub_life == null or not hub_life.has_method("nearest_interact"):
		return
	var hit: Dictionary = hub_life.call("nearest_interact", own.global_position)
	var prompt := str(hit.get("prompt", ""))
	if prompt == _nearby_prompt:
		return
	_nearby_prompt = prompt
	if prompt != "" and _is_web:
		# Soft nudge into DOM tips without wiping the full guide permanently.
		_push_web_tips(MWi18n.t("%s\n\n（走近 · 按 F）", "%s\n\n(walk closer · press F)") % prompt)


func _try_interact() -> void:
	"""F: talk / elevator / E4 exhibit / H9 party+vendor / H11 arena."""
	var own := _own_avatar()
	if own == null or hub_life == null or not hub_life.has_method("nearest_interact"):
		return
	var hit: Dictionary = hub_life.call("nearest_interact", own.global_position)
	if hit.is_empty():
		_refresh_tips(MWi18n.t("附近无可交互物 — 走近发光台或 NPC。", "Nothing to use here — approach a kiosk or NPC."))
		return
	var sid := str(hit.get("id", ""))
	if sid == "elevator":
		_toggle_elevator()
		return
	if sid == "board_party":
		_use_party_board()
		return
	if sid == "vendor":
		_use_vendor()
		return
	if sid == "arena_gate":
		_use_arena_gate()
		return
	if sid == "design_lab":
		_use_design_lab()
		return
	if sid == "edge_dock":
		_use_edge_dock()
		return
	var url := str(hit.get("url", "")).strip_edges()
	if url != "":
		var space_id := str(hit.get("space_id", "")).strip_edges()
		_open_exhibit_url(url, str(hit.get("title", hit.get("id", "Space"))), space_id)
		return
	_refresh_tips(str(hit.get("line", "...")))


func _use_arena_gate() -> void:
	"""H11: cycle 1v1/party × Looking-for-match (authority later)."""
	_arena_state_i = (_arena_state_i + 1) % ARENA_STATES.size()
	var st: Dictionary = ARENA_STATES[_arena_state_i]
	var mode := str(st.get("mode", "1v1"))
	var lfm := MWi18n.t("排队中 ✓", "Looking ✓") if bool(st.get("looking", false)) else MWi18n.t("未排队", "not queued")
	_refresh_tips(
		MWi18n.t(
			"竞技场门\n模式: %s · %s\n\n1v1 / 组队占位；匹配与权威后置。\n再按 F 循环。",
			"Arena Gate\nMode: %s · %s\n\n1v1 / party stub; matchmaking later.\nF again to cycle."
		) % [mode, lfm]
	)


func _use_design_lab() -> void:
	"""H7c: cycle Design Lab stub panes (no editor / no join)."""
	_design_state_i = (_design_state_i + 1) % DESIGN_STATES.size()
	var st := str(DESIGN_STATES[_design_state_i])
	var body := ""
	match st:
		"catalog":
			body = MWi18n.t(
				"目录预览\n未来：契约/卡片列表。现用北翼展柜开 Space。",
				"Catalog preview\nFuture: contract list. Use north exhibits for Spaces."
			)
		"exhibits":
			body = MWi18n.t(
				"展柜通道\n卡片通道：F 打开展品；本门不进仿真。",
				"Exhibit route\nType B: F opens Space URL; no MuJoCo here."
			)
		_:
			body = MWi18n.t(
				"舱门封闭\n设计室编辑器后置。",
				"Sealed\nDesign editor later."
			)
	_refresh_tips(
		MWi18n.t("设计室\n状态: %s\n\n%s\n\n再按 F 切换。", "Design Lab\nStatus: %s\n\n%s\n\nF again.")
		% [st, body]
	)


func _use_edge_dock() -> void:
	"""H7c: cycle Edge Dock link stub (no real robot)."""
	_edge_state_i = (_edge_state_i + 1) % EDGE_STATES.size()
	var st := str(EDGE_STATES[_edge_state_i])
	var body := ""
	match st:
		"pending":
			body = MWi18n.t(
				"边缘会话排队\n鉴权/编排走外部系统；Hub 只做入口。",
				"Edge session pending\nAuth/orchestration external; Hub is entry only."
			)
		"camera_stub":
			body = MWi18n.t(
				"摄像头占位\n无直播流；真机透传近期不做。",
				"Camera feed stub\nNo live stream; real robot passthrough later."
			)
		_:
			body = MWi18n.t(
				"链路离线\n边缘坞不接本仓仿真。",
				"Link offline\nEdge dock has no Hub MuJoCo."
			)
	_refresh_tips(
		MWi18n.t("边缘任务坞\n链路: %s\n\n%s\n\n再按 F 切换。", "Edge Dock\nLink: %s\n\n%s\n\nF again.")
		% [st, body]
	)


func _use_party_board() -> void:
	"""H9: toggle Looking-for-crew + show stub LFG posts."""
	_party_looking = not _party_looking
	var you := (
		MWi18n.t("你 · 正在招募 ✓", "YOU · Looking for crew ✓")
		if _party_looking
		else MWi18n.t("你 · 未发布", "YOU · not posting")
	)
	var lines: PackedStringArray = [MWi18n.t("组队板", "Party board"), you, ""]
	for p in _party_posts():
		lines.append("· %s" % str(p))
	lines.append("")
	lines.append(MWi18n.t("再按 F 切换招募状态。（匹配后置）", "F again to toggle. Matchmaking later."))
	_refresh_tips("\n".join(lines))


func _use_vendor() -> void:
	"""H9: cycle profile accent and apply to own avatar."""
	_vendor_accent_i = (_vendor_accent_i + 1) % VENDOR_ACCENTS.size()
	var hex := str(VENDOR_ACCENTS[_vendor_accent_i])
	_profile["accent"] = hex
	_save_profile()
	_apply_profile_ui()
	var own := _own_avatar()
	if own != null and own.has_method("set_display"):
		own.call("set_display", str(_profile.get("nickname", "Guest")), hex)
	elif own != null and "accent" in own:
		own.set("accent", Color(hex))
	_refresh_tips(
		MWi18n.t(
			"商贩 · 配色 %d/%d\n%s\n已写入档案。再按 F 换色。",
			"Vendor · accent %d/%d\n%s\nSaved. F for next color."
		) % [_vendor_accent_i + 1, VENDOR_ACCENTS.size(), hex]
	)


func _open_exhibit_url(url: String, title: String, space_id: String = "") -> void:
	"""E4: open Space card; stamp hangar ?space_id= for E3 return play."""
	var resolved := url
	if resolved.begins_with("/") and _is_web:
		var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
		if origin != "":
			resolved = origin + resolved
	if _is_web:
		var payload := JSON.stringify({"url": resolved, "space_id": space_id})
		JavaScriptBridge.eval(
			"(function(){try{var p=%s;window.open(p.url,'_blank','noopener,noreferrer');"
			+ "if(p.space_id){var u=new URL(location.href);u.searchParams.set('space_id',p.space_id);"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);}}catch(e){}})()" % payload,
			true
		)
		_refresh_tips(
			MWi18n.t(
				"已打开「%s」· 母港已写入 space_id=%s\n占位：带回 space_id → 门 A 做归因游玩。",
				"Opened «%s» · hangar stamped space_id=%s\nStub: Hangar with space_id → door A for attributed play."
			) % [title, space_id if space_id != "" else "—"]
		)
	else:
		var err := OS.shell_open(resolved)
		if err != OK:
			_refresh_tips(
				MWi18n.t("无法打开展柜链接（err %s）：%s", "Could not open exhibit URL (err %s): %s")
				% [err, resolved]
			)
		else:
			_refresh_tips(
				MWi18n.t(
					"已在浏览器打开「%s」。\n回到本窗口继续母港。",
					"Opened «%s» in your browser.\nReturn to this window for the hangar."
				) % title
			)


func _toggle_elevator() -> void:
	"""H8 thin ride: snap viewer to L2 mezzanine or back to hangar floor."""
	_hub_floor = 2 if _hub_floor == 1 else 1
	_apply_hub_floor()
	if _hub_floor == 2:
		_refresh_tips(MWi18n.t(
			"L2 观景廊 — 可沿廊走动。电梯旁按 F 下楼。",
			"L2 Lounge — F at elevator to return."
		))
		_door_context = MWi18n.t("楼层: L2", "Floor: L2")
	else:
		_refresh_tips(MWi18n.t(
			"母港一层 — 电梯旁按 F 上 L2。",
			"Hangar floor — F at elevator for L2."
		))
		_door_context = MWi18n.t("楼层: L1", "Floor: L1")
	_compose_and_push_tips()


func _apply_hub_floor() -> void:
	"""Raise own avatar onto L2 deck (FakeMech stays planar; visual Y only)."""
	var own := _own_avatar()
	if own == null:
		return
	if "height_offset" in own:
		own.set("height_offset", FLOOR2_Y if _hub_floor == 2 else 0.0)
	# Nudge buffers so the jump is immediate (don't wait for next state).
	if _hub_floor == 2:
		own.global_position.y = FLOOR2_Y
	else:
		own.global_position.y = 0.0


func _on_camera_view_changed(label: String) -> void:
	"""HUD toast when CameraRig cycles view (shared SSOT)."""
	_door_context = "Camera: %s (press V to cycle)" % label
	_compose_and_push_tips()


func _unhandled_input(event: InputEvent) -> void:
	"""Desktop: Esc stays in hub; F interact. Camera C/V live on CameraRig."""
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_F or ek.physical_keycode == KEY_F:
				_try_interact()
				get_viewport().set_input_as_handled()
				return


func _install_web_keyboard_bridge() -> void:
	"""Same document key bridge as main.gd (single-thread Web)."""
	_web_key_cb = JavaScriptBridge.create_callback(_on_dom_key_event)
	_web_blur_cb = JavaScriptBridge.create_callback(_on_dom_blur)
	var document = JavaScriptBridge.get_interface("document")
	var window_obj = JavaScriptBridge.get_interface("window")
	if document == null or window_obj == null:
		push_warning("[MW] hub: JavaScriptBridge document/window missing")
		return
	document.addEventListener("keydown", _web_key_cb)
	document.addEventListener("keyup", _web_key_cb)
	window_obj.addEventListener("blur", _web_blur_cb)
	print("[MW] hub key bridge: document listeners registered")


func _on_dom_key_event(args: Array) -> void:
	"""DOM keydown/keyup → _held_codes; arrows reserved for camera pan."""
	if args.is_empty():
		return
	var event = args[0]
	var code := str(event.code)
	var down := str(event.type) == "keydown"
	_held_codes[code] = down
	# Release nickname LineEdit focus so WSQE reach the game again.
	if down and nick_edit != null and nick_edit.has_focus():
		if code in ["KeyW", "KeyS", "KeyQ", "KeyE", "KeyA", "KeyD"]:
			nick_edit.release_focus()
	if down and camera_rig != null and camera_rig.has_method("handle_code"):
		camera_rig.handle_code(code, true)
	if down and code == "KeyF":
		_try_interact()
	if _WEB_BLOCK_CODES.has(code):
		event.preventDefault()


func _on_dom_blur(_args: Array) -> void:
	"""Clear held keys when the browser tab loses focus."""
	_held_codes.clear()


func _enter_level(scene_path: String) -> void:
	"""Leave hub room and load a MuJoCo play level."""
	if _entering_door:
		return
	_entering_door = true
	var label := MWi18n.t("进入中…", "Entering…")
	var accent := ""
	if scene_path.find("workshop") >= 0:
		label = MWi18n.t("仿真工坊", "Workshop")
		accent = "#e8873a"
	elif scene_path.find("city") >= 0:
		label = MWi18n.t("机甲训练场", "Training")
		accent = "#4aa3ff"
	_refresh_tips(MWi18n.t("进入航线…", "Entering route…"))
	ws.close_link()
	MWTransition.go(scene_path, label, accent)
