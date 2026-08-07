## Fun-H: slow day/night mood cycle for the Hub.
## Drives space-sky shader tint + sun/ambient drift (deep night → nebula dawn
## → warm day → dusk). Viewer-only; no Gateway involvement.
extends Node

const PERIOD_S := 150.0
## Sky shader uniform lerps (night ↔ day).
const NEBULA_A_NIGHT := Color(0.12, 0.05, 0.22)
const NEBULA_A_DAY := Color(0.10, 0.16, 0.30)
const NEBULA_B_NIGHT := Color(0.04, 0.10, 0.28)
const NEBULA_B_DAY := Color(0.16, 0.22, 0.34)

var _t := 0.0
var _env: Environment = null
var _sky_mat: ShaderMaterial = null
var _sun: DirectionalLight3D = null
var _key: OmniLight3D = null


func setup(env: Environment, sun: DirectionalLight3D, key: OmniLight3D) -> void:
	_env = env
	if _env != null and _env.sky != null:
		_sky_mat = _env.sky.sky_material as ShaderMaterial
	_sun = sun
	_key = key


func _process(delta: float) -> void:
	_t = fmod(_t + delta, PERIOD_S)
	var p: float = _t / PERIOD_S
	## day factor: 0 at deep night, 1 at warm midday (smooth sine arc).
	var day: float = 0.5 + 0.5 * sin(TAU * p - PI * 0.5)
	## dawn/dusk warmth peaks at the transitions.
	var edge: float = 1.0 - abs(2.0 * day - 1.0)
	if _sun != null:
		_sun.light_energy = lerpf(0.25, 1.1, day)
		_sun.light_color = Color(
			1.0,
			lerpf(0.55, 0.95, day) + 0.08 * edge,
			lerpf(0.35, 0.85, day)
		)
		_sun.rotation_degrees.x = lerpf(-18.0, -58.0, day)
		_sun.rotation_degrees.y = lerpf(8.0, 48.0, p)
	if _env != null:
		_env.ambient_light_energy = lerpf(0.18, 0.42, day)
		_env.ambient_light_color = Color(
			lerpf(0.4, 0.6, day),
			lerpf(0.36, 0.48, day),
			lerpf(0.5, 0.4, day) + 0.12 * (1.0 - day)
		)
	if _key != null:
		_key.light_energy = lerpf(3.6, 2.6, day)
	if _sky_mat != null:
		_sky_mat.set_shader_parameter("star_brightness", lerpf(2.2, 0.9, day))
		_sky_mat.set_shader_parameter("nebula_a", NEBULA_A_NIGHT.lerp(NEBULA_A_DAY, day))
		_sky_mat.set_shader_parameter("nebula_b", NEBULA_B_NIGHT.lerp(NEBULA_B_DAY, day))
