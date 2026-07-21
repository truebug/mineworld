# 13 · Web 导出与线上多人 Demo 路线（审核）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **目标态** | 浏览器可打开的 Demo：多人可进入、各自/共享会话遥操、Gateway + 真物理权威 |
| **关联** | [09-todo](09-todo.md) · [08-modes-roadmap](08-modes-roadmap.md) · [adr/003](adr/003-client-engine-godot.md) · [12-status-review](12-status-review.md) |

> 手感项（T2.7）**暂缓**。公网 HTTPS/wss（W2.1/2/4）**暂缓**。  
> **已完成（2026-07-19）**：W2.3 本机会话隔离 · W3 同关两人最小 · T2.6 joints。  
> 本机双端请用 `http://127.0.0.1:8080/?room=demo`（勿依赖 `window.*=...; location.reload()`，刷新会丢变量）。

---

## 1. 目标澄清

| 说法 | 含义（本仓库约定） |
|------|-------------------|
| **Web 版** | Godot `--export-release Web` → 静态资源（`index.html` + wasm/pck） |
| **线上 Demo** | 静态站可公网访问 + Gateway 可被浏览器以 `wss://` 连上（Later） |
| **可多人进入使用** | ≥2 名玩家同时在线；私房隔离或同关多机甲（见 §3） |

**不是**：账号体系、匹配大厅、商业计费（仍属 Out of Scope，可后挂）。

---

## 2. 现状审核（相对目标态）

| 能力 | 现状 | 距目标缺口 |
|------|------|------------|
| 单机可玩闭环 M4 | ✅ Godot + Gateway + 录制 + 终点 | — |
| macOS 导出 | ✅ preset + `export_godot.sh macos` | 非主交付 |
| **Web 导出** | ✅ preset + 单线程导出 + `serve_web_demo.py`；浏览器键盘桥已通 | CI 出包可选；手感 T2.7 仍暂缓 |
| Gateway 绑定 | 默认 `127.0.0.1`（安全默认） | 公网需反代 `wss` + 显式 `--host`（暂缓） |
| 浏览器连 Gateway | 客户端可读 `window.MINEWORLD_GATEWAY` | 生产必须 `wss://`（暂缓） |
| 多连接 / 隔离 | ✅ Room 私房 = 每会话独立 MjData | — |
| 多机甲同关 | ✅ `?room=demo` 最多 2 人；每机甲独立 MjData | 机甲互撞（共享 MjData）非本迭代 |
| TLS / 域名 / CDN | 无 | Later（W2.1/2/4） |
| 水平扩展 | 无 Worker 池 | T4.1 |

**结论**：W1 + W2.3 + W3 本机已通。公网部署不阻塞本地 Demo。

---

## 3. 分期计划（建议执行序）

```text
W1  本地 Web 单人     →  Done
W2.3 会话隔离          →  Done（私房一 Session 一 MjData）
W3  同关多人最小      →  Done（Room demo ≤2；多傀儡；控制权）
T2.6 joints 出口      →  Done（state/录制含 joints(+joint_vels)）
W2.1/2/4 公网可部署   →  Later / 暂缓
W4  线上 Demo 加固    →  限流、录制分区、监控、短链分享
```

### W1 — 本地 Web 单人（Done · 2026-07-19）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W1.1 | 安装 Godot **Web** 导出模板（与编辑器同版本） | 管理器「已安装模板」含 Web | [x] |
| W1.2 | `bash scripts/export_godot.sh web` | `dist/web/index.html` 存在 | [x] |
| W1.3 | `python scripts/serve_web_demo.py`（COOP/COEP） | 浏览器打开可进场景 | [x] |
| W1.4 | Gateway + 页面内遥操（含键盘桥 / entity_id） | 位姿跟 state；可到终点 | [x] |

**命令摘要**：

```bash
bash scripts/export_godot.sh web
.venv/bin/python gateway/echo_server.py          # 终端 1
.venv/bin/python scripts/serve_web_demo.py        # 终端 2 → http://127.0.0.1:8080/
```

可选覆盖 Gateway（页面控制台或托管页注入；**room 请用 URL**）：

```html
<script>window.MINEWORLD_GATEWAY = "ws://127.0.0.1:8765";</script>
```

同关两人（Chrome + Safari）：

```text
http://127.0.0.1:8080/?room=demo
```

HUD 应显示 `room: demo`；先到 `entity: mech_player`，后到 `mech_player_b`。  
`window.MINEWORLD_ROOM` / `sessionStorage` 仍可读，但 **`location.reload()` 会清掉 window 变量**，e2e 以 query 为准。

### W2.3 — 会话隔离（Done · 2026-07-19）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W2.3 | 每 Session / 私房独立 `MjData`（共享只读 `MjModel`） | 两标签默认互不踩位姿 | [x] |

### W3 — 同关多人最小（Done · 2026-07-19）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W3.1 | `Room`：共享 tick；state 含全部 mechs；fan-out | 两人互见 | [x] |
| W3.2 | 客户端按 `entity_id` 多傀儡；相机跟己方 | 各控一台 | [x] |
| W3.3 | `join.payload.room_id`：省略=`session_id`（私房）；`demo` 最多 2 人 | 满员 `ROOM_FULL` | [x] |

**MuJoCo 限制（本迭代）**：每机甲一份 `MjData(同一 MjModel)`，互见、**暂无互撞**（避免改 MJCF 双 chassis）。

### T2.6 — joints 出口（Done · 2026-07-19）

Schema 已支持 `entity_state.joints` / `joint_vels`。Gateway 写出 `slide_x` / `slide_y` / `yaw_z`；客户端可暂不消费。

### W2.1 / W2.2 / W2.4 — 公网可部署

> **实施建议书（目标机 / 清单）**：[23-public-deploy.md](23-public-deploy.md)（腾讯云 2C8G · `databall.cloud`）。

| ID | 任务 | 验收 |
|----|------|------|
| W2.1 | 静态资源上 CDN/对象存储或 Nginx/Caddy | HTTPS 可打开 |
| W2.2 | Gateway 反代 `wss://…/ws` | 浏览器跨机可连 |
| W2.4 | 文档：防火墙、仅演示密钥/IP allow（最小） | 有一页运维说明 |

### W4 — 加固

限连、idle 踢出、录制按房间目录、基础指标、短链落地页。

---

## 4. 架构约束（线上也不可破）

1. 浏览器 **不**做机甲权威物理；只发 `cmd`、收 `state`。  
2. 录制仍在 Gateway（每 session 各录一份；frames 含全房 entities）。  
3. 公网 **禁止**裸奔无 TLS 的 `ws://`（本地除外）。  
4. Godot Web 线程版托管必须带 **COOP/COEP**（`serve_web_demo.py` 已示范）。  
5. ADR-003：Web 包体与浏览器限制已知；Demo 可接受「稍重」，不先做 PWA 商店分发。

---

## 5. 风险与建议

| 风险 | 建议 |
|------|------|
| 误以为多标签 = 多人 | 默认私房隔离；同关需显式 `room_id=demo` |
| 共享 `MjData` 数据竞争 | W2.3 已按会话/机甲拆开 |
| 浏览器混合内容 | 页面 HTTPS 则 Gateway 必须 wss（公网阶段） |
| 导出模板版本漂移 | 锁定 4.7.1（或团队统一版）写入 README |
| 手感/延迟（T2.7） | **暂缓**；先通链路再调 |

---

## 6. 文档与脚本清单（本迭代）

| 路径 | 作用 |
|------|------|
| `godot/spike/export_presets.cfg` | preset `macOS` + **`Web`** |
| `scripts/export_godot.sh [web\|macos]` | 默认 **web** |
| `scripts/serve_web_demo.py` | 本地静态 + COOP/COEP |
| `godot/spike/scripts/main.gd` | `gateway_url` + `room_id` + `MINEWORLD_*` |
| `docs/09-todo.md` | Now = 可选短增量；W2.3/W3/T2.6 Done |
| 本文 | 目标、分期、审核 |

---

## 7. 对外话术（建议）

- **现在**：「本地浏览器 Demo；`?room=demo` 可两人同关（无互撞）；默认 URL 为私房隔离。」  
- **公网 W2 后**：「线上 Demo，wss + 静态 HTTPS。」  
- **互撞 / 大厅**：非本迭代承诺。

未到阶段不提前承诺「开房间乱斗」。

---

## 8. 变更日志（摘录）

| 日期 | 摘要 |
|------|------|
| 2026-07-19 | W1 Web 单人通（键盘桥 + entity_id） |
| 2026-07-19 | W2.3 Room 私房隔离；W3 `demo`≤2；T2.6 joints；e2e 用 `?room=demo` |
