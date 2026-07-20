# 19 · 变更记录（Changelog）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **关联** | [09-todo.md](09-todo.md) · [18-hub-dungeon.md](18-hub-dungeon.md) · [16-value-sprint.md](16-value-sprint.md) |

> 按时间倒序记「已入库」切片；待办与路线见 [09](09-todo.md)。不替代 git log，只记产品/架构向摘要。

---

## 2026-07-20 · 3D Hub（地下城入口）落地

### 产品

- 默认主场景改为 `demo_hub.tscn`；文本试验场降级为 `/?menu=1`。
- Hub 世界观与门 A–E 映射冻结于 [18](18-hub-dungeon.md)；本期可进 **A 工坊 / B 训练场**。
- 本地 Profile（昵称）无登录；Web `localStorage` / 桌面 `user://`。

### Gateway

- `demo_hub` 契约：`extensions.mw.mode = "hub"`；Hub 房强制 FakeMech（即使 `--physics mujoco`）。
- 公共房 `room_id=hub`，互见纸片人；**不录** IL。
- `join.player_name` / profile → `state.extensions.mw.display_name`。

### 客户端观感

- 实心机库大厅 + 太空星空天空盒；轮式机器人纸片人。
- 靠墙家具 / 交互台 / Kenney Blocky NPC（静站、缩小、贴地）。
- 相机：环绕 → 第一人称 → 追尾；追尾 RMB/MMB 环视 + 滚轮缩放。
- Web DOM 角标（提示 / 名片 / 小地图），按 `#canvas` 矩形定位，缓解裁切。
- **展示壳**：南侧半层二楼 + 东南角静态电梯（不可乘；F 提示 offline）。

### 资产

- KayKit Dungeon Remastered 子集、Kenney Blocky Characters 子集（见根 `ASSETS.md`）。

### 验证

```bash
.venv/bin/python gateway/echo_server.py --physics fake --no-record
bash scripts/export_godot.sh web && bash scripts/serve_web.sh restart
.venv/bin/python scripts/hub_presence_smoke.py   # 若脚本在仓
# 浏览器 Cmd+Shift+R → http://127.0.0.1:8080/
```

---

## 2026-07-20 · V 线冻结项收口（摘要）

- 车间 `demo_workshop` + 臂/爪 + sticky grasp → IL 标签/导出（详见 [16](16-value-sprint.md)）。
- 试验场 H0–H2、录制过滤 R1/R2 等已勾选（见 [09](09-todo.md) Done）。

---

## 后续方向（已记入 Todo，未实现）

| 线 | 摘要 | Todo ID |
|----|------|---------|
| UX | 首屏/加载动画（替换 Godot 默认 logo） | UX1 **[x] v0** |
| UX | 关卡过场（替代瞬间 `change_scene`） | UX2 **[x] v0** 淡入淡出 |
| 平台 | 可配置持久化库 + 消息中间件的独立 API 服务 | PL1 |
| 平台 | Web 控制台（后台管理） | PL2 |
| Hub | 可乘电梯 / 可上 L2；门 C–E 占位打磨 | H8 / H7 |
| 物理/IL | 真摩擦抓取、最小 BC 离线检查 | P1a / P1b |

完整条目与验收见 [09 § Next](09-todo.md#next平台与体验·规划)。

---

## 2026-07-20 · UX1 + UX2-v0

- Web 首屏：`shell.html` 品牌字标（MineWorld / Dungeon Gate）+ 进度条；隐藏 Godot 默认 splash 图。
- 过场：`MW_TRANSITION` DOM 淡入淡出（~280ms）；Autoload `MWTransition.go` / `notify_arrived` 覆盖 Hub 门、Esc 回 Hub、文本菜单。
