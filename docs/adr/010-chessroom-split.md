# ADR-010 · chessroom.gd 拆分（P2-1）

| 字段 | 值 |
|------|-----|
| 状态 | 刀1 已落地（2026-08-20）：`mw/rules_text.gd` + `mw/table_games/wudui_util.gd` 抽纯函数 ~230 行，四 smoke 绿 · 刀2 待做 |
| 关联 | [37-improvement-plan](../37-improvement-plan-2026-08.md) P2-1 · [32-handover-chess-cards](../32-handover-chess-cards.md) |

## 背景

`chessroom.gd` 3468 行，承载：桌位/入座/旁观、5 种游戏规则渲染（五子棋/跳棋/军棋/五对/21点）、表情、皮肤同步、动画 tick（piece/bj/wudui）、splat 挂载、聊天。下一个桌型会先撞这堵墙。

## 决策

两刀合并，每刀 smoke 全绿（`chessroom_smoke` / `wudui_smoke` / `blackjack_smoke`）：

### 刀 1 · 抽 `godot/spike/scripts/mw/mw_table.gd`（桌游域公共件）

- 职责：桌位状态镜像（sid→座位）、入座/离座 cmd 发送、旁观判定、表情按钮、皮肤同步钩子。
- 接口：`attach(scene, ws)` / `apply_table_update(detail)` / `seated_side(sid)` / 信号 `seat_changed(table_id, side)`。
- chessroom.gd 只保留「哪个桌子、什么游戏」的分发。

### 刀 2 · 每游戏 rules adapter

- 目录 `godot/spike/scripts/mw/table_games/`：`gomoku.gd` `halma.gd` `junqi.gd` `wudui.gd` `blackjack.gd`。
- 统一接口：`render(detail, layer)` / `handle_click(cell)` / `rules_text()` / `anim_tick(delta)`。
- 验收锚：新增「井字棋 demo 桌」≤100 行（contract 声明 + 30 行 adapter）。

## 边界（不做）

- 不改 Gateway 协议与 `chess_*` cmd 集；不改桌数/房型；不碰 splat 挂载逻辑（留 chessroom.gd）。
- 动画补间随 adapter 走，但视觉参数（时长/缓动）保持一致。

## 风险

- piece/bj/wudui 三套 anim tick 交叉在 `_process`：刀 1 先把 tick 分发收敛成 `_tick_table_anims(delta)` 单入口，再刀 2 拆走。
- `_view_game()` 全局状态被 H/S 键复用：adapter 需声明 `hotkeys()` 表，由 chessroom 统一路由。
