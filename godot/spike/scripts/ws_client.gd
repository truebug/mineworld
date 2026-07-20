## WebSocket client for the MineWorld POC-A gateway.
## Emits typed signals; owns no rendering logic.
class_name MWWsClient
extends Node

signal hello_received(payload: Dictionary)
signal scene_received(payload: Dictionary)
signal state_received(tick: int, t_sim: float, payload: Dictionary)
signal event_received(payload: Dictionary)
signal gateway_error(payload: Dictionary)
signal link_state_changed(connected: bool)

var url := "ws://127.0.0.1:8765"
var session_id := ""

var _ws := WebSocketPeer.new()
var _connecting := false


func connect_to_gateway(target_url: String = "") -> void:
	if target_url != "":
		url = target_url
	var err := _ws.connect_to_url(url)
	if err != OK:
		push_error("[MW] connect_to_url failed: %s" % error_string(err))
		return
	_connecting = true
	print("[MW] connecting %s" % url)


func _process(_delta: float) -> void:
	if not _connecting and _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _connecting:
				_connecting = false
				link_state_changed.emit(true)
			while _ws.get_available_packet_count() > 0:
				_handle_packet(_ws.get_packet())
		WebSocketPeer.STATE_CLOSED:
			if _connecting:
				return
			_connecting = false
			var code := _ws.get_close_code()
			print("[MW] closed code=%d reason=%s" % [code, _ws.get_close_reason()])
			link_state_changed.emit(false)


func send_msg(msg: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var err := _ws.send_text(JSON.stringify(msg))
	if err != OK:
		push_warning("[MW] ws send failed: %s" % error_string(err))


func send_cmd(payload: Dictionary) -> void:
	send_msg({"type": "cmd", "session_id": session_id, "payload": payload})


func join(
	level_id: String,
	player_name: String,
	room_id: String = "",
	extensions: Dictionary = {}
) -> void:
	"""Join a level; empty room_id → private room (gateway uses session_id)."""
	var payload := {"level_id": level_id, "player_name": player_name}
	if room_id != "":
		payload["room_id"] = room_id
	if not extensions.is_empty():
		payload["extensions"] = extensions
	send_msg({
		"type": "join",
		"session_id": session_id,
		"payload": payload,
	})


func close_link() -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		send_msg({"type": "bye", "session_id": session_id})
		_ws.close(1000, "client bye")


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[MW] non-JSON packet: %s" % text)
		return
	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		"hello":
			session_id = str(msg.get("session_id", ""))
			hello_received.emit(msg.get("payload", {}))
		"scene":
			scene_received.emit(msg.get("payload", {}))
		"state":
			state_received.emit(int(msg.get("tick", 0)), float(msg.get("t_sim", 0.0)), msg.get("payload", {}))
		"event":
			event_received.emit(msg.get("payload", {}))
		"error":
			gateway_error.emit(msg.get("payload", {}))
		_:
			pass
