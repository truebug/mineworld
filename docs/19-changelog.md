# 19 · 变更记录（Changelog）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **关联** | [09-todo.md](09-todo.md) · [18-hub-dungeon.md](18-hub-dungeon.md) · [16-value-sprint.md](16-value-sprint.md) · [20-platform-portal.md](20-platform-portal.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) |

> 按时间倒序记「已入库」切片；待办与路线见 [09](09-todo.md)。不替代 git log，只记产品/架构向摘要。

---

## 2026-07-21 · W2 公网实施建议书

- 新增 [23-public-deploy.md](23-public-deploy.md)：腾讯云 2C8G + `databall.cloud` 单机拓扑、资源判断、Caddy/env、分阶段清单与验收。
- 非仿真负载确认轻量；MuJoCo 公网需限房。实施仍待 CVM 上执行（W2.1/2/4 未勾 Done）。

---

## 2026-07-21 · H11 竞技场门占位

- 门 E：Arena Gate 立面/地垫/橙红霓虹；小地图 E 点高亮。
- F：四态循环 `1v1/party × Looking-for-match`；**不** join、**不**开 PMS URL。
- Classroom 交互台略东移，避免与 Arena pad 抢 F。

---

## 2026-07-21 · PL2 Admin 运维 + E4 真 URL + IL-place 飞轮

- **PL2**：Gateway admin HTTP `:8770`（`GET /admin/rooms|contracts|status`，`POST /admin/levels/disable|enable`）；Portal Admin 在线房表 + level 开关；`serve_web` 代理 `/api/gateway/*`；`admin_ops_smoke`。
- **E4/E3**：展柜 `enter_url` → `spaces.databall.tech/enter/...`；stub 可开 live Space / 带 `space_id` 回 Hangar。
- **IL**：`scripts/il_place_smoke.py` — 录 grasp→place → export `obj_place_block` → `bc_offline_check`。

```bash
.venv/bin/python scripts/admin_ops_smoke.py
.venv/bin/python scripts/il_place_smoke.py
.venv/bin/python scripts/ws_smoke_test.py
```

---

## 2026-07-21 · E3 会话归因 + H9/H10 Hub 慢扩

- **E3**：`space_id` / `route_kind` 写入 join → recording header → scores；`?space_id=`；样例 `examples/platform/session_attribution.v0.json`。
- **H9**：Party board 切换 Looking-for-crew + stub LFG；Vendor F 循环 accent 并写 profile。
- **H10**：北墙 Gallery / Classroom 走廊壳 + 交互台 lore。

```bash
.venv/bin/python scripts/platform_smoke.py
.venv/bin/python scripts/ws_smoke_test.py
```

---

## 2026-07-21 · E2 身份映射草案 + federated stub

- SSOT：[22-identity-mapping.md](22-identity-mapping.md)；样例 `examples/platform/identity_link.v0.json`。
- `identity_links` 表；`POST /login/federated`（stub）；Admin `identity-links`；`/me` 返回 links。
- `platform_smoke` 覆盖 link + federated 幂等。

---

## 2026-07-21 · E4 展柜 → 外部 Space stub

- Hub 两侧展柜：走近 F → 新标签打开配置 URL（不进 MuJoCo）。
- E5 薄做：`examples/hub/exhibits.v0.json`（与 `godot/spike/data/exhibits.v0.json` 同步）；`/portal/space_stub.html` 可 **Back to hangar**。

---

## 2026-07-20 · R3 / IL place / H8

- **R3**：Hub `main_scene` 下 `/?replay=` 按 recording `level_id` 路由到 workshop/city；Recordings / My record 恢复 3D 入口；Esc 清 `replay` 防回环。
- **IL**：`obj_place_block`（工作台 AABB + 张开夹爪）；`grasp_lift` 仅里程碑不写 outcome；`grasp_place_smoke.py`；默认 `mw.il.task_id=obj_place_block`；录制终局写回 `task_id`。
- **H8**：电梯 F 薄乘 L1↔L2（avatar `height_offset`）；L2 呼叫台；门在 L2 不触发。

```bash
.venv/bin/python scripts/grasp_place_smoke.py
.venv/bin/python scripts/grasp_lift_smoke.py
.venv/bin/python scripts/stow_crate_smoke.py
```

---

## 2026-07-20 · W1 工坊双 prop（推箱 + 抓取）

- `prop_crate` 恢复 0.5 m 供 `obj_stow_crate`；新增 `prop_block` 6 cm 供 `obj_lift_block`。
- `stow_crate_smoke` / `grasp_lift_smoke` 分目标验收。

---

## 2026-07-20 · E1 Portal Landing → Profile/榜 → 进大厅

- `/portal/` 品牌 Landing（未登录 Sign in；已登录 Enter hangar）。
- `/portal/me.html`：主 CTA **Enter hangar** + 积分 + Leaderboard + 近期会话。
- 登录默认 `next=/portal/me.html`；游戏壳未登录 → `/portal/?next=…`（不再直跳 login）。

---

## 2026-07-20 · 生态对接叙事冻结（21）

- 新增 **[21-ecosystem-federation.md](21-ecosystem-federation.md)**：MineWorld = 3D 传送门前台；本仓 MuJoCo 玩法/采数；展厅/教室等 → PMS Space（对接不搬迁）。
- [00-vision.md](00-vision.md) / [AGENTS.md](../AGENTS.md) / [docs/README.md](README.md) / [09](09-todo.md) Now：**E4 / E2**（E1·W1 Done）。

---

## 2026-07-20 · C 线产品闭环收口

### 方向

- **C1–C4 Done**；H8 / R3 / 公网仍顺延。
- 验收主路径：登录 → Hub → 通关 → +N pts → 排行 / 我的 → 2D 回放。

### 实现摘要

- **C1**：`main.gd` 玩法关 `join` 传入 `extensions.mw.profile`（对齐 Hub）。
- **C2**：`objective_complete.detail.points` + 通关即时幂等记账；SUCCESS UI 显示 +N pts / My record 链。
- **C3**：`scripts/journey_smoke.py`（platform API + MuJoCo；`demo_city` 开环到点验收积分链）。
- **C4**：UX2b 薄做（门色过场 · 桌面 Tween · 可跳过）。

```bash
.venv/bin/python scripts/journey_smoke.py
```

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

## 后续方向（已记入 Todo）

| 线 | 摘要 | Todo ID |
|----|------|---------|
| **C 闭环** | profile join · 通关积分 · journey smoke · UX2b 薄 | C1–C4（见上） |
| UX | 过场增强 | UX2b / C4 |
| Hub | 可乘电梯 / 可上 L2（顺延） | H8 |
| 回放 | 修复 `/?replay=` 3D | R3（Next） |

完整条目与验收见 [09 § Now / Next](09-todo.md)。

---

## 2026-07-20 · H7 Hub UI + UX3 重连

- H7：左栏门语境 lore；名片 Pilot card；小地图标 C–E；北墙 D/E stub + 走近文案（不进关）。
- UX3：`WsClient` 自动重连 + `link_phase_changed`；Hub/关卡明确 Connecting / Reconnecting / Offline 文案。

## 2026-07-20 · 相机 SSOT + P1b BC 离线检查

- `camera_rig.gd`：V/C/鼠标为共享 SSOT；chase 松手视线弹簧回正（焦距保留）；关卡与 Hub 共用。
- Hub/关卡 Web 桥只调 `handle_code`；关卡补 V + FP 隐藏车体。
- `scripts/bc_offline_check.py` + `examples/il/bc_sample.csv`：断言 success CSV 有可解析 `joints`。

## 2026-07-20 · AD2 / EXP1 + P1a 摩擦抓取

### Admin 钻取与导出
- 录制 header 写 `player_id`；`/api/recordings?player_id=` 与 `export.csv?player_id=`；CLI `--player-id`。
- Admin 点玩家 → 会话列表（2D 回放链）+ Export CSV（success / all）。

### P1a 真摩擦抓取 v0
- 去掉 sticky weld / 每 tick 粘贴；`grasp_lift` 只认闭合 + 真实接触 + `min_z`。
- 工坊 `prop_crate` 改为可夹 6 cm 料块；`grasp_lift_smoke.py` PASS（不查 weld）。

## 2026-07-20 · 暂禁 3D offline replay（R3）

- Recordings「▶ 3D Replay」改为 disabled；My record 只保留 2D 链。
- 任务 **R3**：修好 `/?replay=` 后再开入口。

## 2026-07-20 · Phase C · ME2 自助回放

- My record 每行探测 `/api/recordings/<id>`：有帧则链 **2D**（`recordings.html?session=`）；3D 暂禁见上。
- Admin 本地默认 key `dev-admin`（可用 env 覆盖）。

---

## 2026-07-20 · Phase C · ME1 / AD1

- Portal `/portal/me.html`：积分汇总 + 近期会话（`/api/platform/me` 扩展）。
- Admin `/portal/admin.html`：admin key 列玩家 / 创建账号。
- Hub 名片链到 My record。

---

## 2026-07-20 · Phase B · SC1/SC2/LB1 + PL3

- 积分公式 `mw_platform/scoring.py`；`scores` 表幂等记账；Gateway `score_client` 在 success close 时 POST。
- Hub DOM `#mw-hub-lb` 轮询 `/api/platform/leaderboard`。
- PL3：`docs/20` §4.1 WS vs HTTP 边界表。

---

## 2026-07-20 · Phase A v0（Portal + SQLite API）

- `mw_platform/`：可换 URL 的 SQLite 玩家库 + Bearer token。
- Portal `/portal/login.html`；未登录访问 `/` 跳转登录（demo/demo）。
- 独立 API：`python mw_platform/api_server.py`（8090）；Web 同域也挂载 `/api/platform/*`。

---

## 2026-07-20 · 平台门户产品线写入计划

- 新增 [20-platform-portal.md](20-platform-portal.md)：Portal 登录 → Hub → 计分关 → 排行/我的/Admin。
- Todo 拆 Phase A/B/C（PL/ID/SC/LB/ME/AD/EXP）；与 P1 并行、Gateway 不塞用户库。

---

## 2026-07-20 · UX1 + UX2-v0

- Web 首屏：`shell.html` 品牌字标（MineWorld / Dungeon Gate）+ 进度条；隐藏 Godot 默认 splash 图。
- 过场：`MW_TRANSITION` DOM 淡入淡出（~280ms）；Autoload `MWTransition.go` / `notify_arrived` 覆盖 Hub 门、Esc 回 Hub、文本菜单。
