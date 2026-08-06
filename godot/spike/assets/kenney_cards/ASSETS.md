# Kenney Playing Cards Pack (subset — large)

| 字段 | 值 |
|------|-----|
| Source | https://kenney.nl/assets/playing-cards-pack |
| License | CC0 1.0（见 `License.txt`） |
| Files | `PNG/Cards (large)/` 全部 57 张（54 牌面 + `card_back` + `card_empty`）+ `License.txt` |
| Role | 棋牌室 21 点 / 五对 牌面贴图（`chessroom.gd` `_draw_bj_card` 贴图路径） |

## 文件名映射（wire card → texture）

- `AS`/`10H`/`Q♣` 等 → `card_<suit>_<rank>.png`（suit ∈ spades/hearts/diamonds/clubs；rank 02–10, A, J, Q, K）
- `JOKER` → `card_joker_black.png`
- `??`（牌背）→ `card_back.png`
