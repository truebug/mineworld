class_name MWSplatBridge
## docs/33 P1/P2: Godot side of the 3DGS under-canvas compositing.
## Opt-in via ?splat=<name> on demo_race only. When enabled: make the Godot
## canvas transparent (clear color, viewport alpha) and push the active camera
## pose to window.MW_CAM_POSE at ~20Hz for the Spark renderer.

const POSE_HZ := 20.0


static func enabled(level_id: String) -> bool:
	"""True on web + hub/race + explicit ?splat= query (PoC scope)."""
	if not OS.has_feature("web"):
		return false
	if level_id not in ["demo_hub", "demo_race"]:
		return false
	var raw := str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('splat')||''}catch(e){return ''}})()",
		true
	)).strip_edges()
	return raw != ""


static func apply_hub_skin(scene_root: Node) -> void:
	"""Hub splat skin: hide procedural hangar shell, keep avatars/NPCs/doors."""
	apply_transparency(scene_root)
	var dress := scene_root.get_node_or_null("HangarDress")
	if dress != null:
		dress.visible = false


static func apply_transparency(scene_root: Node) -> void:
	"""Let the under-canvas splat show through: clear color + viewport alpha."""
	var vp := scene_root.get_viewport()
	if vp != null:
		vp.transparent_bg = true
	var world := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		world.environment.background_mode = Environment.BG_CLEAR_COLOR


static func push_pose(camera: Camera3D) -> void:
	"""Write camera pose for splat_bg.js (Godot/three both RH Y-up: direct copy)."""
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
