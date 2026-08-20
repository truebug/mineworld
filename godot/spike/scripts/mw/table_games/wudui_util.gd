class_name MWWuduiUtil
## ADR-010 刀1: pure wudui helpers extracted from chessroom.gd (no scene state).
## Card dims mirror chessroom's _BJ_CARD_*; keep in sync if those change.

const CARD_W := 64.0
const CARD_H := 92.0
const GAP := 10.0


static func rank(card: String) -> String:
	return "JOKER" if card.begins_with("JOKER") else card.left(card.length() - 1)


static func can_eat(d: Dictionary) -> bool:
	var pile: Array = d.get("discard_pile", [])
	if pile.is_empty():
		return false
	var top := str(pile[-1])
	var hand: Array = d.get("red_cards", [])
	var count := 0
	for c in hand:
		if rank(str(c)) == rank(top):
			count += 1
	return count % 2 == 1


static func card_w(count: int, area: Vector2) -> float:
	"""Shrink card width when the hand can't fit the felt (11 cards ≈ 804px)."""
	var avail := area.x - 16.0
	var need := count * CARD_W + maxi(count - 1, 0) * 4.0
	if need <= avail:
		return CARD_W
	return maxf((avail - maxi(count - 1, 0) * 4.0) / count, 40.0)


static func gap(count: int, area: Vector2) -> float:
	var avail := area.x - 16.0
	var need := count * CARD_W + maxi(count - 1, 0) * GAP
	if need <= avail:
		return GAP
	return 4.0


static func row_h(hand: Array, area: Vector2) -> float:
	var w := card_w(hand.size(), area)
	return w * CARD_H / CARD_W


static func hand_origin(count: int, y: float, area: Vector2) -> Vector2:
	var total := count * card_w(count, area) + maxi(count - 1, 0) * gap(count, area)
	return Vector2(maxf((area.x - total) * 0.5, 8.0), y)


static func card_pos(index: int, count: int, y: float, area: Vector2) -> Vector2:
	return hand_origin(count, y, area) + Vector2(index * (card_w(count, area) + gap(count, area)), 0)


static func grouped_hand(hand: Array) -> Dictionary:
	"""Split hand into pair cards (even rank count) and scattered (odd count)."""
	var counts := rank_counts(hand)
	var pairs: Array = []
	var scattered: Array = []
	for c in hand:
		if int(counts.get(rank(str(c)), 0)) % 2 == 0:
			pairs.append(c)
		else:
			scattered.append(c)
	return {"pairs": pairs, "scattered": scattered}


static func hand_rects(hand: Array, area: Vector2, y: float) -> Array:
	"""Slot rects for one hand row: pairs left, scattered right (绘制/热区同函数)."""
	var group := grouped_hand(hand)
	var ordered: Array = group["pairs"] + group["scattered"]
	var count := ordered.size()
	if count == 0:
		return []
	var w := card_w(count, area)
	var h := w * CARD_H / CARD_W
	var g := gap(count, area)
	var total := count * w + maxi(count - 1, 0) * g
	var origin := Vector2(maxf((area.x - total) * 0.5, 8.0), y)
	var sep := (group["pairs"] as Array).size()
	var rects: Array = []
	for i in count:
		rects.append({
			"card": str(ordered[i]),
			"rect": Rect2(origin + Vector2(i * (w + g), 0), Vector2(w, h)),
			"scattered": i >= sep,
		})
	return rects


static func default_discard(d: Dictionary, hand: Array, opponent: Array) -> String:
	"""Scattered card least likely to be paired by the opponent."""
	var scattered: Array = grouped_hand(hand)["scattered"]
	if scattered.is_empty():
		return ""
	var remaining: Dictionary = d.get("deck_remaining", {}) as Dictionary
	var known: Array = d.get("black_cards", []) + d.get("red_cards", []) + d.get("discard_pile", [])
	var best := ""
	var best_risk := INF
	for c in scattered:
		var card := str(c)
		var r := rank(card)
		var opp_copies := 0
		for o in opponent:
			if rank(str(o)) == r:
				opp_copies += 1
		var deck_copies := int(remaining.get(r, -1))
		if deck_copies < 0:
			var seen := 0
			for k in known:
				if rank(str(k)) == r:
					seen += 1
			deck_copies = maxi((2 if r == "JOKER" else 4) - seen, 0)
		var risk := float(deck_copies) + (1000.0 if opp_copies % 2 == 1 else 0.0)
		if risk < best_risk:
			best_risk = risk
			best = card
	return best


static func rank_counts(hand: Array) -> Dictionary:
	var counts := {}
	for c in hand:
		var r := rank(str(c))
		counts[r] = int(counts.get(r, 0)) + 1
	return counts


static func side_rects(hand: Array, area: Vector2, side: String) -> Array:
	var y := area.y - row_h(hand, area) - 14.0 if side == "black" else 14.0
	return hand_rects(hand, area, y)


static func completed_pair_cards(prev_hand: Array, hand: Array) -> Array:
	"""Cards whose rank just went odd→even (a new pair formed)."""
	var prev_counts := rank_counts(prev_hand)
	var new_counts := rank_counts(hand)
	var out: Array = []
	for r in new_counts:
		if int(new_counts[r]) >= 2 and int(new_counts[r]) % 2 == 0 and int(prev_counts.get(r, 0)) % 2 == 1:
			for c in hand:
				if rank(str(c)) == r:
					out.append(c)
	return out
