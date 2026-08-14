class_name MWEmotes
## Fun-E: quick emote/cheer presets for the chess lounge.
## Sent through the room chat channel (bubbles + chat log already handle them).

const LIST: Array = [
	## No emoji: web export has no system-font fallback (would render tofu).
	{"zh": "好棋！", "en": "Nice move!"},
	{"zh": "精彩！", "en": "Brilliant!"},
	{"zh": "哇哦", "en": "Wow!"},
	{"zh": "哈哈", "en": "Haha"},
	{"zh": "加油！", "en": "Go go!"},
	{"zh": "承让", "en": "GG"},
]


static func text_at(i: int) -> String:
	"""i18n emote text by index (empty when out of range)."""
	if i < 0 or i >= LIST.size():
		return ""
	var e: Dictionary = LIST[i]
	return MWi18n.t(str(e.get("zh", "")), str(e.get("en", "")))


static func build_row(parent: Container, on_pick: Callable) -> HBoxContainer:
	"""Emote button row for the board panel; on_pick(text) per press."""
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for i in range(LIST.size()):
		var btn := Button.new()
		btn.text = text_at(i)
		btn.add_theme_font_size_override("font_size", 14)
		var f: Font = MWFonts.font() if MWFonts != null else null
		if f != null:
			btn.add_theme_font_override("font", f)
		btn.pressed.connect(on_pick.bind(text_at(i)))
		row.add_child(btn)
	return row
