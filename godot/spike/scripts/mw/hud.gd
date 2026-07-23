class_name MWHud
extends Node
## HUD surface layer extracted from main.gd: mission banner + beep,
## ASCII channel bars, web DOM push, desktop layout fixup.
## The big status-text composer stays in the level script; it calls
## push_web_hud()/bar()/steer_bar() from here.

var _banner_layer: CanvasLayer
var _banner_title: Label
var _banner_sub: Label
var _sfx: AudioStreamPlayer


static func bar(v: float, width: int = 10) -> String:
	"""ASCII fill bar for 0..1 channel."""
	var n := int(round(clampf(v, 0.0, 1.0) * width))
	return "[" + "#".repeat(n) + "-".repeat(width - n) + "]"


static func steer_bar(v: float) -> String:
	"""ASCII steer indicator: L <<0>> R around center."""
	var cells := ["L", "<", "<", "<", "0", ">", ">", ">", "R"]
	var idx := int(round((clampf(v, -1.0, 1.0) + 1.0) * 4.0))
	var out := ""
	for i in cells.size():
		out += ("(%s)" % cells[i]) if i == idx else cells[i]
	return out


static func apply_layout(host: Node) -> void:
	"""Desktop: top-left shrink panel. Web: remove Godot Hud (DOM #mw-hud only)."""
	var hud := host.get_node_or_null("Hud") as CanvasLayer
	if OS.has_feature("web"):
		# Free Godot Control HUD entirely — visible=false still left a clipped panel on Web.
		if hud != null:
			hud.queue_free()
		return
	if hud != null:
		hud.visible = true
	var margin := host.get_node_or_null("Hud/Margin") as MarginContainer
	if margin != null:
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := host.get_node_or_null("Hud/Margin/PanelContainer") as PanelContainer
	if panel == null:
		panel = host.get_node_or_null("Hud/Root/PanelContainer") as PanelContainer
	if panel == null:
		panel = host.get_node_or_null("Hud/PanelContainer") as PanelContainer
	if panel == null:
		return
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size = Vector2(480, 0)


func ensure_banner() -> void:
	"""Build a centered SUCCESS/FAIL banner (desktop CanvasLayer; web uses DOM)."""
	if _banner_layer != null:
		return
	_banner_layer = CanvasLayer.new()
	_banner_layer.name = "MissionBanner"
	_banner_layer.layer = 100
	_banner_layer.visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_title = Label.new()
	_banner_title.text = "SUCCESS"
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 96)
	_banner_title.add_theme_color_override("font_color", Color(0.36, 1.0, 0.54))
	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 20)
	_banner_sub.add_theme_color_override("font_color", Color(0.95, 0.96, 0.97))
	col.add_child(_banner_title)
	col.add_child(_banner_sub)
	center.add_child(col)
	root.add_child(dim)
	root.add_child(center)
	_banner_layer.add_child(root)
	add_child(_banner_layer)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "MissionSfx"
	add_child(_sfx)


func push_web_hud(text: String) -> void:
	"""Web-only: push HUD text via shell.html MW_SET_HUD (click-to-collapse)."""
	var payload := JSON.stringify(text)
	JavaScriptBridge.eval(
		"(function(t){"
		+ "if(typeof window.MW_SET_HUD==='function'){window.MW_SET_HUD(t);return;}"
		+ "var el=document.getElementById('mw-hud');"
		+ "if(!el){el=document.createElement('pre');el.id='mw-hud';document.body.appendChild(el);}"
		+ "el.textContent=t;"
		+ "})(%s);" % payload,
		true
	)


func show_mission_result(ok: bool, detail: String, points: int = 0, session_id: String = "") -> void:
	"""Show big SUCCESS/FAIL + short beep (desktop Label / web DOM)."""
	var title := "SUCCESS" if ok else "FAIL"
	var sub := detail if detail != "" else ("reach zone OK" if ok else "objective failed")
	if ok and points > 0:
		sub = "%s · +%d pts" % [sub, points]
	if ok:
		# Data flywheel made visible: this run is training data.
		var sid_short := session_id.substr(0, 8) if session_id != "" else "local"
		sub += "\n本局遥操数据已入库 #%s · 将用于训练机甲 AI" % sid_short
	if OS.has_feature("web"):
		var payload := JSON.stringify({
			"ok": ok,
			"title": title,
			"sub": sub,
			"points": points,
			"me_href": "/portal/me.html",
		})
		JavaScriptBridge.eval(
			"(function(p){var el=document.getElementById('mw-success');"
			+ "if(!el){return;}el.classList.toggle('fail',!p.ok);"
			+ "el.classList.add('show');"
			+ "var t=el.querySelector('.mw-title');if(t){t.textContent=p.title;}"
			+ "var s=el.querySelector('.mw-sub');if(s){s.textContent=p.sub;}"
			+ "var a=el.querySelector('.mw-me');if(a){"
			+ "if(p.ok&&p.points>0){a.style.display='inline';a.href=p.me_href||'/portal/me.html';}"
			+ "else{a.style.display='none';}}"
			+ "try{var Ctx=window.AudioContext||window.webkitAudioContext;var c=new Ctx();"
			+ "var o=c.createOscillator();var g=c.createGain();"
			+ "o.type='sine';o.frequency.value=p.ok?880:220;"
			+ "g.gain.setValueAtTime(0.18,c.currentTime);"
			+ "g.gain.exponentialRampToValueAtTime(0.001,c.currentTime+0.45);"
			+ "o.connect(g);g.connect(c.destination);o.start();o.stop(c.currentTime+0.45);}"
			+ "catch(e){}})(%s);" % payload,
			true
		)
		return
	if _banner_title != null:
		_banner_title.text = title
		_banner_title.add_theme_color_override(
			"font_color",
			Color(0.36, 1.0, 0.54) if ok else Color(1.0, 0.42, 0.42),
		)
	if _banner_sub != null:
		_banner_sub.text = sub
	if _banner_layer != null:
		_banner_layer.visible = true
	_play_mission_beep(ok)


func _play_mission_beep(ok: bool) -> void:
	"""Play a short generated beep without shipping audio assets."""
	if _sfx == null:
		return
	var sample_hz := 22050
	var duration := 0.4
	var n := int(sample_hz * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var freq := 880.0 if ok else 220.0
	for i in n:
		var t := float(i) / float(sample_hz)
		var env := maxf(0.0, 1.0 - t / duration)
		var sample := int(sin(t * TAU * freq) * 0.28 * env * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_hz
	stream.data = data
	_sfx.stream = stream
	_sfx.play()
