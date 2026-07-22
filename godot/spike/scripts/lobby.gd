## Debug text menu (?menu=1). Default entry is 3D Hub (docs/18).
## UI strings are ASCII/English so Web export renders without a CJK font pack.
extends Control

const WORKSHOP_SCENE := "res://demo_workshop.tscn"
const CITY_SCENE := "res://demo_city.tscn"
const RACE_SCENE := "res://demo_race.tscn"
const HUB_SCENE := "res://demo_hub.tscn"


func _ready() -> void:
	"""Hide play-only shell chrome on Web (HUD / Recordings / arm sliders)."""
	MWTransition.notify_arrived()
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"if(typeof window.MW_SET_SHELL_UI==='function'){window.MW_SET_SHELL_UI(false);}",
			true
		)


func _on_workshop_pressed() -> void:
	"""Enter closed workshop (default Gateway contract)."""
	MWTransition.go(WORKSHOP_SCENE, "Workshop", "#e8873a")


func _on_city_pressed() -> void:
	"""Enter shared training yard (room=city, max 5)."""
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){try{var u=new URL(location.href);"
			+ "u.searchParams.set('room','city');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);}catch(e){}})()",
			true
		)
	MWTransition.go(CITY_SCENE, "Training", "#4aa3ff")


func _on_race_pressed() -> void:
	"""Enter shared race oval (room=race, max 6, MuJoCo)."""
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){try{var u=new URL(location.href);"
			+ "u.searchParams.set('room','race');"
			+ "history.replaceState({},'',u.pathname+u.search+u.hash);}catch(e){}})()",
			true
		)
	MWTransition.go(RACE_SCENE, "Race", "#e85a7a")


func _on_hub_pressed() -> void:
	"""Return to 3D dungeon-gate Hub."""
	MWTransition.go(HUB_SCENE, "Hub", "#8a93a3")
