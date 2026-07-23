class_name MWGhost
extends Node
## Ghost car v1: fetch fastest demo_race session from the platform,
## spawn a translucent duplicate of the player's mech, loop its recorded
## trajectory. Pure viewer — never feeds physics. Web only.

signal loaded(ghost_name: String)

var frames: Array = []
var puppet: Node3D = null
var ghost_name := ""
var own_mech_getter: Callable = Callable()

var _t := 0.0
var _loading := false


func fetch_best() -> void:
	"""Query platform for the fastest demo_race session (no-op off web)."""
	if _loading or not OS.has_feature("web"):
		return
	_loading = true
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	if origin == "":
		return
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_best_http.bind(http))
	http.request("%s/api/platform/best_lap?level_id=demo_race" % origin)


func advance(delta: float) -> void:
	if frames.is_empty():
		return
	_t += delta
	_apply_frame()


func is_running() -> bool:
	return puppet != null


func _on_best_http(
	result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest
) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var best: Variant = (data as Dictionary).get("best")
	if typeof(best) != TYPE_DICTIONARY:
		return  # no successful lap recorded yet — ghost stays off
	var sid := str((best as Dictionary).get("session_id", ""))
	ghost_name = str((best as Dictionary).get("display_name", "ghost"))
	if sid == "":
		return
	var origin := str(JavaScriptBridge.eval("location.origin || ''", true))
	var http2 := HTTPRequest.new()
	add_child(http2)
	http2.request_completed.connect(_on_frames_http.bind(http2))
	http2.request("%s/api/recordings/%s/frames" % [origin, sid.uri_encode()])


func _on_frames_http(
	result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest
) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	for line in body.get_string_from_utf8().split("\n", false):
		if str(line).strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			frames.append(parsed)
	if frames.is_empty():
		return
	_spawn_puppet()
	loaded.emit(ghost_name)


func _spawn_puppet() -> void:
	"""Translucent duplicate of own mech template; pure viewer, no physics."""
	if not own_mech_getter.is_valid():
		return
	var tmpl := own_mech_getter.call() as Node3D
	if tmpl == null:
		return
	var ghost := tmpl.duplicate() as Node3D
	ghost.name = "GhostCar"
	ghost.set("entity_id", "__ghost__")
	# Strip scripts' behavior: visual only.
	ghost.set_script(null)
	for child in ghost.get_children():
		if child is Label3D:
			child.queue_free()
	add_child(ghost)
	# Translucent cyan glass look.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.9, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh_inst in ghost.find_children("*", "MeshInstance3D", true, false):
		(mesh_inst as MeshInstance3D).material_override = mat
	puppet = ghost
	_t = 0.0


func _apply_frame() -> void:
	"""Advance ghost along recorded t_sim (loops)."""
	if puppet == null:
		return
	var total := float((frames[-1] as Dictionary).get("t_sim", 0.0))
	if total <= 0.0:
		return
	var t := fmod(_t, total)
	# binary search frame
	var lo := 0
	var hi := frames.size() - 1
	while lo < hi:
		var mid := int((lo + hi + 1) / 2)
		if float((frames[mid] as Dictionary).get("t_sim", 0.0)) <= t:
			lo = mid
		else:
			hi = mid - 1
	var frame: Dictionary = frames[lo]
	var state: Variant = frame.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return
	for entity in (state as Dictionary).get("entities", []):
		if typeof(entity) != TYPE_DICTIONARY:
			continue
		var eid := str((entity as Dictionary).get("entity_id", ""))
		# Follow the recorded winner's own car (first controllable mech).
		if not eid.begins_with("mech_player"):
			continue
		var pose: Variant = (entity as Dictionary).get("base_pose", {})
		if typeof(pose) != TYPE_DICTIONARY:
			continue
		var mw := pose as Dictionary
		puppet.global_position = Vector3(
			float(mw.get("x", 0.0)), float(mw.get("z", 0.0)), -float(mw.get("y", 0.0))
		)
		puppet.global_rotation.y = float(mw.get("yaw", 0.0))
		break
