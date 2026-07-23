## MineWorld Godot spike — session shell.
## Connects to the Python gateway, joins a level, takes/releases control,
## drives capsule puppets with WASD/QE (authority stays server-side).
##
## Multiplayer (W3): join with room_id (export or window.MINEWORLD_ROOM);
## empty = private room. Scene assigns controlled_entity_id; extra mechs
## are duplicated from MechPlayer.
##
## Web keyboard: single-thread export + document listeners via JavaScriptBridge
## (eval/window._mw_keys readback is unreliable; InputMap often fails in browser).
extends Node3D

const MOVE_SPEED := 1.0
const TURN_SPEED := 1.0
## demo_race: throttle/steer in [-1,1] (Ackermann: vx→RWD, yaw_rate→front steer).
const MOVE_SPEED_RACE := 1.0
const TURN_SPEED_RACE := 1.0
const STRAFE_SPEED_RACE := 0.35
## R2 analog drive (keyboard time-for-axis; gamepad native axis).
const CMD_HZ := 20.0
const _WEB_BLOCK_CODES := {
	"KeyW": true, "KeyA": true, "KeyS": true, "KeyD": true,
	"KeyQ": true, "KeyE": true, "KeyT": true, "KeyR": true,
	"KeyV": true, "KeyC": true, "KeyX": true,
	"ArrowUp": true, "ArrowDown": true, "ArrowLeft": true, "ArrowRight": true,
	"Space": true,
}

@export var level_id := "demo_workshop"
@export var gateway_url := "ws://127.0.0.1:8765"
## Empty = private room (gateway uses session_id). Set "demo" for shared room.
@export var room_id := ""

@onready var ws = $WsClient
@onready var mech = $MechPlayer
@onready var camera_rig = $CameraRig
@onready var hud_label: Label = _resolve_hud_label()

var _session_id := ""
var _hello: Dictionary = {}
var _drive := MWDriveInput.new()
var _lap_splits: Array = []
var _lap_start_t := -1.0
var _last_state_t := 0.0
var _ghost: MWGhost = null
var _race_fx: MWRaceFX = null
var _race_cum: PackedFloat32Array = PackedFloat32Array()  # centerline cumulative dist (m)
var _race_pts: PackedVector2Array = PackedVector2Array()  # centerline MW xy
var _race_track_len := 0.0
var _duel_hint_idx: Dictionary = {}  # eid -> last nearest centerline idx
var _last_error := ""
var _cmd_timer := 0.0
var _last_log_tick := -1
var _controlled := false
var _mission_done := false
var _status_line := ""
var _is_web := false
## Must keep refs or JS callbacks are garbage-collected.
var _web_key_cb
var _web_blur_cb
## KeyboardEvent.code → pressed (web)
var _held_codes: Dictionary = {}
var _held: Dictionary = {}
var _web_key_logged := false
## entity_id → MWMechPuppet
var _puppets: Dictionary = {}
var _controlled_entity_id := "mech_player"
var _joined_room_id := ""
var _hud: MWHud = null
## D8: offline frame replay (?replay=<session_id>); skips gateway.
var _replay: MWReplay = null
## V1c: held arm/gripper setpoints (desktop sliders / web MW_JOINT_TARGETS).
var _joint_targets: Dictionary = {
	"arm_yaw": 0.0,
	"arm_shoulder": 0.0,
	"arm_elbow": 0.0,
	"gripper": 0.0,
}
var _joint_panel: CanvasLayer
## Platform / local profile for score wiring (align hub.gd).
var _profile: Dictionary = {}
const _JOINT_SPECS := [
	{"id": "arm_yaw", "label": "yaw", "min": -2.8, "max": 2.8, "step": 0.02},
	{"id": "arm_shoulder", "label": "shoulder", "min": -1.4, "max": 1.6, "step": 0.02},
	{"id": "arm_elbow", "label": "elbow", "min": -2.4, "max": 0.2, "step": 0.02},
	{"id": "gripper", "label": "gripper", "min": 0.0, "max": 0.05, "step": 0.001},
]


func _ready() -> void:
	_is_web = OS.has_feature("web")
	_profile = _load_profile()
	var q_level := _resolve_level_override()
	if q_level != "":
		level_id = q_level
	MWTransition.notify_arrived()
	ws.hello_received.connect(_on_hello)
	ws.scene_received.connect(_on_scene)
	ws.state_received.connect(_on_state)
	ws.event_received.connect(_on_event)
	ws.gateway_error.connect(_on_gateway_error)
	ws.link_state_changed.connect(_on_link_state)
	if ws.has_signal("link_phase_changed"):
		ws.link_phase_changed.connect(_on_link_phase)
	mech.entity_id = "mech_player"
	_puppets["mech_player"] = mech
	var mech_b := get_node_or_null("MechPlayerB")
	if mech_b != null:
		_puppets["mech_player_b"] = mech_b
	_hud = MWHud.new()
	_hud.name = "HudFx"
	add_child(_hud)
	_hud.ensure_banner()
	_ensure_hud_layout()
	_ensure_joint_sliders()
	call_deferred("_ensure_hud_layout")
	if not get_viewport().size_changed.is_connected(_ensure_hud_layout):
		get_viewport().size_changed.connect(_ensure_hud_layout)
	if _is_web:
		_install_web_keyboard_bridge()
		_sync_web_city_seed_ui()
		# Hide arm UI before/with play chrome (city has no arm joints).
		_sync_web_joints_ui()
		var play_js := "true"
		var no_joints := "true" if _is_chassis_play() else "false"
		JavaScriptBridge.eval(
			(
				"if(typeof window.MW_SET_SHELL_UI==='function'){"
				+ "window.MW_SET_SHELL_UI(%s,false,%s);}"
			) % [play_js, no_joints],
			true
		)
		_sync_web_joints_ui()
	if camera_rig != null and camera_rig.has_signal("view_mode_changed"):
		camera_rig.view_mode_changed.connect(_on_camera_view_changed)
	if level_id == "demo_race":
		_load_race_centerline()
	var replay_id := _resolve_replay_id()
	if replay_id != "":
		_replay = MWReplay.new()
		_replay.name = "Replay"
		_replay.puppets = _puppets
		_replay.ensure_puppets_cb = _ensure_puppets
		_replay.own_mech_getter = _own_mech
		_replay.camera_rig = camera_rig
		_replay.hud_refresh = _update_hud
		_replay.frame_applied.connect(_on_replay_frame)
		add_child(_replay)
		_replay.start(replay_id)
	elif level_id == "demo_race":
		# Ghost is viewer-only async fetch — must NOT return early or race
		# never connects WS (throttle/cmds never sent; car sits at spawn).
		_ghost = MWGhost.new()
		_ghost.name = "Ghost"
		_ghost.own_mech_getter = _own_mech
		_ghost.loaded.connect(_on_ghost_loaded)
		add_child(_ghost)
		_ghost.fetch_best()
	ws.connect_to_gateway(_resolve_gateway_url())
	_update_hud()


func _sync_web_city_seed_ui() -> void:
	"""Show city seed/Regen chrome only for demo_city."""
	if not _is_web:
		return
	var show := "true" if level_id == "demo_city" else "false"
	JavaScriptBridge.eval(
		"(function(show){var e=document.getElementById('mw-seed');if(!e){return;}"
		+ "e.classList.toggle('mw-show',!!show);})(%s);" % show,
		true
	)


func _sync_web_joints_ui() -> void:
	"""Hide arm/gripper DOM on city (DiffBot has no arm joints)."""
	if not _is_web:
		return
	var show := "false" if _is_chassis_play() else "true"
	JavaScriptBridge.eval(
		"(function(show){document.body.classList.toggle('mw-no-joints',!show);"
		+ "var e=document.getElementById('mw-joints');if(e){e.style.display=show?'':'none';}"
		+ "})(%s);" % show,
		true
	)


func _resolve_level_override() -> String:
	"""Web: ?level= / ?level_id= overrides exported level (A3 tutorial variants)."""
	if not _is_web:
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{var q=new URLSearchParams(location.search);"
		+ "return q.get('level')||q.get('level_id')||''}catch(e){return ''}})()",
		true
	)).strip_edges()


func _is_place_il_level() -> bool:
	"""Workshop place IL + A3 tutorial_place_* variants."""
	return level_id == "demo_workshop" or level_id.begins_with("tutorial_place")


func _is_chassis_play() -> bool:
	"""City / race DiffBot levels — no arm joints UI."""
	return level_id == "demo_city" or level_id == "demo_race"


func _move_speed() -> float:
	"""Forward/strafe cmd scale (race uses high-speed chassis)."""
	return MOVE_SPEED_RACE if level_id == "demo_race" else MOVE_SPEED


func _turn_speed() -> float:
	"""Yaw rate cmd scale."""
	return TURN_SPEED_RACE if level_id == "demo_race" else TURN_SPEED


func _place_il_time_limit_s() -> float:
	"""Match extensions.mw.il.time_limit_s for HUD countdown."""
	if level_id == "tutorial_place_near":
		return 240.0
	if level_id == "tutorial_place_tight":
		return 120.0
	return 180.0


func _resolve_replay_id() -> String:
	"""Web: ?replay=<session_id> for D8 offline playback."""
	if not _is_web:
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('replay')||''}catch(e){return ''}})()",
		true
	))


func _on_replay_frame(t_sim: float) -> void:
	_update_hud(-1, t_sim)

func _resolve_hud_label() -> Label:
	"""Resolve Label under Hud (Margin/... or legacy PanelContainer/...)."""
	for path in [
		"Hud/Margin/PanelContainer/MarginContainer/Label",
		"Hud/Root/PanelContainer/MarginContainer/Label",
		"Hud/PanelContainer/MarginContainer/Label",
	]:
		var n := get_node_or_null(path)
		if n != null:
			return n as Label
	return $Hud/PanelContainer/MarginContainer/Label as Label


func _ensure_hud_layout() -> void:
	"""Desktop/web HUD surface fixup (delegates to MWHud)."""
	MWHud.apply_layout(self)


func _install_web_keyboard_bridge() -> void:
	"""Bind document keydown/keyup on the page (single-thread Web only)."""
	_web_key_cb = JavaScriptBridge.create_callback(_on_dom_key_event)
	_web_blur_cb = JavaScriptBridge.create_callback(_on_dom_blur)
	var document = JavaScriptBridge.get_interface("document")
	var window_obj = JavaScriptBridge.get_interface("window")
	if document == null or window_obj == null:
		push_warning("[MW] JavaScriptBridge document/window missing")
		return
	document.addEventListener("keydown", _web_key_cb)
	document.addEventListener("keyup", _web_key_cb)
	window_obj.addEventListener("blur", _web_blur_cb)
	print("[MW] key bridge: document listeners registered")


func _on_dom_key_event(args: Array) -> void:
	"""DOM keydown/keyup → update _held_codes. args[0] is the KeyboardEvent."""
	if args.is_empty():
		return
	var event = args[0]
	var code := str(event.code)
	var down := str(event.type) == "keydown"
	_held_codes[code] = down
	if not _web_key_logged and down:
		_web_key_logged = true
		print("[MW] first key from document: ", code)
	if down and not bool(event.repeat) and camera_rig != null and camera_rig.has_method("handle_code"):
		camera_rig.handle_code(code, true)
	if _WEB_BLOCK_CODES.has(code):
		event.preventDefault()
	if down and not bool(event.repeat):
		match code:
			"KeyT":
				if not _controlled and not _mission_done and ws.session_id != "":
					ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})
			"KeyR":
				if _controlled and ws.session_id != "":
					ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
			"Space":
				if _replay != null and _replay.is_active():
					_replay.toggle_pause()
			"Escape":
				_leave_to_hub()


func _leave_to_hub() -> void:
	"""Esc → Hub; strip ?replay=/?room= so Hub does not re-route or join play rooms."""
	# Stop cmds + drop play room before scene swap (avoids stale WS / sticky keys).
	if ws != null:
		ws.close_link()
	if _is_web:
		JavaScriptBridge.eval(
			"(function(){try{"
			+ "if(typeof window.MW_CLEAR_MISSION==='function'){window.MW_CLEAR_MISSION();}"
			+ "var el=document.getElementById('mw-success');"
			+ "if(el){el.classList.remove('show','fail');}"
			+ "window._mw_keys=Object.create(null);"
			+ "var u=new URL(location.href);"
			+ "u.searchParams.delete('replay');"
			+ "u.searchParams.delete('room');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);"
			+ "}catch(e){}})()",
			true
		)
	_held.clear()
	_held_codes.clear()
	MWTransition.go("res://demo_hub.tscn", "Hub", "#8a93a3")


func _on_camera_view_changed(label: String) -> void:
	"""Show camera mode on HUD when V cycles (CameraRig SSOT)."""
	_status_line = "相机 · Camera: %s（V 切换 · C 回正）" % label
	_update_hud()


func _sync_first_person_mesh() -> void:
	"""Hide own chassis in FP so the camera is not inside the hull."""
	var own := _own_mech()
	if own == null:
		return
	var fp := false
	if camera_rig != null and camera_rig.has_method("is_first_person"):
		fp = bool(camera_rig.is_first_person())
	own.visible = not fp


func _on_dom_blur(_args: Array) -> void:
	"""Clear held keys when the browser tab loses focus."""
	_held_codes.clear()


func _web_key(code: String) -> bool:
	"""True if this KeyboardEvent.code is held."""
	return bool(_held_codes.get(code, false))


func _resolve_gateway_url() -> String:
	"""Prefer window.MINEWORLD_GATEWAY on Web; else exported gateway_url."""
	if _is_web:
		var from_js := str(JavaScriptBridge.eval("window.MINEWORLD_GATEWAY || ''", true))
		if from_js != "":
			return from_js
	return gateway_url


func _resolve_room_id() -> String:
	"""Web: ?room= → window.MINEWORLD_ROOM → sessionStorage; else @export room_id.

	Do not rely on `window.MINEWORLD_ROOM=...; location.reload()` — reload clears
	window vars. Prefer http://host/?room=city for training yard e2e.
	demo_city defaults to shared room `city` when omitted.
	demo_race defaults to shared room `race` when omitted.
	"""
	if _is_web:
		var from_q := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('room')||''}catch(e){return ''}})()",
			true
		))
		if from_q != "":
			return from_q
		var from_js := str(JavaScriptBridge.eval(
			"window.MINEWORLD_ROOM || sessionStorage.getItem('MINEWORLD_ROOM') || ''",
			true
		))
		if from_js != "":
			return from_js
	if room_id != "":
		return room_id
	if level_id == "demo_city":
		return "city"
	if level_id == "demo_race":
		return "race"
	return room_id


func _own_mech() -> Node3D:
	"""Puppet for the assigned controlled entity."""
	if _puppets.has(_controlled_entity_id):
		return _puppets[_controlled_entity_id]
	return mech


func _load_profile() -> Dictionary:
	"""Load platform/local profile for join + score (same sources as hub)."""
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
		"id": "local-%s" % str(Time.get_unix_time_from_system()).replace(".", ""),
		"nickname": "Guest",
		"accent": "#4aa3ff",
	}


func _on_hello(payload: Dictionary) -> void:
	_hello = payload
	_session_id = ws.session_id
	_joined_room_id = _resolve_room_id()
	print("[MW] hello session=%s room=%s payload=%s" % [_session_id, _joined_room_id, payload])
	var nick := str(_profile.get("nickname", "godot_spike"))
	if nick == "":
		nick = "godot_spike"
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
	_update_hud()


func _resolve_space_id() -> String:
	"""E3: optional ?space_id= attribution for recordings / scores."""
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('space_id')||''}catch(e){return ''}})()",
		true
	)).strip_edges()


func _on_scene(payload: Dictionary) -> void:
	print("[MW] scene level=%s entities=%d" % [payload.get("level_id", ""), (payload.get("entities", []) as Array).size()])
	_controlled = false
	_mission_done = false
	_status_line = ""
	if _is_place_il_level():
		var lim := int(_place_il_time_limit_s())
		_status_line = MWi18n.t(
			"工坊 · 夹小料块 → 放到工作台橙区并张开夹爪（时限 %ds）",
			"Workshop · grasp block → place on orange pad, open gripper (%ds)"
		) % lim
	var ext: Dictionary = payload.get("extensions", {})
	if typeof(ext) == TYPE_DICTIONARY:
		var mw: Variant = ext.get("mw", {})
		if typeof(mw) == TYPE_DICTIONARY:
			if str(mw.get("controlled_entity_id", "")) != "":
				_controlled_entity_id = str(mw.get("controlled_entity_id"))
			if str(mw.get("room_id", "")) != "":
				_joined_room_id = str(mw.get("room_id"))
	_ensure_puppets(payload.get("entities", []) as Array)
	var own := _own_mech()
	if camera_rig != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(own)
	ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})


func _ensure_puppets(entities: Array) -> void:
	"""Create/update puppets for mechs and dynamic_props in the scene list."""
	var live_mechs: Dictionary = {}
	for entity in entities:
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var kind := str(entity.get("kind", "mech"))
		var eid := str(entity.get("entity_id", ""))
		if eid == "":
			continue
		if kind == "dynamic_prop":
			_ensure_prop_puppet(eid, entity.get("size", null))
			continue
		if kind != "mech":
			continue
		live_mechs[eid] = true
		if not _puppets.has(eid):
			var copy: Node3D = mech.duplicate()
			copy.name = "Mech_%s" % eid
			copy.set("entity_id", eid)
			add_child(copy)
			_puppets[eid] = copy
			print("[MW] spawned puppet entity_id=%s" % eid)
		var puppet = _puppets[eid]
		puppet.set("entity_id", eid)
		if puppet.has_method("apply_team_look"):
			puppet.apply_team_look()
		puppet.visible = true
	# Keep template entity_id in sync when we were assigned mech_player_b.
	if _puppets.has(_controlled_entity_id):
		var p = _puppets[_controlled_entity_id]
		p.set("entity_id", _controlled_entity_id)
		if p.has_method("apply_team_look"):
			p.apply_team_look()
	if level_id == "demo_race" and not live_mechs.is_empty():
		_prune_race_puppets(live_mechs)


func _prune_race_puppets(live_mechs: Dictionary) -> void:
	"""Hide DiffBots for empty race slots (avoids stacked ghost grid)."""
	for eid in _puppets.keys():
		var node = _puppets[eid]
		if node == null or not str(eid).begins_with("mech_"):
			continue
		if live_mechs.has(eid):
			continue
		if eid == _controlled_entity_id:
			continue
		node.visible = false


func _ensure_prop_puppet(eid: String, size_arr: Variant = null) -> void:
	"""Spawn a pushable-box visual for dynamic_prop entity_id."""
	if _puppets.has(eid):
		return
	var prop_script: Script = load("res://scripts/prop_puppet.gd") as Script
	var node := Node3D.new()
	node.set_script(prop_script)
	node.name = "Prop_%s" % eid
	node.set("entity_id", eid)
	if typeof(size_arr) == TYPE_ARRAY and size_arr.size() >= 3:
		node.set("box_size", Vector3(float(size_arr[0]), float(size_arr[1]), float(size_arr[2])))
	add_child(node)
	_puppets[eid] = node
	print("[MW] spawned prop entity_id=%s" % eid)


func _on_event(payload: Dictionary) -> void:
	var et := str(payload.get("event_type", ""))
	print("[MW] event %s" % et)
	match et:
		"player_take_control":
			_controlled = true
		"player_release_control":
			_controlled = false
		"objective_complete":
			var detail_v: Variant = payload.get("detail", {})
			var detail: Dictionary = detail_v if typeof(detail_v) == TYPE_DICTIONARY else {}
			var kind := str(detail.get("kind", ""))
			var oid := str(payload.get("objective_id", "?"))
			# grasp_lift / stow milestones — keep control for place.
			if level_id == "demo_race" and oid.begins_with("obj_cp"):
				# R3 sector split: sim time since last checkpoint.
				var t_now := _last_state_t
				if _lap_start_t >= 0.0:
					_lap_splits.append("%s %.1fs" % [oid.trim_prefix("obj_"), t_now - _lap_start_t])
					if _lap_splits.size() > 3:
						_lap_splits.pop_front()
				_lap_start_t = t_now
				_update_hud()
				return
			if oid == "obj_race_finish" and _lap_start_t >= 0.0:
				_lap_splits.append("lap %.1fs" % (_last_state_t - _lap_start_t))
				_lap_start_t = -1.0
			if kind == "grasp_lift" or kind == "milestone" or oid == "obj_lift_block":
				if oid == "obj_stow_crate" or kind == "milestone":
					_status_line = MWi18n.t(
						"料箱已入区 · 继续：夹料块放到工作台",
						"Crate stowed · next: place block on bench"
					)
				else:
					_status_line = MWi18n.t(
						"已夹起 · 放到工作台并张开夹爪",
						"Lifted · place on bench and open gripper"
					)
				_update_hud()
				return
			_mission_done = true
			var pts := int(detail.get("points", 0))
			if pts <= 0:
				pts = int(payload.get("points", 0))
			_status_line = MWi18n.t("通关 · %s", "SUCCESS · %s") % oid
			_hud.show_mission_result(true, oid, pts, ws.session_id)
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
		"duel_result":
			var d_v: Variant = payload.get("detail", {})
			var d: Dictionary = d_v if typeof(d_v) == TYPE_DICTIONARY else {}
			var winner := str(d.get("winner_entity_id", ""))
			var win := winner == _controlled_entity_id
			var wname := str(d.get("winner_name", winner))
			var wtime := float(d.get("win_time_s", 0.0))
			_status_line = (
				MWi18n.t("对决胜利 · %.1fs", "DUEL WIN · %.1fs") % wtime
				if win
				else MWi18n.t("对决落败 · %s %.1fs", "DUEL LOSE · %s %.1fs") % [wname, wtime]
			)
			_hud.show_mission_result(
				win, _status_line, 0, ws.session_id, "YOU WIN" if win else "YOU LOSE"
			)
			_update_hud()
		"objective_failed":
			_mission_done = true
			_status_line = MWi18n.t("失败 · %s", "FAIL · %s") % payload.get("objective_id", "?")
			_hud.show_mission_result(false, str(payload.get("objective_id", "objective")), 0, ws.session_id)
			if _controlled:
				ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})
	_update_hud()


func _on_gateway_error(payload: Dictionary) -> void:
	"""Surface gateway errors; bounce to Hub when training yard is full."""
	var code := str(payload.get("code", "?"))
	_last_error = "%s: %s" % [code, payload.get("message", "")]
	push_warning("[MW] gateway error: %s" % payload)
	if code == "ROOM_FULL" and _is_chassis_play():
		var max_n := 6 if level_id == "demo_race" else 5
		_status_line = MWi18n.t("房间已满（最多 %d 人），返回母港", "Room full (max %d) — back to Hub") % max_n
		_update_hud()
		call_deferred("_bounce_yard_full_to_hub")
		return
	_update_hud()


func _bounce_yard_full_to_hub() -> void:
	"""ROOM_FULL on shared chassis rooms → leave play scene without sticking."""
	if ws != null:
		ws.close_link()
	if _is_web:
		JavaScriptBridge.eval(
			"(function(){try{"
			+ "window._mw_keys=Object.create(null);"
			+ "var u=new URL(location.href);"
			+ "u.searchParams.delete('replay');"
			+ "u.searchParams.delete('room');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);"
			+ "}catch(e){}})()",
			true
		)
	_held.clear()
	_held_codes.clear()
	MWTransition.go(
		"res://demo_hub.tscn",
		MWi18n.t("房间已满", "Room full"),
		"#4aa3ff"
	)


func _on_link_state(connected: bool) -> void:
	if not connected and _status_line == "":
		_status_line = "Disconnected · reconnecting…"
	elif connected and _status_line.begins_with("Disconnected"):
		_status_line = "Reconnected · waiting for scene…"
	_update_hud()


func _on_link_phase(phase: String) -> void:
	"""UX3: surface connect/reconnect in play HUD (shared WsClient)."""
	match phase:
		"connecting":
			_status_line = "Connecting to gateway…"
		"reconnecting":
			_status_line = "Disconnected · reconnecting…"
		"connected":
			if _status_line.begins_with("Disconnected") or _status_line.begins_with("Connecting"):
				_status_line = "Connected"
		"disconnected":
			_status_line = "Offline — start gateway: echo_server.py"
	_update_hud()


func _on_state(tick: int, t_sim: float, payload: Dictionary) -> void:
	for entity in payload.get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str(entity.get("entity_id", ""))
		if eid == "" or not _puppets.has(eid):
			continue
		var puppet = _puppets[eid]
		if puppet.has_method("apply_state"):
			puppet.apply_state(entity, t_sim)
	var own = _own_mech()
	if tick - _last_log_tick >= 20:
		_last_log_tick = tick
		var held_w := _web_key("KeyW") if _is_web else _key_down(KEY_W)
		var mw_x := float(own.get("last_mw_x")) if "last_mw_x" in own else 0.0
		var mw_y := float(own.get("last_mw_y")) if "last_mw_y" in own else 0.0
		print(
			"[MW] state tick=%d t_sim=%.3f srv=(%.2f, %.2f) pos=(%.2f, %.2f) heldW=%s ctrl=%s entity=%s"
			% [
				tick, t_sim, mw_x, mw_y,
				own.position.x, own.position.z, held_w, _controlled, _controlled_entity_id,
			]
		)
	_update_hud(tick, t_sim)


func _process(delta: float) -> void:
	if _replay != null and _replay.is_active():
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
		_replay.advance(delta)
		return
	# Web: arrow keys pan camera (document bridge). Desktop: camera_rig reads Input.
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
	if ws.session_id == "":
		return
	if not _controlled or _mission_done:
		return
	_cmd_timer += delta
	if _cmd_timer >= 1.0 / CMD_HZ:
		_cmd_timer = 0.0
		_send_velocity_cmd()
	if _ghost != null:
		_ghost.advance(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not _is_web:
		_set_held(event.keycode, event.pressed)
		_set_held(event.physical_keycode, event.pressed)
		if event.pressed and not event.echo:
			var code: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
			if code == KEY_ESCAPE:
				_leave_to_hub()
				return
			if code == KEY_SPACE and _replay != null and _replay.is_active():
				_replay.toggle_pause()
				return
			if ws.session_id == "":
				return
			match code:
				KEY_T:
					if not _controlled and not _mission_done:
						ws.send_cmd({"action": "take_control", "entity_id": _controlled_entity_id})
				KEY_R:
					if _controlled:
						ws.send_cmd({"action": "release_control", "entity_id": _controlled_entity_id})


func _set_held(code: int, pressed: bool) -> void:
	"""Record key down/up; ignore KEY_NONE."""
	if code == KEY_NONE:
		return
	_held[code] = pressed


func _key_down(code: int) -> bool:
	"""True if this keycode is currently held (desktop)."""
	return bool(_held.get(code, false))


func _ensure_joint_sliders() -> void:
	"""Desktop: bottom-left HSliders for arm/gripper (V1c). Web uses DOM #mw-joints."""
	if _is_web or _joint_panel != null:
		return
	# City DiffBot has no arm — skip desktop panel too.
	if _is_chassis_play():
		return
	_joint_panel = CanvasLayer.new()
	_joint_panel.name = "JointSliders"
	_joint_panel.layer = 12
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	root.offset_left = 12
	root.offset_bottom = -12
	root.offset_right = 280
	root.offset_top = -160
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var col := VBoxContainer.new()
	var title := Label.new()
	title.text = "Arm / gripper"
	col.add_child(title)
	for spec in _JOINT_SPECS:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = str(spec["label"])
		lab.custom_minimum_size = Vector2(72, 0)
		var slider := HSlider.new()
		slider.name = "Slider_%s" % spec["id"]
		slider.min_value = float(spec["min"])
		slider.max_value = float(spec["max"])
		slider.step = float(spec["step"])
		slider.value = float(_joint_targets.get(spec["id"], 0.0))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(120, 0)
		var jid := str(spec["id"])
		slider.value_changed.connect(func(v: float) -> void: _joint_targets[jid] = v)
		row.add_child(lab)
		row.add_child(slider)
		col.add_child(row)
	margin.add_child(col)
	panel.add_child(margin)
	root.add_child(panel)
	_joint_panel.add_child(root)
	add_child(_joint_panel)


func _read_joint_targets() -> Dictionary:
	"""Current joint setpoints from web DOM or desktop sliders."""
	if _is_web:
		var raw := str(JavaScriptBridge.eval(
			"JSON.stringify(window.MW_JOINT_TARGETS||{})"
		))
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			var out: Dictionary = {}
			for spec in _JOINT_SPECS:
				var jid := str(spec["id"])
				out[jid] = float((parsed as Dictionary).get(jid, _joint_targets.get(jid, 0.0)))
			_joint_targets = out
			return out
	return _joint_targets.duplicate()


func _race_forward_speed() -> float:
	"""Body +X speed of the controlled race car (m/s)."""
	if not _puppets.has(_controlled_entity_id):
		return 0.0
	var own = _puppets[_controlled_entity_id]
	if own != null and own.has_method("body_forward_speed"):
		return float(own.call("body_forward_speed"))
	return 0.0


func _on_ghost_loaded(ghost_name: String) -> void:
	_status_line = "幽灵车 · %s 的最快圈" % ghost_name
	_update_hud()


func _send_drive_cmd() -> void:
	if _controlled_entity_id == "":
		return
	ws.send_cmd({
		"entity_id": _controlled_entity_id,
		"control_mode": "drive",
		"throttle": snappedf(_drive.throttle, 0.01),
		"brake": snappedf(_drive.brake, 0.01),
		"steer": snappedf(_drive.steer, 0.01),
		"handbrake": 0.0,
	})


func _send_velocity_cmd() -> void:
	var vx := 0.0
	var vy := 0.0
	var yaw_rate := 0.0
	var spd := _move_speed()
	var turn := _turn_speed()
	var strafe := STRAFE_SPEED_RACE if level_id == "demo_race" else spd
	var w := false
	var s := false
	var a := false
	var d := false
	var q := false
	var e := false
	var x_rev := false
	if _is_web:
		w = _web_key("KeyW")
		s = _web_key("KeyS")
		a = _web_key("KeyA")
		d = _web_key("KeyD")
		q = _web_key("KeyQ")
		e = _web_key("KeyE")
		x_rev = _web_key("KeyX")
	else:
		w = _key_down(KEY_W)
		s = _key_down(KEY_S)
		a = _key_down(KEY_A)
		d = _key_down(KEY_D)
		q = _key_down(KEY_Q)
		e = _key_down(KEY_E)
		x_rev = _key_down(KEY_X)
	if level_id == "demo_race":
		# R2 analog drive → control_mode "drive" (see gateway DRIVE_DEFAULTS).
		_drive.update(w, s, q, e, x_rev, _race_forward_speed(), 1.0 / CMD_HZ)
		var fx_own := _own_mech()
		if _race_fx == null:
			_race_fx = MWRaceFX.new()
			_race_fx.name = "RaceFX"
			add_child(_race_fx)
		_race_fx.ensure_smoke(fx_own)
		_race_fx.update(fx_own, _race_forward_speed(), _drive.brake, _drive.steer, 1.0 / CMD_HZ)
		if camera_rig != null and camera_rig.has_method("set_drive_speed"):
			camera_rig.set_drive_speed(_race_forward_speed())
		_send_drive_cmd()
		return
	elif _is_web:
		if w:
			vx += spd
		if s:
			vx -= spd
		if a:
			vy += spd
		if d:
			vy -= spd
		if q:
			yaw_rate += turn
		if e:
			yaw_rate -= turn
	else:
		if w:
			vx += spd
		if s:
			vx -= spd
		if a:
			vy += spd
		if d:
			vy -= spd
		if q:
			yaw_rate += turn
		if e:
			yaw_rate -= turn
		if vx == 0.0 and vy == 0.0 and yaw_rate == 0.0:
			vx = Input.get_axis("move_back", "move_forward") * spd
			vy = Input.get_axis("strafe_left", "strafe_right") * -spd
			yaw_rate = Input.get_axis("turn_cw", "turn_ccw") * turn
	if vx != 0.0 or vy != 0.0 or yaw_rate != 0.0:
		print("[MW] cmd vx=%.1f vy=%.1f yaw_rate=%.1f entity=%s" % [vx, vy, yaw_rate, _controlled_entity_id])
	var payload := {
		"entity_id": _controlled_entity_id,
		"control_mode": "velocity",
		"vx": vx,
		"vy": vy,
		"yaw_rate": yaw_rate,
	}
	# Workshop arm only — city/race DiffBot rejects arm_* (UNKNOWN_JOINT spam).
	if not _is_chassis_play():
		payload["joint_targets"] = _read_joint_targets()
	ws.send_cmd(payload)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		ws.close_link()


func _load_race_centerline() -> void:
	# demo_race centerline → cumulative distances for duel progress delta.
	var raw := FileAccess.get_file_as_string("res://data/race_layout.json")
	if raw == "":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var cl: Array = (parsed as Dictionary).get("centerline", [])
	if cl.size() < 2:
		return
	_race_pts.clear()
	for pt in cl:
		if typeof(pt) == TYPE_DICTIONARY:
			var d := pt as Dictionary
			_race_pts.append(Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))))
	_race_cum.clear()
	_race_cum.append(0.0)
	for i in range(1, _race_pts.size()):
		_race_cum.append(_race_cum[i - 1] + _race_pts[i].distance_to(_race_pts[i - 1]))
	_race_track_len = _race_cum[_race_cum.size() - 1] + _race_pts[0].distance_to(
		_race_pts[_race_pts.size() - 1]
	)


func _race_progress_m(eid: String) -> float:
	# Nearest-centerline progress (m along lap) with per-entity wrap hint.
	if _race_pts.size() < 2 or not _puppets.has(eid):
		return -1.0
	var puppet = _puppets[eid]
	if not ("last_mw_x" in puppet):
		return -1.0
	var px := float(puppet.get("last_mw_x"))
	var py := float(puppet.get("last_mw_y"))
	var n := _race_pts.size()
	var hint := int(_duel_hint_idx.get(eid, 0))
	var best := hint
	var best_d := 1e18
	for off in range(-20, 21):
		var i: int = (hint + off + n) % n
		var dd := _race_pts[i].distance_squared_to(Vector2(px, py))
		if dd < best_d:
			best_d = dd
			best = i
	if best_d > 225.0:  # >15m off line: full rescan (spawn/reset)
		for i in n:
			var dd2 := _race_pts[i].distance_squared_to(Vector2(px, py))
			if dd2 < best_d:
				best_d = dd2
				best = i
	_duel_hint_idx[eid] = best
	return _race_cum[best]


func _duel_delta_text() -> String:
	# Shortest signed gap vs nearest opponent on the loop (client-side).
	if _race_track_len <= 0.0:
		return ""
	var self_p := _race_progress_m(_controlled_entity_id)
	if self_p < 0.0:
		return ""
	var best_abs := 1e18
	var best_delta := 0.0
	var found := false
	for eid in _puppets.keys():
		var id_str := str(eid)
		if id_str == _controlled_entity_id or not id_str.begins_with("mech_player"):
			continue
		var opp_p := _race_progress_m(id_str)
		if opp_p < 0.0:
			continue
		var delta := fmod(self_p - opp_p + _race_track_len * 1.5, _race_track_len) - _race_track_len * 0.5
		if absf(delta) < best_abs:
			best_abs = absf(delta)
			best_delta = delta
			found = true
	if not found:
		return ""
	var word := MWi18n.t("领先", "ahead") if best_delta >= 0.0 else MWi18n.t("落后", "behind")
	return "\n" + MWi18n.t("对决 %s %.0fm", "duel %s %.0fm") % [word, absf(best_delta)]


func _update_hud(tick: int = -1, t_sim: float = 0.0) -> void:
	var own = _own_mech()
	if _replay != null and _replay.is_active():
		var text := "MineWorld · REPLAY\n"
		text += "%s\n" % _replay.status
		text += "session: %s\n" % _replay.session
		if tick >= 0 or t_sim > 0.0:
			text += "t_sim=%.2f frame=%d/%d\n" % [
				t_sim if t_sim > 0.0 else _replay.t,
				_replay.idx + 1,
				_replay.frames.size(),
			]
			text += "pos=(%.2f, %.2f) yaw=%.2f\n" % [
				own.position.x, own.position.z, own.rotation.y,
			]
		text += "\nSpace pause/restart | arrows pan | C center | Recordings ←"
		if _is_web:
			_hud.push_web_hud(text)
		elif hud_label != null:
			hud_label.text = text
		return
	var state_name := "disconnected"
	if ws.session_id != "":
		state_name = "linked"
	var text := "MineWorld · %s\n" % level_id
	text += "link: %s | control: %s | entity: %s\n" % [
		state_name, "ON" if _controlled else "OFF", _controlled_entity_id,
	]
	text += "room: %s\n" % (_joined_room_id if _joined_room_id != "" else "(private)")
	var space_id := _resolve_space_id()
	if space_id != "":
		text += "space_id: %s · route: pms_space\n" % space_id
	if _is_web:
		text += "input: document→godot | heldW=%s\n" % _web_key("KeyW")
	if _status_line != "":
		text += "%s\n" % _status_line
	if _is_place_il_level() and not _mission_done and t_sim > 0.0:
		var left := _place_il_time_limit_s() - t_sim
		if left < 0.0:
			left = 0.0
		text += MWi18n.t("剩余 %.0fs", "left %.0fs") % left + "\n"
	if _mission_done:
		text += MWi18n.t("任务结束 — Esc 回母港", "MISSION DONE — Esc to hangar") + "\n"
	if _hello:
		text += "protocol: %s | dt=%.2f sim=%dHz state=%dHz\n" % [
			_hello.get("protocol_version", "?"),
			float(_hello.get("dt", 0.0)),
			int(_hello.get("sim_hz", 0)),
			int(_hello.get("state_hz", 0)),
		]
		text += "frame: %s | features: %s\n" % [_hello.get("frame", "?"), _hello.get("features", [])]
	if tick >= 0:
		_last_state_t = t_sim
		text += "tick=%d t_sim=%.2f\n" % [tick, t_sim]
		text += "pos=(%.2f, %.2f) yaw=%.2f\n" % [own.position.x, own.position.z, own.rotation.y]
	if _last_error != "":
		text += "\n! gateway error: %s" % _last_error
	text += "\nWASD 平移 | QE 转向 | T 接管 | R 释放 | 左下角臂爪滑条"
	if level_id == "demo_race":
		var kmh := absf(_race_forward_speed()) * 3.6
		text += "\n车速 %3.0f km/h | 油门 %s | 刹车 %s\n转向 %s" % [
			kmh, MWHud.bar(_drive.throttle), MWHud.bar(_drive.brake), MWHud.steer_bar(_drive.steer),
		]
		if _lap_splits.size() > 0:
			text += "\n" + " | ".join(_lap_splits)
		text += _duel_delta_text()
		text += "\nRace: W 油门 | S 刹车 | X 倒车 | Q/E 转向"
	text += "\nV 相机 | 左键 peek 松手回中 | 右键粘性环视 | 中键/左右同按平移 | 滚轮缩放 | C 强制回中"
	if _is_web:
		text += "\n录制 → 右上角链接"
	if _is_web:
		text += "\n历史: /recordings.html"
	if _is_web:
		_hud.push_web_hud(text)
	elif hud_label != null:
		hud_label.text = text
