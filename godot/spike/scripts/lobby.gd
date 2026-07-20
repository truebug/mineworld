## Test-field / game-lobby entry (viewer-only). No WS join until a level is chosen.
extends Control

const WORKSHOP_SCENE := "res://demo_workshop.tscn"
const CITY_SCENE := "res://demo_city.tscn"


func _ready() -> void:
	"""Focus UI; Esc is unused here (levels handle Esc→lobby later)."""
	pass


func _on_workshop_pressed() -> void:
	"""Enter closed workshop (default Gateway contract)."""
	get_tree().change_scene_to_file(WORKSHOP_SCENE)


func _on_city_pressed() -> void:
	"""Enter city demo; Gateway must serve demo_city contract (see docs/17)."""
	get_tree().change_scene_to_file(CITY_SCENE)
