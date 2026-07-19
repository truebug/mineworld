## Headless M1 acceptance for the Godot spike.
## Run: godot --headless --path godot/spike --script res://headless/smoke_client.gd
## Optional level override: ... --script res://headless/smoke_client.gd -- tutorial_02
## Exits 0 on "smoke OK", 1 on failure. Mirrors scripts/ws_smoke_test.py.
extends SceneTree

const MOVE_SECONDS := 1.5
const GLOBAL_TIMEOUT_MS := 10000

var _ws := WebSocketPeer.new()
var _session_id := ""
var _level_id := "demo_city"
var _phase := "connect"
var _saw_event := false
var _last_x := 0.0
var _drive_until := 0.0
var _start_msec := 0


func _init() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		_level_id = user_args[0]
	print("[smoke] connecting ws://127.0.0.1:8765")
	_start_msec = Time.get_ticks_msec()
	var err := _ws.connect_to_url("ws://127.0.0.1:8765")
	if err != OK:
		_fail("connect_to_url: %s" % error_string(err))


func _process(_delta: float) -> bool:
	if _phase == "done":
		return false
	if Time.get_ticks_msec() - _start_msec > GLOBAL_TIMEOUT_MS:
		_fail("global timeout (%d ms)" % GLOBAL_TIMEOUT_MS)
		return false
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_fail("socket closed during phase=%s (code=%d)" % [_phase, _ws.get_close_code()])
		return false
	if state != WebSocketPeer.STATE_OPEN:
		return false
	while _ws.get_available_packet_count() > 0:
		_handle(_ws.get_packet().get_string_from_utf8())
	match _phase:
		"drive":
			_send({"entity_id": "mech_player", "control_mode": "velocity", "vx": 1.0, "vy": 0.0, "yaw_rate": 0.2})
			if Time.get_ticks_msec() > _drive_until:
				_finish()
	return false


func _handle(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		"hello":
			_session_id = str(msg.get("session_id", ""))
			print("hello ok ", _session_id, " ", msg.get("payload", {}))
			_send_raw({"type": "join", "session_id": _session_id, "payload": {"level_id": _level_id, "player_name": "godot_headless"}})
		"scene":
			var entities: Array = msg.get("payload", {}).get("entities", [])
			print("scene ok ", msg.get("payload", {}).get("level_id", ""), " ", entities.size())
			_send({"action": "take_control", "entity_id": "mech_player"})
			_drive_until = Time.get_ticks_msec() + int(MOVE_SECONDS * 1000.0)
			_phase = "drive"
		"event":
			_saw_event = true
			print("event ", msg.get("payload", {}).get("event_type", ""))
		"state":
			for entity in msg.get("payload", {}).get("entities", []):
				if str(entity.get("entity_id", "")) == "mech_player":
					_last_x = float(entity.get("base_pose", {}).get("x", 0.0))
			print("state tick=", msg.get("tick", 0), " x=%.3f" % _last_x)
		"error":
			_fail("gateway error: %s" % msg.get("payload", {}))


func _finish() -> void:
	if not _saw_event:
		_fail("missing event")
		return
	if _last_x <= 0.05:
		_fail("expected motion in +x from vx=1, got x=%.3f" % _last_x)
		return
	print("smoke OK")
	_ws.close(1000, "done")
	_phase = "done"
	quit(0)


func _send(payload: Dictionary) -> void:
	_send_raw({"type": "cmd", "session_id": _session_id, "payload": payload})


func _send_raw(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


func _fail(reason: String) -> void:
	if _phase == "done":
		return
	printerr("FAIL: ", reason)
	_phase = "done"
	quit(1)
