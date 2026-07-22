## Soft emission pulse on A/B door glow meshes (viewer-only life).
extends Node

var glows: Array = []
var _t := 0.0


func _process(delta: float) -> void:
	"""Oscillate emission energy on attached MeshInstance3D materials."""
	_t += delta
	var k := 1.55 + 0.45 * sin(_t * 2.1)
	for item in glows:
		var mi := item as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = k
