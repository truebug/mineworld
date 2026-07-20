## Debug text menu (?menu=1). Default entry is 3D Hub (docs/18).
## UI strings are ASCII/English so Web export renders without a CJK font pack.
extends Control

const WORKSHOP_SCENE := "res://demo_workshop.tscn"
const CITY_SCENE := "res://demo_city.tscn"
const HUB_SCENE := "res://demo_hub.tscn"


func _ready() -> void:
	"""Hide play-only shell chrome on Web (HUD / Recordings / arm sliders)."""
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(false);}",
			true
		)


func _on_workshop_pressed() -> void:
	"""Enter closed workshop (default Gateway contract)."""
	get_tree().change_scene_to_file(WORKSHOP_SCENE)


func _on_city_pressed() -> void:
	"""Enter city demo; Gateway resolves demo_city via join.level_id (docs/17)."""
	get_tree().change_scene_to_file(CITY_SCENE)


func _on_hub_pressed() -> void:
	"""Return to 3D dungeon-gate Hub."""
	get_tree().change_scene_to_file(HUB_SCENE)
