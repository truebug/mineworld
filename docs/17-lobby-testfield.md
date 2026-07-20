# 17 · 试验场入口（Lobby / Test Field）

| 字段 | 值 |
|------|-----|
| **状态** | Active · H0–H2 已落地；文本菜单降级为 `?menu=1` |
| **日期** | 2026-07-20 |
| **关联** | [09](09-todo.md) · [13](13-web-multiplayer-demo.md) · [16](16-value-sprint.md) · **[18-hub-dungeon.md](18-hub-dungeon.md)** |
| **场景** | `demo_lobby.tscn`（调试菜单）；默认入口见 [18](18-hub-dungeon.md) `demo_hub.tscn` |

> **试验场文本菜单** = 调试用选关壳（`/?menu=1`）。玩家默认走 **3D 地下城 Hub**（[18](18-hub-dungeon.md)）。  
> 选关后 `change_scene` 进入真实玩法关（车间 / 街区），再 `join` Gateway。

---

## 1. 为什么要有入口

| 问题 | 入口解决什么 |
|------|----------------|
| 默认直进车间/城市 | 玩家/采集员不知道有哪些关、关什么数据 |
| 关卡与契约 1:1 | 需要显式选择，避免「画面是 A、物理是 B」 |
| 后续多任务 IL | 大厅可挂难度、任务说明、录制入口 |

**不是**匹配大厅、账号系统或元宇宙广场。

---

## 2. 分期

| ID | 内容 | 验收 | 状态 |
|----|------|------|------|
| **H0** | `demo_lobby` UI：车间 / 街区两按钮；工程 `main_scene` 指向 lobby | Web/F5 先见入口再进关 | [x] |
| **H1** | Gateway 按 `join.level_id` 加载 `examples/contracts/{level}.json`（多契约） | 同进程可进 workshop **或** city | [x] |
| **H2** | 玩法关 Esc / UI「回试验场」；Recordings 链回 lobby | 不硬刷 URL 可回入口 | [x] |
| **H3** | 卡片化：任务文案、`task_id`、推荐 control_mode | 与 header IL 标签一致 | [ ] |

---

## 3. H0–H2 行为（当前）

```text
demo_lobby（无 WS）
   ├─ Workshop → demo_workshop.tscn → join level_id=demo_workshop
   └─ City     → demo_city.tscn     → join level_id=demo_city
玩法关 Esc → demo_lobby
```

- Gateway 扫描 `examples/contracts/*.json`，按 `level_id` 建 Room（MuJoCo 按关缓存 `MjModel`）。  
- 同 `room_id` 不允许混关。  
- CLI `--contract` 仍为默认热加载种子；不禁止其它已登记关。

---

## 4. H1 设计要点（待实现）

- 扫描 `examples/contracts/*.json`，以 JSON 内 `level_id` 为键。  
- `join.payload.level_id` 命中则用该契约建 Room（MuJoCo 按关缓存 `MjModel`）。  
- 同 `room_id` 不允许混关；`demo` 房按**先入者的 level** 锁定。  
- CLI `--contract` 仍表示**默认关**（hello / 热加载种子），不禁止其它已登记关。

铁律不变：换关 = 换契约 + 换权威世界；Godot 只跟皮。

---

## 5. 与录制 / IL

| 入口动作 | 数据侧 |
|----------|--------|
| 选车间 | `level_id=demo_workshop`，任务 `obj_stow_crate`（大箱）/ `obj_lift_block`→`obj_place_block`（小块夹放） |
| 选街区 | `level_id=demo_city`，巡航 / 推箱 |
| Recordings | 仍走 `/recordings.html`；过滤 `level_id` / `outcome`（见回放验收） |

---

## 6. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-20 | 初版：H0–H3；落地 `demo_lobby` 为主场景 |
| 2026-07-20 | H1 多契约 join + H2 Esc 回入口 |
| 2026-07-20 | 默认入口迁至 3D Hub（[18](18-hub-dungeon.md)）；本页菜单保留为 `?menu=1` |
