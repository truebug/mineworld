## ASCII minimap for Hub: hall outline + player/other dots.
extends Control

## MW half-extents (must match gateway hub bounds / dress).
@export var half_x := 18.5
@export var half_y := 14.5

var _points: Array = [] ## [{x,y,self}]


func set_actors(actors: Array) -> void:
	"""actors: array of {x:float, y:float, is_self:bool}."""
	_points = actors
	queue_redraw()


func _draw() -> void:
	"""Draw framed map in local rect."""
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	var pad := 10.0
	var inner := r.grow(-pad)
	draw_rect(inner, Color(0.08, 0.12, 0.18, 0.85), true)
	draw_rect(inner, Color(0.35, 0.7, 0.95, 0.9), false, 2.0)
	# Crosshair at origin.
	var cx := inner.position.x + inner.size.x * 0.5
	var cy := inner.position.y + inner.size.y * 0.5
	draw_line(Vector2(cx - 6, cy), Vector2(cx + 6, cy), Color(0.4, 0.55, 0.7, 0.5), 1.0)
	draw_line(Vector2(cx, cy - 6), Vector2(cx, cy + 6), Color(0.4, 0.55, 0.7, 0.5), 1.0)
	var sx := inner.size.x / (half_x * 2.0)
	var sy := inner.size.y / (half_y * 2.0)
	# Door marks (E workshop, W training, N design).
	_draw_door(inner, sx, sy, half_x, 0.0, Color(1.0, 0.55, 0.15))
	_draw_door(inner, sx, sy, -half_x, 0.0, Color(0.3, 0.7, 1.0))
	_draw_door(inner, sx, sy, 0.0, -half_y, Color(0.85, 0.85, 0.55))
	# Mezzanine footprint (south half) + elevator tick — display-only.
	var mz_a := _map_pt(inner, sx, sy, -half_x + 1.0, 1.2)
	var mz_b := _map_pt(inner, sx, sy, half_x - 1.0, half_y - 0.8)
	var mz := Rect2(
		Vector2(minf(mz_a.x, mz_b.x), minf(mz_a.y, mz_b.y)),
		Vector2(absf(mz_b.x - mz_a.x), absf(mz_b.y - mz_a.y)),
	)
	draw_rect(mz, Color(0.45, 0.65, 0.85, 0.18), true)
	draw_rect(mz, Color(0.55, 0.75, 0.95, 0.45), false, 1.0)
	_draw_door(inner, sx, sy, 13.5, 12.5, Color(0.4, 0.9, 1.0))
	for p in _points:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var mx := float(p.get("x", 0.0))
		var my := float(p.get("y", 0.0))
		var is_self := bool(p.get("is_self", false))
		var local := Vector2(
			inner.position.x + (mx + half_x) * sx,
			inner.position.y + (half_y - my) * sy,
		)
		var col := Color(1.0, 0.85, 0.25) if is_self else Color(0.45, 0.85, 1.0)
		var rad := 5.0 if is_self else 4.0
		draw_circle(local, rad, col)
		if is_self:
			draw_arc(local, rad + 2.0, 0.0, TAU, 24, Color(1, 1, 1, 0.7), 1.2)


func _draw_door(inner: Rect2, sx: float, sy: float, mx: float, my: float, col: Color) -> void:
	"""Small door tick on the perimeter."""
	var local := _map_pt(inner, sx, sy, mx, my)
	draw_rect(Rect2(local - Vector2(4, 4), Vector2(8, 8)), col, true)


func _map_pt(inner: Rect2, sx: float, sy: float, mx: float, my: float) -> Vector2:
	"""MW (x,y) → minimap pixel."""
	return Vector2(
		inner.position.x + (mx + half_x) * sx,
		inner.position.y + (half_y - my) * sy,
	)
