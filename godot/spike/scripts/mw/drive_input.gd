class_name MWDriveInput
extends RefCounted
## R2 analog drive channels: hold-to-ramp, release-to-decay, auto-center steer.
## Pure logic — no scene access; gamepad axis wins when live.

const THROTTLE_UP := 2.5   # /s ramp to full gas
const THROTTLE_DOWN := 4.0 # /s decay on release
const BRAKE_UP := 5.0      # /s ramp to full brake
const BRAKE_DOWN := 6.0
const STEER_UP := 3.0      # /s toward lock
const STEER_CENTER := 5.0  # /s auto-center on release

var throttle := 0.0
var brake := 0.0
var steer := 0.0


static func approachf(cur: float, target: float, up: float, down: float, dt: float) -> float:
	"""Rate-limited approach: `up` toward ±target, `down` back toward 0."""
	if target != 0.0:
		return move_toward(cur, target, up * dt)
	return move_toward(cur, 0.0, down * dt)


func update(w: bool, s: bool, q: bool, e: bool, x_rev: bool, fwd_speed: float, dt: float) -> void:
	"""Keyboard: hold-to-ramp, release-to-decay; gamepad axis wins when live."""
	var pad_thr := Input.get_axis("move_back", "move_forward")
	var pad_steer := Input.get_axis("turn_ccw", "turn_cw")
	if absf(pad_thr) > 0.15 or absf(pad_steer) > 0.15:
		throttle = clampf(pad_thr, -1.0, 1.0)
		brake = 0.0
		steer = clampf(-pad_steer, -1.0, 1.0)
		return
	if w and not s and not x_rev:
		throttle = approachf(throttle, 1.0, THROTTLE_UP, THROTTLE_DOWN, dt)
	elif x_rev and not w and fwd_speed < 1.0:
		# Reverse gate: only when nearly stopped (NFS-style shift protection).
		throttle = approachf(throttle, -1.0, THROTTLE_UP, THROTTLE_DOWN, dt)
	else:
		throttle = approachf(throttle, 0.0, THROTTLE_UP, THROTTLE_DOWN, dt)
	if s and not w and not x_rev:
		brake = approachf(brake, 1.0, BRAKE_UP, BRAKE_DOWN, dt)
	else:
		brake = approachf(brake, 0.0, BRAKE_UP, BRAKE_DOWN, dt)
	var steer_target := 0.0
	if q:
		steer_target += 1.0
	if e:
		steer_target -= 1.0
	steer = approachf(steer, steer_target, STEER_UP, STEER_CENTER, dt)


func reset() -> void:
	throttle = 0.0
	brake = 0.0
	steer = 0.0
