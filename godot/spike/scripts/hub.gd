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
	"KeyQ": true, "KeyE": true, "KeyV": true, "KeyF": true,
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
@onready var hub_life: Node3D = $HubLife

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
const DOOR_ENTER_DIST := 2.4


func _ready() -> void:
	"""Boot Hub or divert to text menu when ?menu=1."""
	_is_web = OS.has_feature("web")
	if _wants_text_menu():
		MWTransition.go(LOBBY_SCENE, "Debug menu")
		return
	MWTransition.notify_arrived()
	_profile = _load_profile()
	_apply_profile_ui()
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	if camera_rig != null:
		camera_rig.distance = 18.0
		camera_rig.pitch = -0.55
		camera_rig.max_distance = 48.0
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
	_refresh_tips("Walk the hall. Approach a glowing door to enter a route.")
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
	if not _is_web and not OS.has_feature("web"):
		# Desktop: honor --menu=1 style via env is overkill; only Web query.
		pass
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('menu')||''}catch(e){return ''}})()",
			true
		))
		return q == "1" or q.to_lower() == "true"
	return false


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
	"""Refresh top-right card from _profile."""
	var nick := str(_profile.get("nickname", "Guest"))
	if nick_edit != null:
		nick_edit.text = nick
	if profile_label != null:
		profile_label.text = "ID %s\n%s" % [
			str(_profile.get("id", "?")).substr(0, 12),
			nick,
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
	ws.join(level_id, nick, _joined_room_id, {
		"mw": {
			"profile": {
				"id": str(_profile.get("id", "")),
				"nickname": nick,
				"accent": str(_profile.get("accent", "#4aa3ff")),
			}
		}
	})


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
	_refresh_tips("You are %s · doors: Workshop (E) · Training Yard (W)" % str(_profile.get("nickname", "Guest")))


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
		var self_txt := "alone"
		for a in actors:
			if bool(a.get("is_self", false)):
				self_txt = "you (%.1f, %.1f)" % [float(a.get("x", 0.0)), float(a.get("y", 0.0))]
				break
		map_coords.text = "%s · n=%d" % [self_txt, actors.size()]
	if _is_web:
		_push_web_map(actors)
	if tick % 100 == 0 and not _controlled and _session_id != "":
		ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})


func _push_web_map(actors: Array) -> void:
	"""Draw hub minimap in DOM canvas."""
	var self_txt := "alone"
	for a in actors:
		if typeof(a) == TYPE_DICTIONARY and bool(a.get("is_self", false)):
			self_txt = "you (%.1f, %.1f)" % [float(a.get("x", 0.0)), float(a.get("y", 0.0))]
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
	_refresh_tips("Gateway: %s — %s" % [payload.get("code", "?"), payload.get("message", "")])


func _on_link_state(connected: bool) -> void:
	"""Show link drops."""
	if not connected:
		_refresh_tips("Disconnected from gateway. Is echo_server running?")


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
		profile_card.offset_bottom = m + 92.0
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
	var collapsed := JSON.stringify("Dungeon Gate - tips > (click)")
	JavaScriptBridge.eval(
		(
			"(function(){var t=%s;var c=%s;"
			+ "if(typeof window.MW_SET_HUD==='function'){window.MW_SET_HUD(t,c);}"
			+ "})()"
		) % [payload, collapsed],
		true
	)


func _refresh_tips(msg: String) -> void:
	"""Update left lore / tip panel; Web uses DOM, desktop uses Godot Label."""
	_tips_full = "Dungeon Gate\n\n%s\n\nWSQE move | A/D turn | F talk / use\nRMB/MMB look + wheel zoom | arrows pan (orbit only)\nC recenter | V cycle orbit / first-person / chase\nOrange door Workshop | Blue door City\n\n(click to collapse)" % msg
	if _is_web:
		_push_web_tips(_tips_full)
		return
	_apply_tips_view()


func _apply_tips_view() -> void:
	"""Show collapsed one-liner or full tip block."""
	if tips_label == null:
		return
	if _tips_collapsed:
		tips_label.text = "Dungeon Gate - tips > (click)"
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
	"""Enter a route when own avatar is close to a glowing door."""
	var own := _own_avatar()
	if own == null or not own.visible:
		return
	if door_workshop != null and own.global_position.distance_to(door_workshop.global_position) < DOOR_ENTER_DIST:
		_enter_level(WORKSHOP_SCENE)
		return
	if door_city != null and own.global_position.distance_to(door_city.global_position) < DOOR_ENTER_DIST:
		_enter_level(CITY_SCENE)


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
		_push_web_tips("%s\n\n(walk closer · press F)" % prompt)


func _try_interact() -> void:
	"""F: talk to NPC / use nearby station."""
	var own := _own_avatar()
	if own == null or hub_life == null or not hub_life.has_method("nearest_interact"):
		return
	var hit: Dictionary = hub_life.call("nearest_interact", own.global_position)
	if hit.is_empty():
		_refresh_tips("Nothing to use here — approach a glowing kiosk or NPC.")
		return
	_refresh_tips(str(hit.get("line", "...")))


func _cycle_camera_view() -> void:
	"""Orbit / first-person / chase-behind."""
	if camera_rig == null or not camera_rig.has_method("cycle_view_mode"):
		return
	var label := str(camera_rig.cycle_view_mode())
	_refresh_tips("Camera: %s (press V to cycle)" % label)


func _unhandled_input(event: InputEvent) -> void:
	"""Desktop: Esc stays in hub; C recenters; V cycles camera."""
	if event is InputEventKey:
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo:
			if ek.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_V or ek.physical_keycode == KEY_V:
				_cycle_camera_view()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_F or ek.physical_keycode == KEY_F:
				_try_interact()
				get_viewport().set_input_as_handled()
				return
			if ek.keycode == KEY_C or ek.physical_keycode == KEY_C:
				if camera_rig != null and camera_rig.has_method("reset_look_offset"):
					camera_rig.reset_look_offset()
				get_viewport().set_input_as_handled()


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
	if down and code == "KeyC" and camera_rig != null and camera_rig.has_method("reset_look_offset"):
		camera_rig.reset_look_offset()
	if down and code == "KeyV":
		_cycle_camera_view()
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
	var label := "Entering…"
	if scene_path.find("workshop") >= 0:
		label = "Workshop"
	elif scene_path.find("city") >= 0:
		label = "Training"
	_refresh_tips("Entering route…")
	ws.close_link()
	MWTransition.go(scene_path, label)
