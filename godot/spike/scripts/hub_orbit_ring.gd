## Fun-H: rotating holo-ring chandelier above the plaza (Hub atmosphere decor).
## Outer cyan ring spins slowly, inner magenta arc counter-rotates with tilt,
## satellites orbit as children; gentle bob. Viewer-only.
extends Node3D

const RING_R := 5.2
const INNER_R := 3.1
const BOB_AMP := 0.35
const BOB_HZ := 0.12
const SPIN_DPS := 6.0
const INNER_SPIN_DPS := -14.0

var _ring_a: Node3D = null
var _ring_b: MeshInstance3D = null
var _base_y := 0.0
var _t := 0.0


func _ready() -> void:
	_base_y = position.y
	var cyan := _holo_mat(Color(0.35, 0.85, 1.0), 1.6)
	var magenta := _holo_mat(Color(1.0, 0.45, 0.85), 1.3)
	_ring_a = Node3D.new()
	_ring_a.name = "RingSpin"
	add_child(_ring_a)
	var torus := MeshInstance3D.new()
	torus.name = "OuterRing"
	var tm := TorusMesh.new()
	tm.inner_radius = RING_R - 0.09
	tm.outer_radius = RING_R
	tm.rings = 64
	tm.ring_segments = 8
	torus.mesh = tm
	torus.material_override = cyan
	_ring_a.add_child(torus)
	# Satellites ride the outer ring spin.
	for i in range(3):
		var sat := MeshInstance3D.new()
		sat.name = "Sat%d" % i
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sat.mesh = sm
		sat.material_override = _holo_mat(Color(1.0, 0.8, 0.4), 2.2)
		var a := TAU * float(i) / 3.0
		sat.position = Vector3(cos(a) * RING_R, 0.0, sin(a) * RING_R)
		_ring_a.add_child(sat)
	_ring_b = MeshInstance3D.new()
	_ring_b.name = "InnerRing"
	var im := TorusMesh.new()
	im.inner_radius = INNER_R - 0.06
	im.outer_radius = INNER_R
	im.rings = 48
	im.ring_segments = 6
	_ring_b.mesh = im
	_ring_b.material_override = magenta
	_ring_b.rotation_degrees.x = 18.0
	add_child(_ring_b)


func _process(delta: float) -> void:
	_t += delta
	_ring_a.rotation_degrees.y = fmod(_ring_a.rotation_degrees.y + SPIN_DPS * delta, 360.0)
	_ring_b.rotation_degrees.y = fmod(
		_ring_b.rotation_degrees.y + INNER_SPIN_DPS * delta, 360.0
	)
	position.y = _base_y + sin(_t * TAU * BOB_HZ) * BOB_AMP


func _holo_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
