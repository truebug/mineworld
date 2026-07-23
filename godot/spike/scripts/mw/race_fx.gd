class_name MWRaceFX
extends Node
## R4 viewer-only race effects: brake smoke + tire marks.
## Never feeds physics; attach under the level root and call
## ensure_smoke()/update() from the level script.

const TIRE_MARK_MAX := 220
const MARK_INTERVAL := 0.08

var _smoke: GPUParticles3D = null
var _tire_marks: Array[MeshInstance3D] = []
var _mark_acc := 0.0


func ensure_smoke(own: Node3D) -> void:
	if _smoke != null or own == null:
		return
	var p := GPUParticles3D.new()
	p.name = "RaceBrakeSmoke"
	p.amount = 24
	p.lifetime = 0.6
	p.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0, 0.6, 0)
	mat.scale_min = 0.15
	mat.scale_max = 0.4
	mat.color = Color(0.75, 0.75, 0.78, 0.55)
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	p.draw_pass_1 = quad
	p.position = Vector3(-0.4, 0.12, 0)
	own.add_child(p)
	_smoke = p


func update(own: Node3D, speed: float, brake: float, steer: float, dt: float) -> void:
	var spd := absf(speed)
	var hard_brake := brake > 0.35 and spd > 4.0
	var hard_turn := absf(steer) > 0.75 and spd > 10.0
	if _smoke != null:
		_smoke.emitting = hard_brake or hard_turn
	if hard_brake or hard_turn:
		_drop_tire_mark(own, dt)


func reset() -> void:
	for mi in _tire_marks:
		if is_instance_valid(mi):
			mi.queue_free()
	_tire_marks.clear()
	_mark_acc = 0.0


func _drop_tire_mark(own: Node3D, dt: float) -> void:
	if own == null:
		return
	_mark_acc += dt
	if _mark_acc < MARK_INTERVAL:
		return
	_mark_acc = 0.0
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.22)
	quad.orientation = PlaneMesh.FACE_Y
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	mi.global_position = own.global_position + Vector3(0, 0.02, 0)
	mi.global_rotation.y = own.global_rotation.y
	_tire_marks.append(mi)
	if _tire_marks.size() > TIRE_MARK_MAX:
		var old_mi: MeshInstance3D = _tire_marks.pop_front()
		if is_instance_valid(old_mi):
			old_mi.queue_free()
