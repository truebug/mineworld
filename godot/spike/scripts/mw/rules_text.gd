class_name MWRulesText
## ADR-010 刀1: per-game concise rules (SSOT summaries, zh/en).

const RULES := {
	"gomoku": {"zh": "五子棋 · 双方轮流落子\n横竖斜先连成五子者胜", "en": "Gomoku: take turns placing stones\nfirst to five in a row (any direction) wins"},
	"checkers": {"zh": "跳棋 · 每步走一格，或隔子连跳\n先把自己的棋子全部跳进对角营者胜", "en": "Halma: move one step or hop chains\nfirst to fill the far camp wins"},
	"blackjack": {"zh": "21 点 · 要牌 (H) 逼近 21，停牌 (S) 定局\n超过 21 爆牌即负 · 庄家 17 点停\n首手 21 = Blackjack 直接胜 · 点数相同为平局", "en": "Blackjack: Hit (H) toward 21, Stand (S) to lock\nbust over 21 loses · dealer stands on 17\nnatural 21 wins · equal points push"},
	"wudui": {"zh": "五对 · 54 张含双王 · 各发 10 张，先手 11 张\n凑成五对即胜 · 先手首弃即成五对 = 天和\n先手回合必弃一张散牌，再抓 1 张\n后手可吃牌（凑对后弃一张）或过牌（抓 1 再弃 1）\n可认输 · 对局中离座判负", "en": "WuDui: 54 cards incl. jokers · 10 each, first gets 11\nfive pairs win · first discard leaving 5 pairs = Tianhe\nfirst must discard an unmatched card, then draws one\nsecond may eat (pair + discard) or pass (draw + discard)\nresign allowed · leaving mid-game forfeits"},
	"junqi": {"zh": "12×5 · 行营免战 · 铁路工兵可拐弯\n军旗必在大本营 · 地雷仅后两行 · 炸弹不上底线\n公路一步 · 铁路直线（工兵可拐）· 行营离营限一格\n任意己子走进对方军旗即胜（无需清雷）\n司令阵亡→公开该方军旗位置", "en": "12x5 · camps safe · engineer turns on rail\nFlag in HQ · mines last 2 rows · bombs not on back row\nRoad 1-step · rail straight (engineer bends)\nany piece onto the enemy flag wins (no mine-clear)\ncommander lost → reveal that side's flag"},
}


static func for_game(game: String) -> Dictionary:
	return RULES.get(game, {"zh": "", "en": ""})
