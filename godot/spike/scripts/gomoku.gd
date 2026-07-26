## Gomoku (五子棋) board state + heuristic AI. Pure logic, no scene deps.
## Board 15x15; 0=empty 1=black(player) 2=white(AI). Black moves first.
class_name Gomoku
extends RefCounted

const SIZE := 15
const EMPTY := 0
const BLACK := 1
const WHITE := 2

var cells: Array = []  ## SIZE*SIZE flat
var moves: Array = []  ## [x, y, color] history
var winner := EMPTY


func _init() -> void:
	reset()


func reset() -> void:
	cells.clear()
	cells.resize(SIZE * SIZE)
	cells.fill(EMPTY)
	moves.clear()
	winner = EMPTY


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return -1
	return int(cells[y * SIZE + x])


func place(x: int, y: int, color: int) -> bool:
	"""Place a stone; returns false when illegal. Updates winner."""
	if winner != EMPTY or at(x, y) != EMPTY:
		return false
	cells[y * SIZE + x] = color
	moves.append([x, y, color])
	if _line_len(x, y, color) >= 5:
		winner = color
	return true


func is_full() -> bool:
	return moves.size() >= SIZE * SIZE


func ai_move() -> Vector2i:
	"""White reply: best-scoring empty cell (attack biased over defense)."""
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	var jitter := RandomNumberGenerator.new()
	jitter.randomize()
	for y in SIZE:
		for x in SIZE:
			if at(x, y) != EMPTY:
				continue
			var score := (
				_cell_score(x, y, WHITE) * 1.05
				+ _cell_score(x, y, BLACK)
				+ jitter.randf() * 3.0
			)
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	return best


func _line_len(x: int, y: int, color: int) -> int:
	"""Longest run through (x,y) assuming color sits there."""
	var longest := 1
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var n := 1
		for sign in [1, -1]:
			var cx: int = x + d.x * sign
			var cy: int = y + d.y * sign
			while at(cx, cy) == color:
				n += 1
				cx += d.x * sign
				cy += d.y * sign
		longest = maxi(longest, n)
	return longest


func _cell_score(x: int, y: int, color: int) -> float:
	"""Threat value of placing color at empty (x,y), summed over 4 axes."""
	var total := 0.0
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var n := 1
		var open := 0
		for sign in [1, -1]:
			var cx: int = x + d.x * sign
			var cy: int = y + d.y * sign
			while at(cx, cy) == color:
				n += 1
				cx += d.x * sign
				cy += d.y * sign
			if at(cx, cy) == EMPTY:
				open += 1
		total += _pattern_score(n, open)
	return total


func _pattern_score(run: int, open_ends: int) -> float:
	if run >= 5:
		return 10000000.0
	if open_ends == 0:
		return 0.0
	match run:
		4:
			return 1000000.0 if open_ends == 2 else 120000.0
		3:
			return 9000.0 if open_ends == 2 else 1200.0
		2:
			return 320.0 if open_ends == 2 else 60.0
		_:
			return 4.0 if open_ends == 2 else 1.0
