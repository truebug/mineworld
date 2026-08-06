# 29 · 五对（WuDui）双人纸牌桌 + 棋牌室扩容 · 实施结果报告

| 字段 | 值 |
|------|-----|
| **状态** | 已上线（Done） |
| **日期** | 2026-08-06 |
| **提交** | `744ca38` feat(chess): 五对 WuDui 2P table + lounge expansion |
| **部署** | `playground.dev.databall.tech` · `MW_BUILD="20260806-113133"` |
| **关联** | [09-todo.md](09-todo.md) Chess-P5 · [19-changelog.md](19-changelog.md) |

## 1. 需求摘要

- 扩大棋牌室面积，增加桌位：多放五子棋 / 21 点位置。
- 新增一张**双人**纸牌桌，玩法「五对」（54 张含双王，凑 5 对胜出）。

## 2. 五对规则（SSOT，本次定稿）

1. 54 张牌（A–K ×4 + 双王），双方各发 10 张，**先手方多发 1 张（11 张）**。
2. 先手回合：必须弃一张未配对散牌；若剩余牌恰好 5 对 = **天和**，直接胜出。弃后抓 1 张补回 11。
3. 后手回合：可**吃牌**（吃弃牌与手中散牌凑对，再弃一张散牌）或**过牌**（抓 1 张，再弃一张散牌）。
4. 任一方全手成对（5 对）即胜；可**认输**判负；对局中离座判负。

## 3. 交付内容

### Gateway 权威裁判（`gateway/wudui.py` 新增）

- `WuDuiBoard`：发牌 / 弃牌 / 吃牌 / 过牌 / 认输 / 明细；天和判定。
- 错误码：`WUDUI_NOT_TURN` / `WUDUI_BAD_CARD` / `WUDUI_NOT_UNMATCHED` / `WUDUI_NO_DISCARD` / `WUDUI_BAD_EAT` / `WUDUI_CANNOT_EAT` / `WUDUI_BAD_DISCARD`。

### Gateway 接入（`gateway/echo_server.py`）

- `_new_board_for_game("wudui")`、`ChessTable.reset_board` 自动 deal、`to_detail`（含 `turn_sid`）。
- 双人入座：先坐者为黑等第二位，第二位坐即发牌。
- 新 cmd：`card_discard` / `card_eat` / `card_pass`；错座位/错回合回 `chess_reject`。
- `chess_resign` wudui 分支 + `_chess_free_session` 离座判负分支。

### 契约与场景

- `examples/contracts/demo_chessroom.json`：新增 `table_5`（五子棋 丙桌）、`table_6`（五对 双人桌）；bounds 扩到 `half_x=16 / half_y=11`，walkable `±15.5 / ±10.5`。
- `godot/spike/demo_chessroom.tscn`：地板 32×22、墙 ±16/±11、LampC/LampD、Table5（-11,0）/ Table6（11,0）含腿/板/双椅，挂 `chess_tables` 组。

### 客户端（`godot/spike/scripts/chessroom.gd`）

- `TABLE_META` 增 table_5/6；房间标签「甲乙丙五子棋 / 丁跳棋 / 戊军棋 / 己五对」。
- 五对面板：明牌双人、弃牌堆、回合提示、黑/红对数常显、选牌高亮。
- 按钮：出牌 / 吃牌 / 过牌（按座位与回合显隐）。

### 冒烟（`scripts/wudui_smoke.py` 新增）

- 全链断言：双人 sit → deal（黑 11 / 红 10）→ 黑弃 → 红过 → 错回合拒着 → 认输 → redeal。

## 4. 实施中发现并修复的问题

| # | 问题 | 修复 |
|---|------|------|
| 1 | smoke 事件线读错位置：`chess_table_update.detail` 在 wire 上是 `payload.detail`，首版谓词查 `msg["detail"]` 导致超时 | 按 `blackjack_smoke.py` 范式改 `payload.detail`，并加状态特定谓词过滤 join 期陈旧广播 |
| 2 | 错座位动作（红发 `card_discard` / 黑发 `card_eat|pass`）在 gateway 静默 return，无拒着 → 客户端无反馈 | 改为回 `WUDUI_NOT_TURN` 拒着 |
| 3 | `chessroom.gd` 用 `in ("blackjack", "wudui")` 元组字面量，GDScript 不支持 → 场景编译失败 | 改为 `in ["blackjack", "wudui"]` 数组写法 |

## 5. 验证结果

```text
wudui smoke OK   # p1 seated → dealt 11/10 → discard → pass → reject → resign → redeal
ws_smoke:        smoke OK
blackjack:       blackjack smoke OK
gdscript_lint:   0 finding(s)
场景编译门:      demo_hub / demo_race / demo_workshop / demo_city / demo_chessroom / demo_arm_lab 全 BOOT OK
```

## 6. 部署与线上验证

```text
deploy_playground.sh → DEPLOY OK 20260806-113133
site:    200  MW_BUILD="20260806-113133"
/xr/:    200（rsync 无 --delete，未动）
/arm/:   200（rsync 无 --delete，未动）
?level=demo_chessroom: 200
WS 探针:  table_5 = gomoku 五子棋 · 丙桌
          table_6 = wudui  五对 · 双人桌
          LIVE PROBE OK
```

## 7. 变更文件清单

- `gateway/wudui.py`（新增）
- `gateway/echo_server.py`
- `examples/contracts/demo_chessroom.json`
- `godot/spike/demo_chessroom.tscn`
- `godot/spike/scripts/chessroom.gd`
- `scripts/wudui_smoke.py`（新增）
- `docs/09-todo.md` · `docs/19-changelog.md` · `AGENTS.md`

## 8. 后续建议

- 牌面美术：现为代码绘制（♠♥♦♣ Unicode + 点数）；可换 Kenney Playing Cards 包（CC0，需联网下载 + `ASSETS.md` 台账）。
- 玩法增强：五对规则说明弹窗；对局历史/战报；四人围观观战席位。
- 稳定性：五对全自动对局 fuzz（随机策略对跑千局，校验无死锁）。
