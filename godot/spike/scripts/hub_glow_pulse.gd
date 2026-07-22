## Soft emission pulse on A/B/E door glow meshes (viewer-only life).
extends Node

var glows: Array = []
var _t := 0.0


func _process(delta: float) -> void:
	"""Oscillate emission energy; respect approach boost from hub.gd meta."""
	_t += delta
	var wave := 0.45 * sin(_t * 2.1)
	for item in glows:
		var mi := item as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		var base := 1.8
		if mi.has_meta("glow_base"):
			base = float(mi.get_meta("glow_base"))
		var boost := 0.0
		if mi.has_meta("approach_boost"):
			boost = float(mi.get_meta("approach_boost"))
		mat.emission_energy_multiplier = base + wave + boost
