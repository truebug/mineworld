class_name MWInviteLink
## Fun-R: private-room invite link for the web chess lounge.
## ?room=<code> already flows into join (_resolve_room_id); this module only
## builds the share URL + clipboard/reload glue. Web-only (desktop is a no-op).

const CODE_CHARS := "abcdefghjkmnpqrstuvwxyz23456789"  # no confusing 0/o/1/l/i


static func build_button(parent: Node, on_pressed: Callable) -> Button:
	"""Floating bottom-right invite button (sits above the quick-sit one)."""
	var layer := CanvasLayer.new()
	layer.layer = 10
	parent.add_child(layer)
	var btn := Button.new()
	btn.text = MWi18n.t("邀请开黑", "Invite link")
	var f: Font = MWFonts.font() if MWFonts != null else null
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.position = Vector2(-230, -116)
	btn.size = Vector2(200, 44)
	btn.pressed.connect(on_pressed)
	layer.add_child(btn)
	return btn


static func gen_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in range(6):
		out += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
	return out


static func current_room_code() -> String:
	"""?room= from the page URL (empty in the public room / off web)."""
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(
		"(function(){try{return new URLSearchParams(location.search).get('room')||''}catch(e){return ''}})()",
		true
	)).strip_edges()


static func copy_url(code: String, jump: bool) -> void:
	"""Copy invite URL (room=<code>) to clipboard; optionally reload into it."""
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		(
			"(function(){try{"
			+ "var u=new URL(location.href);"
			+ "u.searchParams.set('room',%s);"
			+ "if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(u.href);}"
			+ "else{var t=document.createElement('textarea');t.value=u.href;document.body.appendChild(t);"
			+ "t.select();document.execCommand('copy');t.remove();}"
			+ "if(%s){location.assign(u.href);}else{history.replaceState({},'',u.pathname+u.search+u.hash);}"
			+ "}catch(e){}})()"
		) % [JSON.stringify(code), "true" if jump else "false"],
		true
	)
