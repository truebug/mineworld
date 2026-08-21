class_name MWPerf
extends Node
## S5 step 0 (docs/37-38): FPS probe + quality tiers.
## Tiers: "high" (default) / "low" (auto-degrade when fps<30 sustained, or ?quality=low).
## Exposes window.MW_FPS on web; emits quality_changed(tier) for scenes to react.

signal quality_changed(tier: String)

const WINDOW_S := 5.0
const DEGRADE_FPS := 30.0
const LOW_SCALE := 0.75  ## 3D render scale in low tier (pixel-fill relief)

var tier := "high"
var _samples: Array[float] = []
var _window_left := 0.0
var _forced := false
var _degraded_once := false


static func create(scene_root: Node) -> MWPerf:
	var perf := MWPerf.new()
	perf.name = "MWPerf"
	scene_root.add_child(perf)
	return perf


func _ready() -> void:
	var q := _url_param("quality")
	if q in ["low", "high"]:
		tier = q
		_forced = true
	_apply_tier()


func _process(delta: float) -> void:
	_window_left -= delta
	var fps := Engine.get_frames_per_second()
	if fps > 0:
		_samples.append(float(fps))
	if _window_left > 0.0:
		return
	_window_left = WINDOW_S
	var avg := _window_avg()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.MW_FPS=%d;window.MW_QUALITY='%s';" % [int(avg), tier], true)
	if not _forced and not _degraded_once and _samples.size() >= 2 and avg < DEGRADE_FPS:
		_degraded_once = true
		set_tier("low", true)


func set_tier(new_tier: String, auto := false) -> void:
	if new_tier == tier and not auto:
		return
	tier = new_tier
	_apply_tier()
	quality_changed.emit(tier)
	print("[MW] quality tier=%s (auto=%s, avg_fps=%.0f)" % [tier, auto, _window_avg()])


func _apply_tier() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_scale = LOW_SCALE if tier == "low" else 1.0
	# Glow off in low tier (fullscreen passes are the priciest on compatibility).
	var env_node := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.glow_enabled = tier == "high"


func _window_avg() -> float:
	if _samples.is_empty():
		return 60.0
	var total := 0.0
	for s in _samples:
		total += s
	return total / _samples.size()


func _url_param(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('%s')||''}catch(e){return ''}})()" % key,
		true
	)).strip_edges()
