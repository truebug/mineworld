## Soft chat bubble over Hub NPCs: fade-rotate lines, optional dwell-only mode.
extends Node3D

const FADE_S := 0.28
const HOLD_S := 4.2
const PANEL_SIZE := Vector2(1.35, 0.55)

var lines: Array = [] ## String
var hold_s := HOLD_S
## When true, only draw while parent sets visible_wanted (patrol dwell).
var dwell_only := false
var visible_wanted := true
## Player plaza chat: show once then hide (no rotate loop).
var one_shot := false

var _idx := 0
var _phase := "hold" ## hold | out | in
var _t := 0.0
var _label: Label3D
var _panel: MeshInstance3D
var _mat: StandardMaterial3D
var _accent := Color(0.95, 0.92, 0.82, 1.0)


func setup(line_list: Array, accent: Color = Color(0.95, 0.9, 0.75), start_offset: float = 0.0) -> void:
	"""Attach styled panel + label; stagger start_offset so NPCs don't sync-speak."""
	one_shot = false
	lines = []
	for item in line_list:
		var s := str(item).strip_edges()
		if s != "":
			lines.append(s)
	_accent = accent
	_t = -start_offset
	_idx = 0
	_phase = "hold"
	_ensure_nodes()
	_apply_line(0.0 if lines.is_empty() else 1.0)
	visible = not dwell_only and not lines.is_empty()


func flash(text: String, accent: Color = Color(0.95, 0.9, 0.75), hold: float = 4.5) -> void:
	"""One-shot player chat bubble; high-contrast text (ignores dark accents)."""
	var s := text.strip_edges()
	if s == "":
		return
	one_shot = true
	hold_s = hold
	dwell_only = false
	visible_wanted = true
	lines = [s]
	# Readable on bright hangar / outdoor: near-white glyph + dark plate.
	_accent = Color(0.98, 0.99, 1.0, 1.0)
	_t = 0.0
	_idx = 0
	_phase = "hold"
	_ensure_nodes()
	if _label != null:
		_label.outline_size = 14
		_label.outline_modulate = Color(0.02, 0.03, 0.05, 1.0)
		_label.font_size = 30
	_apply_line(1.0)
	visible = true


func set_dwell_active(on: bool) -> void:
	"""Patrol: show bubble only while paused at a stop."""
	visible_wanted = on
	if not dwell_only:
		return
	if on and not lines.is_empty():
		visible = true
		_phase = "in"
		_t = 0.0
		_apply_line(0.0)
	else:
		visible = false


func _ensure_nodes() -> void:
	"""Build soft panel + Label3D once."""
	if _panel != null:
		return
	_panel = MeshInstance3D.new()
	_panel.name = "BubblePanel"
	var quad := QuadMesh.new()
	quad.size = PANEL_SIZE
	_panel.mesh = quad
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.1, 0.14, 0.78)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.roughness = 0.85
	_mat.metallic = 0.0
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_panel.material_override = _mat
	add_child(_panel)
	_panel.position = Vector3(0, 0, 0)

	_label = Label3D.new()
	_label.name = "BubbleText"
	MWFonts.apply_label3d(_label)
	_label.font_size = 28
	_label.outline_size = 8
	_label.outline_modulate = Color(0.05, 0.06, 0.08, 0.95)
	_label.pixel_size = 0.0085
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.modulate = _accent
	add_child(_label)
	_label.position = Vector3(0, 0, 0.02)


func _apply_line(alpha: float) -> void:
	"""Set current line and shared alpha on panel + text; slight scale pop."""
	_ensure_nodes()
	var text := ""
	if not lines.is_empty():
		text = str(lines[_idx % lines.size()])
	_label.text = text
	var a := clampf(alpha, 0.0, 1.0)
	if one_shot:
		_label.modulate = Color(1.0, 1.0, 1.0, a)
		# Player chat: no dark plate (it clipped long lines); outline carries readability.
		_panel.visible = false
	else:
		_panel.visible = true
		_label.modulate = Color(_accent.r, _accent.g, _accent.b, a)
		_mat.albedo_color = Color(0.08, 0.1, 0.14, 0.78 * a)
	var pop := 0.92 + 0.08 * a
	scale = Vector3(pop, pop, pop)
	if a > 0.85:
		_mat.emission_enabled = true
		if one_shot:
			_mat.emission = Color(0.15, 0.2, 0.28)
			_mat.emission_energy_multiplier = 0.2
		else:
			_mat.emission = Color(_accent.r, _accent.g, _accent.b) * 0.25
			_mat.emission_energy_multiplier = 0.35
	else:
		_mat.emission_enabled = false


func _process(delta: float) -> void:
	"""Fade-hold-rotate through lines."""
	if lines.is_empty():
		visible = false
		return
	if dwell_only and not visible_wanted:
		visible = false
		return
	if dwell_only:
		visible = true
	_t += delta
	match _phase:
		"hold":
			_apply_line(1.0)
			if _t >= hold_s:
				if one_shot or lines.size() <= 1 and not dwell_only:
					if one_shot:
						_phase = "out"
						_t = 0.0
						return
					_t = 0.0
					return
				_phase = "out"
				_t = 0.0
		"out":
			var k := 1.0 - clampf(_t / FADE_S, 0.0, 1.0)
			_apply_line(k)
			if _t >= FADE_S:
				if one_shot:
					visible = false
					lines.clear()
					one_shot = false
					return
				_idx = (_idx + 1) % lines.size()
				_phase = "in"
				_t = 0.0
				_apply_line(0.0)
		"in":
			var k2 := clampf(_t / FADE_S, 0.0, 1.0)
			_apply_line(k2)
			if _t >= FADE_S:
				_phase = "hold"
				_t = 0.0
				_apply_line(1.0)
