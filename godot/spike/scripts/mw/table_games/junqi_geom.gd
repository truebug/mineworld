class_name MWJunqiGeom
## ADR-010 刀2: junqi board geometry + labels (pure; chessroom.gd delegates).

const ROWS := 12
const COLS := 5

const LABEL := {
	"junqi": "旗",
	"siling": "司",
	"junzhang": "军",
	"shizhang": "师",
	"lvzhang": "旅",
	"tuanzhang": "团",
	"yingzhang": "营",
	"lianzhang": "连",
	"paizhang": "排",
	"gongbing": "工",
	"zhadan": "炸",
	"dilei": "雷",
	"?": "?",
}


static func board_size(vp: Vector2) -> Vector2:
	"""Landscape 12×5: long axis horizontal for widescreen comfort."""
	var chrome_h := 160.0
	var max_w := clampf(vp.x - 48.0, 360.0, 740.0)
	var max_h := clampf(vp.y - chrome_h, 150.0, 300.0)
	var w := max_w
	var h := w * (5.0 / 12.2)
	if h > max_h:
		h = max_h
		w = h * (12.2 / 5.0)
	return Vector2(floorf(w), floorf(h))


static func view_r(model_r: int, flip: bool) -> int:
	return (ROWS - 1 - model_r) if flip else model_r


static func model_r(view_row: int, flip: bool) -> int:
	return (ROWS - 1 - view_row) if flip else view_row
