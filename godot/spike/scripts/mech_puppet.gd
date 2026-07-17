## Visual puppet for a gateway-driven entity.
## Buffers the last two base_pose samples and interpolates between them,
## delayed by one state interval (standard entity interpolation).
class_name MWMechPuppet
extends Node3D

var entity_id := ""
var interp_delay := 0.05

var _prev_pos := Vector3.ZERO
var _prev_yaw := 0.0
var _prev_time := -1.0
var _next_pos := Vector3.ZERO
var _next_yaw := 0.0
var _next_time := -1.0
var _has_state := false
var _sim_now := 0.0
var _wall_at_last_state := 0.0


func apply_state(entity: Dictionary, t_sim: float) -> void:
	var pose: Dictionary = entity.get("base_pose", {})
	_sim_now = t_sim
	_wall_at_last_state = Time.get_ticks_msec() / 1000.0
	_prev_pos = _next_pos
	_prev_yaw = _next_yaw
	_prev_time = _next_time
	_next_pos = Vector3(float(pose.get("x", 0.0)), float(pose.get("z", 0.0)), -float(pose.get("y", 0.0)))
	_next_yaw = float(pose.get("yaw", 0.0))
	_next_time = t_sim
	if not _has_state:
		_has_state = true
		_prev_pos = _next_pos
		_prev_yaw = _next_yaw
		_prev_time = t_sim - interp_delay
		position = _next_pos
		rotation.y = _next_yaw


func _process(_delta: float) -> void:
	if not _has_state or _prev_time < 0.0:
		return
	var render_time := _sim_clock() - interp_delay
	var span := _next_time - _prev_time
	if span <= 0.0:
		return
	var alpha := clampf((render_time - _prev_time) / span, 0.0, 1.0)
	position = _prev_pos.lerp(_next_pos, alpha)
	rotation.y = _prev_yaw + (_next_yaw - _prev_yaw) * alpha


func _sim_clock() -> float:
	# Extrapolate forward from the last known sim time using wall clock,
	# so interpolation keeps moving between 20 Hz updates.
	return _sim_now + (Time.get_ticks_msec() / 1000.0 - _wall_at_last_state)
