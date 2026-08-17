class_name MWSplatBridge
## docs/33: Godot side of 3DGS under-canvas compositing.
## Chessroom (P-door) primary. Hub splat is opt-in via ?splatHub=1 (dual-WebGL risk).
## Transparent clear + MW_CAM_POSE @ ~20Hz. JS starts Spark via MW_SPLAT_START.

const POSE_HZ := 20.0


static func enabled(level_id: String) -> bool:
	"""True on web + ?splat= + splatOn=1. Hub also needs splatHub=1."""
	if not OS.has_feature("web"):
		return false
	var raw := str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('splat')||''}catch(e){return ''}})()",
		true
	)).strip_edges()
	if raw == "":
		return false
	var dev := str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('splatOn')||''}catch(e){return ''}})()",
		true
	)).strip_edges()
	if dev != "1":
		return false
	if level_id == "demo_hub":
		var hub := str(JavaScriptBridge.eval(
			"(function(){try{return new URLSearchParams(location.search).get('splatHub')||''}catch(e){return ''}})()",
			true
		)).strip_edges()
		return hub == "1"
	if level_id in ["demo_chessroom", "demo_race"]:
		return true
	return false


static func start_js() -> void:
	"""Ask web layer to boot Spark (idempotent)."""
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"if(typeof window.MW_SPLAT_START==='function'){window.MW_SPLAT_START();}",
		true
	)


static func apply_hub_skin(scene_root: Node) -> void:
	"""Hub: hide HangarDress (may be under Decor; built deferred — also hub_dress)."""
	apply_transparency(scene_root)
	_hide_named(scene_root, "HangarDress")


static func apply_chessroom_skin(scene_root: Node) -> void:
	"""Chessroom: transparent clear so under-canvas splat shows; shell hide is separate."""
	apply_transparency(scene_root)


static func hide_chessroom_shell(scene_root: Node) -> void:
	"""Hide box shell after splat is actually drawing (avoid black void)."""
	# Re-assert transparency right before hide — Hub→chess may reset clear.
	apply_transparency(scene_root)
	for n in ["Floor", "WallN", "WallS", "WallW", "WallE"]:
		_hide_named(scene_root, n)


static func show_chessroom_shell(scene_root: Node) -> void:
	"""Restore shell if splat failed to draw."""
	for n in ["Floor", "WallN", "WallS", "WallW", "WallE"]:
		var node := scene_root.find_child(n, true, false)
		if node != null:
			node.visible = true


static func _hide_named(scene_root: Node, node_name: String) -> void:
	"""Hide first match by name (recursive)."""
	var node := scene_root.find_child(node_name, true, false)
	if node != null:
		node.visible = false


static func apply_transparency(scene_root: Node) -> void:
	"""Godot Web must clear with alpha=0 so #mw-splat shows through."""
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
	var vp := scene_root.get_viewport()
	if vp != null:
		vp.transparent_bg = true
	var world := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.background_color = Color(0, 0, 0, 0)
	# CSS: canvas + body must not paint opaque black over the underlay.
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){document.body.classList.add('mw-splat-live');"
			+ "var c=document.getElementById('canvas');"
			+ "if(c){c.style.background='transparent';}})();",
			true
		)


static func push_pose(camera: Camera3D) -> void:
	"""Write camera pose for splat_bg.js (Godot/three both RH Y-up)."""
	if camera == null or not OS.has_feature("web"):
		return
	var o := camera.global_transform.origin
	var q := camera.global_transform.basis.get_rotation_quaternion()
	JavaScriptBridge.eval(
		(
			"window.MW_CAM_POSE={pos:[%f,%f,%f],quat:[%f,%f,%f,%f],fov:%f};"
			% [o.x, o.y, o.z, q.x, q.y, q.z, q.w, camera.fov]
		),
		true
	)
