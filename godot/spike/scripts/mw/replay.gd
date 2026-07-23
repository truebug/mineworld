class_name MWReplay
extends Node
## D8 offline replay: fetch frames.jsonl from the platform and drive
## puppets without a Gateway connection. Web only (?replay=<session_id>).
## Puppet creation/application stays in the level script via callables.

signal frame_applied(t_sim: float)

var session := ""
var frames: Array = []
var playing := false
var speed := 1.0
var t := 0.0
var idx := 0
var status := ""

## Wired by the level script before start():
var puppets: Dictionary = {}          # reference to the level's puppet dict
var ensure_puppets_cb: Callable       # func(entities: Array) -> void
var own_mech_getter: Callable         # func() -> Node3D
var camera_rig: Node = null
var hud_refresh: Callable             # func() -> void


func is_active() -> bool:
	return session != ""


func start(session_id: String) -> void:
	"""Fetch frames.jsonl and prepare playback."""
	session = session_id
	status = "loading frames…"
	_hud()
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	if origin == "":
		status = "replay: no origin"
		_hud()
		return
	var http := HTTPRequest.new()
	http.name = "ReplayHttp"
	add_child(http)
	http.request_completed.connect(_on_http.bind(http))
	var url := "%s/api/recordings/%s/frames" % [origin, session.uri_encode()]
	var err := http.request(url)
	if err != OK:
		status = "replay HTTP err %s" % err
		http.queue_free()
		_hud()


func advance(delta: float) -> void:
	"""Advance offline replay clock and apply nearest frame."""
	if not playing or frames.is_empty():
		return
	t += delta * speed
	var last: Dictionary = frames[frames.size() - 1]
	var t_max := float(last.get("t_sim", 0.0))
	if t >= t_max:
		t = t_max
		playing = false
		status = "REPLAY done · Space restart · Esc back"
	while idx + 1 < frames.size():
		var nxt: Dictionary = frames[idx + 1]
		if float(nxt.get("t_sim", 0.0)) > t:
			break
		idx += 1
	apply_frame(idx)


func toggle_pause() -> void:
	"""Space: pause/resume or restart when finished."""
	if frames.is_empty():
		return
	var last: Dictionary = frames[frames.size() - 1]
	var t_max := float(last.get("t_sim", 0.0))
	if t >= t_max and not playing:
		t = 0.0
		idx = 0
		playing = true
		status = "REPLAY · %s · %d frames" % [session.substr(0, 8), frames.size()]
		apply_frame(0)
		return
	playing = not playing
	status = "REPLAY paused" if not playing else "REPLAY playing"
	_hud()


func apply_frame(frame_idx: int) -> void:
	"""Apply one recorded frame to puppets."""
	if frame_idx < 0 or frame_idx >= frames.size():
		return
	var frame: Dictionary = frames[frame_idx]
	var t_sim := float(frame.get("t_sim", 0.0))
	var state: Variant = frame.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return
	for entity in (state as Dictionary).get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str((entity as Dictionary).get("entity_id", ""))
		if eid == "":
			continue
		if not puppets.has(eid) and ensure_puppets_cb.is_valid():
			ensure_puppets_cb.call([entity])
		if not puppets.has(eid):
			continue
		var puppet: Node3D = puppets[eid]
		if puppet.has_method("apply_state"):
			puppet.apply_state(entity, t_sim)
	idx = frame_idx
	frame_applied.emit(t_sim)


func _on_http(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	"""Parse JSONL frames and start playback."""
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		status = "replay load fail %s/%s" % [result, response_code]
		_hud()
		return
	var lines := body.get_string_from_utf8().split("\n", false)
	frames.clear()
	for line in lines:
		if str(line).strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			frames.append(parsed)
	if frames.is_empty():
		status = "replay: empty frames"
		_hud()
		return
	# Seed puppets from first frame entities.
	var first: Dictionary = frames[0]
	var state: Variant = first.get("state", {})
	if typeof(state) == TYPE_DICTIONARY and ensure_puppets_cb.is_valid():
		ensure_puppets_cb.call((state as Dictionary).get("entities", []) as Array)
	playing = true
	t = 0.0
	idx = 0
	status = "REPLAY · %s · %d frames · Space pause" % [session.substr(0, 8), frames.size()]
	var own: Node3D = own_mech_getter.call() if own_mech_getter.is_valid() else null
	if camera_rig != null and camera_rig.has_method("set_target"):
		camera_rig.set_target(own)
	apply_frame(0)
	_hud()


func _hud() -> void:
	if hud_refresh.is_valid():
		hud_refresh.call()
