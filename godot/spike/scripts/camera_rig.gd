## Follow-orbit camera for teleoperation / hub / levels (shared SSOT).
## Modes: chase-behind (default), first-person, orbit (wide 3rd). V cycles.
## Mouse: LMB peek (spring back), RMB sticky look, MMB or L+R pan, wheel zoom, C recenter.
extends Node3D

signal view_mode_changed(label: String)
signal turn_drag_started ## WoW-style: RMB pressed while turn-drive is armed.
signal turn_dragged(dx: float) ## WoW-style: horizontal mouse delta while RMB held.

enum ViewMode { ORBIT, FIRST, CHASE }
enum DragKind { NONE, PEEK, STICKY, PAN }

const CHASE_PITCH_DEFAULT := -0.38

@export var target_path: NodePath
@export var distance := 13.0
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var pitch := -0.6 ## radians; negative = looking down
@export var yaw := 0.5
@export var zoom_step := 1.0
@export var orbit_sensitivity := 0.01
@export var pan_speed := 8.0
@export var pan_mouse_scale := 0.12
@export var max_look_offset := 40.0
@export var view_mode: ViewMode = ViewMode.CHASE
@export var chase_distance := 4.8
@export var min_chase_distance := 2.0
@export var max_chase_distance := 9.0
@export var chase_recenter_speed := 7.0
## R3 speed FX (race): FOV widens + follow lags behind target at speed.
@export var speed_fov_enabled := false
@export var speed_fov_ref := 18.0   ## m/s at full boost
@export var speed_fov_boost := 12.0 ## degrees added at ref speed
@export var follow_lag := 0.0       ## 0 = rigid; ~6 gives elastic chase
## WoW-style RMB: while held, horizontal mouse motion turns the *body* (via
## hub-injected yaw_rate) instead of orbiting the camera. Off by default so
## race/play levels keep the classic sticky-look RMB.
@export var turn_drive_enabled := false

@onready var camera: Camera3D = $Camera3D
var _target: Node3D = null
## World-space offset of the look-at point from the mech (y ignored).
var look_offset := Vector3.ZERO
var _orbit_distance := 13.0
var _orbit_pitch := -0.6
var _orbit_yaw := 0.5
## First-person look offset relative to body forward (radians).
var _fp_yaw := 0.0
var _fp_pitch := 0.0
## Chase: mouse orbit relative to "behind head" (radians).
var _chase_yaw := 0.0
var _chase_pitch := CHASE_PITCH_DEFAULT
var _drive_speed := 0.0
var _base_fov := 0.0
var _follow_pos := Vector3.ZERO
var _follow_init := false
## Sticky/home look (RMB commits; LMB peek springs back here; C resets).
var _c_orbit_yaw := 0.5
var _c_orbit_pitch := -0.6
var _c_fp_yaw := 0.0
var _c_fp_pitch := 0.0
var _c_chase_yaw := 0.0
var _c_chase_pitch := CHASE_PITCH_DEFAULT
var _btn_l := false
var _btn_r := false
var _btn_m := false
var _drag: DragKind = DragKind.NONE


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_orbit_distance = distance
	_orbit_pitch = pitch
	_orbit_yaw = yaw
	_commit_current_look()
	_update_camera()


func set_target(node: Node3D) -> void:
	"""Follow a different mech (e.g. assigned controlled_entity_id)."""
	_target = node
	_update_camera()


func reset_look_offset() -> void:
	"""C / force recenter: pan + look back to mode defaults."""
	look_offset = Vector3.ZERO
	_fp_yaw = 0.0
	_fp_pitch = 0.0
	_chase_yaw = 0.0
	_chase_pitch = CHASE_PITCH_DEFAULT
	yaw = _orbit_yaw
	pitch = _orbit_pitch
	_commit_current_look()
	_update_camera()


func handle_code(code: String, down: bool) -> bool:
	"""Shared camera hotkeys for Web DOM bridge (KeyC / KeyV). Returns true if handled."""
	if not down:
		return false
	if code == "KeyC":
		reset_look_offset()
		return true
	if code == "KeyV":
		cycle_view_mode()
		return true
	return false


func cycle_view_mode() -> String:
	"""Chase-behind → first-person → orbit → chase. Returns mode label."""
	match view_mode:
		ViewMode.CHASE:
			view_mode = ViewMode.FIRST
			_fp_yaw = 0.0
			_fp_pitch = 0.0
			_commit_current_look()
		ViewMode.FIRST:
			view_mode = ViewMode.ORBIT
			distance = _orbit_distance
			pitch = _orbit_pitch
			yaw = _orbit_yaw
			_commit_current_look()
		_:
			view_mode = ViewMode.CHASE
			_chase_yaw = 0.0
			_chase_pitch = CHASE_PITCH_DEFAULT
			chase_distance = 4.8
			_commit_current_look()
	_update_camera()
	var label := view_mode_label()
	view_mode_changed.emit(label)
	return label


func view_mode_label() -> String:
	"""Short HUD label for current mode."""
	match view_mode:
		ViewMode.FIRST:
			return "first-person"
		ViewMode.CHASE:
			return "chase (behind)"
		_:
			return "orbit"


func is_first_person() -> bool:
	"""True when first-person mode is active."""
	return view_mode == ViewMode.FIRST


func get_look_yaw_offset() -> float:
	"""Horizontal peek/sticky offset from body forward (chase / FP modes)."""
	match view_mode:
		ViewMode.FIRST:
			return _fp_yaw
		ViewMode.CHASE:
			return _chase_yaw
		_:
			return 0.0


func snap_look_behind() -> void:
	"""WoW RMB-press: zero the horizontal look offset so the camera sits
	directly behind the body (which the hub has just re-aimed)."""
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw = 0.0
		ViewMode.CHASE:
			_chase_yaw = 0.0
		_:
			return
	_commit_current_look()
	_update_camera()


func pan_axes(right: float, forward: float, delta: float) -> void:
	"""Arrow pan — orbit/chase shift look point; first-person looks."""
	if right == 0.0 and forward == 0.0:
		return
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw -= right * 1.8 * delta
			_fp_pitch = clampf(_fp_pitch + forward * 1.2 * delta, -1.2, 1.0)
			_commit_current_look()
		_:
			_pan_ground(right, forward, delta)


func _pan_ground(right: float, forward: float, delta: float) -> void:
	"""Pan look_offset on the ground plane in camera-relative axes."""
	var basis := (
		camera.global_transform.basis
		if camera != null
		else Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	)
	var right_v := Vector3(basis.x.x, 0.0, basis.x.z)
	var forward_v := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if right_v.length_squared() < 1e-6:
		right_v = Vector3.RIGHT
	else:
		right_v = right_v.normalized()
	if forward_v.length_squared() < 1e-6:
		forward_v = Vector3.FORWARD
	else:
		forward_v = forward_v.normalized()
	look_offset += (right_v * right + forward_v * forward) * pan_speed * delta
	look_offset.y = 0.0
	var flat := Vector2(look_offset.x, look_offset.z)
	if flat.length() > max_look_offset:
		flat = flat.limit_length(max_look_offset)
		look_offset = Vector3(flat.x, 0.0, flat.y)


func _unhandled_input(event: InputEvent) -> void:
	"""Desktop/Web canvas: C recenter, V cycle, wheel zoom, L/R/M mouse."""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C or event.physical_keycode == KEY_C:
			reset_look_offset()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_V or event.physical_keycode == KEY_V:
			cycle_view_mode()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_on_zoom(-1.0)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_on_zoom(1.0)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_btn_l = mb.pressed
			_refresh_drag_kind()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_btn_r = mb.pressed
			_refresh_drag_kind()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_btn_m = mb.pressed
			_refresh_drag_kind()
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseMotion:
		if _drag == DragKind.NONE:
			return
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		if _drag == DragKind.PAN:
			_on_mouse_pan(rel)
		else:
			_on_mouse_look(rel, _drag == DragKind.STICKY)
		get_viewport().set_input_as_handled()


func _refresh_drag_kind() -> void:
	"""LMB peek, RMB sticky, MMB or L+R pan."""
	var was := _drag
	if _btn_m or (_btn_l and _btn_r):
		_drag = DragKind.PAN
	elif _btn_l:
		_drag = DragKind.PEEK
	elif _btn_r:
		_drag = DragKind.STICKY
	else:
		_drag = DragKind.NONE
	if turn_drive_enabled and _drag == DragKind.STICKY and was != DragKind.STICKY:
		turn_drag_started.emit()


func _on_zoom(sign: float) -> void:
	"""Wheel zoom by mode (never auto-resets on mouse release)."""
	match view_mode:
		ViewMode.FIRST:
			_fp_pitch = clampf(_fp_pitch - sign * 0.08, -1.2, 1.0)
			_commit_current_look()
		ViewMode.CHASE:
			chase_distance = clampf(
				chase_distance + sign * zoom_step * 0.45,
				min_chase_distance,
				max_chase_distance,
			)
		_:
			distance = clampf(distance + sign * zoom_step, min_distance, max_distance)
			_orbit_distance = distance
	_update_camera()


func _on_mouse_look(relative: Vector2, commit: bool) -> void:
	"""Orbit / FP / chase look; commit=true stores sticky home (RMB)."""
	if turn_drive_enabled and commit:
		# RMB turn-drive: only pitch follows the mouse; yaw turns the body
		# (hub injects yaw_rate while RMB is held), and the chase camera
		# stays glued behind the body — so the view pans with the turn.
		turn_dragged.emit(relative.x)
		match view_mode:
			ViewMode.FIRST:
				_fp_pitch = clampf(_fp_pitch - relative.y * orbit_sensitivity, -1.2, 1.0)
			ViewMode.CHASE:
				_chase_pitch = clampf(_chase_pitch - relative.y * orbit_sensitivity, -1.0, 0.45)
			_:
				pitch = clampf(pitch - relative.y * orbit_sensitivity, -1.45, -0.05)
		_commit_current_look()
		_update_camera()
		return
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw -= relative.x * orbit_sensitivity
			_fp_pitch = clampf(_fp_pitch - relative.y * orbit_sensitivity, -1.2, 1.0)
		ViewMode.CHASE:
			_chase_yaw -= relative.x * orbit_sensitivity
			_chase_pitch = clampf(_chase_pitch - relative.y * orbit_sensitivity, -1.0, 0.45)
		_:
			yaw -= relative.x * orbit_sensitivity
			pitch = clampf(pitch - relative.y * orbit_sensitivity, -1.45, -0.05)
	if commit:
		_commit_current_look()
	_update_camera()


func _on_mouse_pan(relative: Vector2) -> void:
	"""MMB / L+R: pan look point (orbit/chase) or look (first-person)."""
	match view_mode:
		ViewMode.FIRST:
			_on_mouse_look(relative, true)
		_:
			_pan_ground(relative.x * pan_mouse_scale, -relative.y * pan_mouse_scale, 1.0)
			_update_camera()


func _commit_current_look() -> void:
	"""Store sticky home for peek spring / C baseline per mode."""
	_c_orbit_yaw = yaw
	_c_orbit_pitch = pitch
	_c_fp_yaw = _fp_yaw
	_c_fp_pitch = _fp_pitch
	_c_chase_yaw = _chase_yaw
	_c_chase_pitch = _chase_pitch


func _spring_to_committed(delta: float) -> void:
	"""Ease look back to sticky home after LMB peek release (keep zoom / pan)."""
	if _drag != DragKind.NONE:
		return
	var k := clampf(chase_recenter_speed * delta, 0.0, 1.0)
	match view_mode:
		ViewMode.FIRST:
			_fp_yaw = lerpf(_fp_yaw, _c_fp_yaw, k)
			_fp_pitch = lerpf(_fp_pitch, _c_fp_pitch, k)
		ViewMode.CHASE:
			_chase_yaw = lerpf(_chase_yaw, _c_chase_yaw, k)
			_chase_pitch = lerpf(_chase_pitch, _c_chase_pitch, k)
		_:
			yaw = lerpf(yaw, _c_orbit_yaw, k)
			pitch = lerpf(pitch, _c_orbit_pitch, k)


func set_drive_speed(v: float) -> void:
	_drive_speed = v


func _process(delta: float) -> void:
	"""Desktop arrow pan + peek spring; Web scenes also call pan_axes from key bridge."""
	if not OS.has_feature("web"):
		var right := 0.0
		var forward := 0.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_RIGHT):
			right += 1.0
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_LEFT):
			right -= 1.0
		if Input.is_physical_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_UP):
			forward += 1.0
		if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_DOWN):
			forward -= 1.0
		pan_axes(right, forward, delta)

	_spring_to_committed(delta)

	if _target == null:
		return
	var anchor := _target.global_position
	if view_mode != ViewMode.FIRST:
		anchor += look_offset
	if follow_lag > 0.0:
		if not _follow_init:
			_follow_pos = anchor
			_follow_init = true
		var k := clampf(follow_lag * delta, 0.0, 1.0)
		_follow_pos = _follow_pos.lerp(anchor, k)
		anchor = _follow_pos
	global_position = anchor
	_update_camera()
	if speed_fov_enabled and camera != null:
		if _base_fov <= 0.0:
			_base_fov = camera.fov
		var ratio := clampf(absf(_drive_speed) / speed_fov_ref, 0.0, 1.0)
		camera.fov = lerpf(camera.fov, _base_fov + speed_fov_boost * ratio, clampf(4.0 * delta, 0.0, 1.0))


func _update_camera() -> void:
	if camera == null:
		return
	if view_mode == ViewMode.FIRST and _target != null:
		var eye := _target.global_position + Vector3(0, 1.05, 0)
		var body_yaw := _target.rotation.y
		var look_dir: Vector3 = (
			Basis(Vector3.UP, body_yaw + _fp_yaw)
			* Basis(Vector3.RIGHT, _fp_pitch)
			* Vector3(1, 0, 0)
		).normalized()
		camera.global_position = eye + look_dir * 0.2
		camera.look_at(eye + look_dir * 8.0, Vector3.UP)
		return
	if view_mode == ViewMode.CHASE and _target != null:
		# Look at upper chest / head; sit behind MW forward (+X) by default.
		var look := _target.global_position + Vector3(0, 1.15, 0) + look_offset
		var body_yaw := _target.rotation.y
		# yaw=-PI/2 places orbit camera on -X when body_yaw=0 (behind +X forward).
		var orbit_yaw := body_yaw - PI * 0.5 + _chase_yaw
		var rot := Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, _chase_pitch)
		camera.global_position = look + rot * Vector3(0.0, 0.0, chase_distance)
		camera.look_at(look, Vector3.UP)
		return
	var rot2 := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	camera.global_position = global_position + rot2 * Vector3(0.0, 0.0, distance)
	camera.look_at(global_position, Vector3.UP)
