class_name MWTutorial
extends CanvasLayer
## P0-2 (docs/37): data-driven control card overlay for every level.
## First entry per level auto-shows; Esc/click closes; H re-opens.
## "Seen" flag persists in localStorage on web, in-memory elsewhere.

const CARDS := {
	"demo_hub": {
		"title": "母港 · Hangar Core",
		"goal": "走近门 A 工坊 / B 训练场 / E 竞速，回车进聊天。",
		"keys": [["W A S D", "移动"], ["鼠标", "视角"], ["F", "交互 / 进门"], ["Enter", "聊天"], ["H", "本帮助"]],
	},
	"demo_workshop": {
		"title": "工坊 · 抓放训练",
		"goal": "夹起小料块，放到工作台橙区并张开夹爪。",
		"keys": [["W A S D", "移动"], ["鼠标", "视角"], ["右下滑杆", "臂 / 夹爪"], ["R", "重置"], ["H", "本帮助"]],
	},
	"demo_city": {
		"title": "训练场 · 街区",
		"goal": "开到目标区完成训练；多人共享房间。",
		"keys": [["W A S D", "移动"], ["鼠标", "视角"], ["R", "重置"], ["H", "本帮助"]],
	},
	"demo_race": {
		"title": "竞速 · 计时榜",
		"goal": "过检查点冲线计时；同房 ≥2 人自动开赛。",
		"keys": [["W / S", "油门 / 刹车"], ["X", "倒车"], ["Q / E", "转向"], ["G", "幽灵挑战"], ["H", "本帮助"]],
	},
	"demo_chessroom": {
		"title": "棋牌室",
		"goal": "走近桌子点击入座；满桌可旁观喝彩。",
		"keys": [["W A S D", "移动"], ["鼠标点击", "入座 / 落子"], ["J", "快速入座"], ["1-6", "表情"], ["H / S", "21点要牌/停牌"], ["H", "本帮助"]],
	},
}

static var _seen_session: Dictionary = {}

var _level_id := ""
var _panel: PanelContainer


static func attach(scene_root: Node, level_id: String) -> void:
	"""Attach tutorial overlay; auto-shows on first entry for this level."""
	if not CARDS.has(level_id):
		return
	var tut := MWTutorial.new()
	tut._level_id = level_id
	tut.layer = 90
	scene_root.add_child(tut)


static func _already_seen(level_id: String) -> bool:
	if OS.has_feature("web"):
		var v := str(JavaScriptBridge.eval(
			"(function(){try{return localStorage.getItem('mw_tut_seen_%s')||''}catch(e){return ''}})()" % level_id,
			true
		))
		return v == "1"
	return _seen_session.has(level_id)


static func _mark_seen(level_id: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			"(function(){try{localStorage.setItem('mw_tut_seen_%s','1')}catch(e){}})()" % level_id,
			true
		)
	else:
		_seen_session[level_id] = true


func _ready() -> void:
	var card: Dictionary = CARDS[_level_id]
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(380, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.11, 0.92)
	style.border_color = Color(0.29, 0.64, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18.0)
	_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = str(card["title"])
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	var goal := Label.new()
	goal.text = str(card["goal"])
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	box.add_child(goal)
	var sep := HSeparator.new()
	box.add_child(sep)
	for row in card["keys"]:
		var line := Label.new()
		line.text = "%-10s  %s" % [row[0], row[1]]
		line.add_theme_font_size_override("font_size", 15)
		box.add_child(line)
	var hint := Label.new()
	hint.text = "Esc / 点击关闭 · H 重看"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	box.add_child(hint)
	add_child(_panel)
	_panel.gui_input.connect(_on_panel_input)
	if not MWTutorial._already_seen(_level_id):
		show_card()
	else:
		_panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H or event.physical_keycode == KEY_H:
			if _panel.visible:
				_close()
			else:
				show_card()
		elif event.keycode == KEY_ESCAPE and _panel.visible:
			_close()


func show_card() -> void:
	_panel.show()
	MWTutorial._mark_seen(_level_id)


func _close() -> void:
	_panel.hide()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()
