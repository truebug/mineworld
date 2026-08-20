# ADR-011 · Gateway Room 基类（P2-2）

| 字段 | 值 |
|------|-----|
| 状态 | Accepted · 2026-08-20 |
| 关联 | [37](../37-improvement-plan-2026-08.md) P2-2 · B3 房间模式 |

## 背景

`echo_server.py` 承载所有房间规则；race/chess/city/hub 的 max_members、模式、旁观、满员策略散落在 `_handle_join` 分支里。B3 后的匹配队列/私密房/观战席需要房间生命周期抽象。

## 决策

新增 `gateway/rooms/` 包，`RoomPolicy` 基类冻结边界：

| 方法 | 职责 |
|------|------|
| `max_members(room_id, join_ext)` | 容量决策（现散在 join 分支） |
| `on_join(room, session)` / `on_leave(room, session)` | 钩子：棋桌入座释放、race 车位回收 |
| `allow_spectate(room)` | duel 超员旁观等 |
| `mode_for(room_id, join_ext)` | solo/duel/shared_ffa |

实现：子类 `HubPolicy` `CityPolicy` `RacePolicy` `ChessPolicy` + `DEFAULT`；`echo_server.py` 只按 level_id 查表路由。迁移顺序：race → chess → city/hub，每步 smoke 全绿。

## 边界（本刀不做）

- 匹配队列、跨房撮合只做 stub（`Matchmaker` 占位返回 None）。
- 不动 MuJoCo 共享步进与录制语义；grce/判负规则（P0-1）不变。
