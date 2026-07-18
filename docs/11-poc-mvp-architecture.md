# 11 · POC 规格 + MVP 目标架构（薄）

| 字段 | 值 |
|------|-----|
| **状态** | Accepted（2026-07-17 评审通过） |
| **日期** | 2026-07-17 |
| **仓库** | https://github.com/truebug/mineworld |
| **关联** | [01-architecture.md](01-architecture.md) · [09-todo.md](09-todo.md) · [adr/001](adr/001-dual-engine-split.md) · [adr/002](adr/002-authority-and-sync.md) · [adr/003](adr/003-client-engine-godot.md) |

> **2026-07-17 后续**：客户端引擎已由 GDevelop 切换为 **Godot 4**（[adr/003](adr/003-client-engine-godot.md)）。
> 本文中所有 `GDevelop` 现应读作「Godot 客户端」；M1 已在 Godot spike 上复验通过（见 §7.1 与 `godot/spike/`）。

---

## 0. 怎么读本文

| 层级 | 回答的问题 | 本文章节 |
|------|------------|----------|
| **POC** | 双引擎 + WS 能不能通、手感与数据是否可信？ | §1–§4 |
| **MVP 目标态（薄）** | POC 必须朝什么形状长，禁止临时叉路？ | §5–§6 |
| **验收与节奏** | 何时算过、下一步做什么？ | §7–§9 |

**原则**：架构讨论以 MVP 为目标态；当前落地以 POC 为迭代。详细协议/契约见既有 `02`–`04`，本文不重复抄全文。

---

## 1. POC 一句话

> 在 **本地单机** 上跑通：Godot 客户端 ↔ Python Gateway ↔（先假后真）MuJoCo，玩家 `velocity` 遥操可见，并落一段可回放的 `frames.jsonl`。

不证明「头号玩家世界」；只证明 **集成风险可接受**。

---

## 2. POC 验证什么 / 不验证什么

### 2.1 必须验证（4 件事）

| # | 风险点 | 验证方式 |
|---|--------|----------|
| V1 | **连通** | hello / join / cmd / state 双向 JSON 跑通 |
| V2 | **权威** | 机甲位姿来自 MuJoCo（或 POC 中期假积分→末期真仿真），非仅客户端本地物理 |
| V3 | **时序** | 固定 `dt`；客户端对 `state` 做简单插值，肉眼可接受 |
| V4 | **落盘** | `header.json` + `frames.jsonl` ≥10s，脚本能读出基座轨迹 |

### 2.2 明确不验证（POC Out of Scope）

| 不做 | 理由 |
|------|------|
| 多人联机 / 引擎自带 Multiplayer 桥 | 与仿真通道无关 |
| 场景契约从编辑器自动导出 | 手写 `tutorial_01.json` 足够 |
| 任务系统完备、第二关、UI 打磨 | MVP 再做 |
| TLS / 账号 / 计费 / 脱敏合规 | 生产前 |
| 关节级 50Hz 全量优化、state_delta | 先通再压 |
| 自托管编辑器 SaaS | 用桌面版本地工程 |
| 多 Worker / 水平扩展 | Phase 4 |

---

## 3. POC 冻结默认（讨论通过即 Closed）

| ID | 项 | POC 默认 | 可复议时机 |
|----|-----|----------|------------|
| D1 | 坐标系 | **米 · 右手系 · Z-up**（对齐 MuJoCo）；客户端侧做一次轴映射 | MVP 前若映射成本过高 |
| D2 | 控制模式 | **`velocity`**：`vx`, `vy`, `yaw_rate` | 需要关节 IL 数据时加 `joint_targets` |
| D3 | Gateway | **Python 3.11+**，单进程；本地 `ws://127.0.0.1:8765` | 上生产再拆 |
| D4 | 仿真步长 | **`dt = 0.02`（50Hz）**；`state` 广播 **20Hz**（每 2–3 tick） | 压测后微调 |
| D5 | 录制 | **本地目录** `recordings/sessions/<session_id>/` | 规模化再上对象存储 |
| D6 | 机甲 | **自建盒子机甲**（单刚体/少 geom，平地可动；不接 g1） | POC 通过后再换真实 MJCF |
| D7 | 契约 | **手写** `examples/contracts/tutorial_01.json` | 编辑器扩展 P1 |

---

## 4. POC 分两拍（**冻结工期：5 个工作日**）

```text
POC-A（连通，~2 天）            POC-B（真仿真+落盘，~3 天）
─────────────────────          ─────────────────────────────
Gateway echo + 假 state        MuJoCo 盒子机甲 mj_step
Godot WS 收发                  cmd → ctrl，state ← qpos
假机甲可见移动                  take_control + JSONL 录制
验收：M1                       验收：M2 + M3（最小）
```

对应待办：[09-todo.md](09-todo.md) `T1.*` → `T2.*`。

### 4.1 POC-A 组件图（假物理）

```text
┌──────────────────┐     WS JSON      ┌──────────────────────┐
│ Godot Desktop    │◄────────────────►│ gateway/echo_server  │
│ + WebSocket      │   cmd / state    │ (Python, in-process  │
│   Client         │                  │  kinematic integrator│
└──────────────────┘                  │  — NO MuJoCo yet)    │
                                      └──────────────────────┘
```

假 state 规则：Gateway 内用 `cmd.velocity` 做简单积分（或固定圆周运动），**协议形状与真仿真相同**，避免换真仿真时改客户端。

### 4.2 POC-B 组件图（真物理）

```text
┌──────────────────┐     WS JSON      ┌──────────────────────┐
│ gateway/echo_server.py
│ 3D puppet only   │                  │ session · protocol   │
└──────────────────┘                  │ recorder · contract  │
                                      └──────────┬───────────┘
                                                 │ in-process API
                                      ┌──────────▼───────────┐
                                      │ mujoco/ (MJCF+step)  │
                                      │ authoritative qpos   │
                                      └──────────────────────┘
                                                 │
                                      ┌──────────▼───────────┐
                                      │ recordings/sessions/ │
                                      └──────────────────────┘
```

**禁止叉路**：不要在 Godot 内嵌 MuJoCo；不要用引擎自带 Multiplayer 同步位姿；不要把录制写在客户端。

---

## 5. MVP 目标架构（薄冻结）

POC 通过后，**不改拓扑**，只把假积分换成真仿真并补任务闭环。目标态如下。

### 5.1 逻辑视图

```text
                    ┌─────────────────────────────────────┐
                    │           Godot Client              │
                    │  Level shell · Input · HUD · Puppet │
                    └─────────────────┬───────────────────┘
                                      │ WSS/WS  protocol v0.1
                    ┌─────────────────▼───────────────────┐
                    │              Gateway                │
                    │  join · contract · cmd queue        │
                    │  broadcast state/event · record     │
                    └─────────────────┬───────────────────┘
                                      │
              ┌───────────────────────┼───────────────────┐
              ▼                       ▼                   ▼
        Scene Contract           MuJoCo Worker      Recording Store
     (tutorial_01.json)        (single process      (local FS →
                                in POC/MVP)          later object store)
```

### 5.2 职责冻结（MVP）

| 组件 | 做 | 不做 |
|------|----|------|
| Godot | 关卡呈现、输入→cmd、state→傀儡、任务 UI 展示 | 机甲权威物理、持久化录制 |
| Gateway | 会话、契约加载、控制映射、广播、录制、目标判定 | 关卡美术、账号 |
| MuJoCo | `mj_step`、机甲+盒体障碍 | 渲染、任务叙事 |
| Contract | spawn、障碍盒、终点 trigger | 完整客户端场景（`.tscn`） |

### 5.3 目录约定（实现必须落这里）

```text
mineworld/
├── docs/                 # 设计（已有）
├── schemas/              # JSON Schema SSOT
├── examples/
│   └── contracts/        # 手写契约
├── gateway/              # Python WS 网关 + recorder
├── mujoco/
│   ├── models/           # MJCF
│   └── scripts/          # 无头/本地调试
├── godot/                # 客户端工程（spike 已有；大资源另议 git-lfs）
├── gdevelop/             # Legacy：GDevelop 时代 POC-A 存档（不再演进，ADR-003）
├── recordings/           # gitignore；本地会话产出
└── scripts/              # replay / validate-contract
```

### 5.4 数据流（MVP 稳态）

```text
Input → cmd ──► Gateway ──► MuJoCo.ctrl
                     │
                     ├──► state (20Hz) ──► Godot puppet
                     ├──► event (async) ──► HUD / 任务
                     └──► recorder (cmd+state+event @ tick)
```

权威与时间轴：见 [adr/002-authority-and-sync.md](adr/002-authority-and-sync.md)。`tick` 为 SSOT。

---

## 6. 关键序列（POC / MVP 共用）

### 6.1 会话建立

```text
Client                    Gateway                     MuJoCo
  │                          │                          │
  │──── WS connect ─────────►│                          │
  │◄─── hello(session_id,    │                          │
  │      protocol_version,   │                          │
  │      tick_rate) ─────────│                          │
  │──── join(level_id) ─────►│── load contract ─────────│
  │                          │── reset(seed) ──────────►│
  │◄─── scene(summary) ──────│                          │
  │──── cmd(take_control) ──►│                          │
```

### 6.2 稳态循环

```text
Client                    Gateway                     MuJoCo
  │──── cmd(velocity) ──────►│                          │
  │                          │── apply ctrl ───────────►│
  │                          │◄─ after mj_step ─────────│
  │◄─── state(entities) ─────│── append frame ──────────│
  │                          │                          │
  │◄─── event(objective_*) ──│  (进入终点 AABB 时)       │
```

### 6.3 最小消息形状（提醒）

完整字段见 [03-websocket-protocol.md](03-websocket-protocol.md)。POC 必须支持：

- `hello` / `join` / `scene` / `cmd` / `state` / `event` / `error` / `bye`
- `cmd.payload.control_mode = "velocity"`
- `state.payload.entities[].base_pose`（至少 x,y,z,yaw 或四元数一种）

---

## 7. 验收清单

### 7.1 POC-A 通过（M1）

- [x] `gateway` 可启动，日志打印 `listening ws://127.0.0.1:8765`
- [x] 独立脚本或 wscat 能完成 hello→join→收 state（`scripts/ws_smoke_test.py`；另有 Godot 无头脚本 `godot/spike/headless/smoke_client.gd`，均 `smoke OK`）
- [x] 客户端预览：连接成功、键盘发 cmd、3D 对象随 state 移动（GDevelop demo0 与 Godot spike 各验证一次；现行基线 Godot，ADR-003）
- [x] 协议字段与 `03` 草案一致（无临时私货字段，或已回写文档）

### 7.2 POC-B 通过（M2 + 最小 M3）

- [ ] 关闭假积分；位姿来自 `mujoco.MjData`
- [ ] 加速/转向 cmd 改变仿真轨迹（肉眼可辨）
- [ ] 盒体障碍存在时，运动受阻或可碰撞（至少不穿模到离谱）
- [ ] `recordings/sessions/<id>/header.json` + `frames.jsonl` 存在且 ≥10s
- [ ] `scripts/replay_xy.py`（或等价）画出 x–y 轨迹图

### 7.3 MVP 通过（M4，POC 之后）

- [ ] 进关 → 接管 → 到达终点 → `objective_complete` → 结算 UI
- [ ] 同一 `seed` + 契约可开环重放轨迹（允许数值误差带说明）
- [ ] README 有「本地 5 分钟跑通」步骤

---

## 8. 与待办映射

| 本文 | [09-todo.md](09-todo.md) |
|------|--------------------------|
| §3 冻结默认 | T0.1–T0.3、T0.6 |
| POC-A | T1.1–T1.5 |
| POC-B | T2.1–T2.5 |
| MVP 任务闭环 | T3.1–T3.3 |
| 不做清单 | 同 09「明确不做」 |

---

## 9. 讨论议程（建议 30–45 分钟）

1. 同意 §2 Out of Scope 吗？有无必须提前塞进 POC 的项？
2. 接受 §3 D1–D7 默认吗？（尤其 **Z-up**、**velocity**）
3. POC 时长：5 天还是 10 天？谁负责客户端 / Gateway？
4. 机甲模型：自建盒子机甲 vs 直接挂现有 MJCF？
5. 通过后：ADR-001/002 → Accepted；`10-open-questions` 关闭对应项。

### 9.1 决议记录

| 项 | 决议 | 日期 |
|----|------|------|
| Out of Scope | **不再追加**；POC 保持简洁 | 2026-07-17 |
| D1 坐标系 | **接受**：米 · 右手系 · Z-up；客户端侧映射 | 2026-07-17 |
| D2 控制模式 | **接受**：`velocity`（vx, vy, yaw_rate） | 2026-07-17 |
| D3 Gateway | **接受**：Python 3.11+ 单进程 | 2026-07-17 |
| D4–D5 / D7 | **接受**：dt=0.02、state 20Hz、本地录制、手写契约 | 2026-07-17 |
| D6 机甲 | **自建盒子机甲**（降低复杂度；不接 g1） | 2026-07-17 |
| POC 工期 | **5 个工作日**（A≈2d + B≈3d） | 2026-07-17 |

---

## 10. 成功后的产品含义（一句话）

POC 通过 = **「娱乐壳采真物理遥操数据」技术可行**。  
MVP 通过 = **可演示的最短产品环**（一关、可玩、可录、可回放）。  
更大世界 / 学习 / 商业模式，建立在这两环之上，不倒过来做。
