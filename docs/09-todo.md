# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-17 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | 打通 MVP：进关 → 接管 → MuJoCo 驱动 → 落盘 |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md)（POC 规格 + MVP 薄架构） |

勾选约定：`[ ]` 未做 · `[x]` 完成 · `[-]` 取消

---

## Now（Phase 2 · 真仿真）

> Phase 0（决策/Schema）与 Phase 1（POC-A 连通，M1）已于 2026-07-17 完成；
> 客户端引擎定案 Godot（[adr/003](adr/003-client-engine-godot.md)）。当前执行入口为 T2.x。

### A. 钉死 3 个决策（阻塞后续实现）

> 默认提案已写入 [11 §3](11-poc-mvp-architecture.md#3-poc-冻结默认讨论通过即-closed)；评审勾选即可。

| ID | 任务 | 建议默认 | 状态 |
|----|------|----------|------|
| T0.1 | 坐标系：米 + 右手系；**Z-up**（对齐 MuJoCo）还是 Y-up（对齐部分游戏引擎） | **Z-up**，客户端侧做一次映射 | [x] |
| T0.2 | MVP 控制模式 | **`velocity`**（vx, vy, yaw_rate） | [x] |
| T0.3 | Gateway 语言 | **Python 3.11+** | [x] |
| T0.3b | 机甲策略 + POC 工期 | **自建盒子**；**5 工作日**（见 `11` §9.1） | [x] |

已完成：`10-open-questions` C2/P2/P3/E2/C3 Closed；`11` §9.1 已填；ADR-001/002 → Accepted。

### B. 补齐契约 SSOT

| ID | 任务 | 产出 | 状态 |
|----|------|------|------|
| T0.4 | 补 `schemas/ws-messages.v0.json` | 与 `03` 对齐；可扩展信封 | [x] |
| T0.5 | 补 `schemas/recording-session.v0.json` | header + frame；可扩 features/extensions | [x] |
| T0.6 | 定 `dt` / `tick_rate` 默认值 | `dt=0.02`、sim 50Hz、state 20Hz（`11` D4 + schema README） | [x] |
| T0.7 | 弹性化 `scene-contract` + `common.v0` + 示例 | `shape`、extensions、开放枚举 | [x] |

### C. Phase 1 连通（假物理即可）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| T1.1 | `gateway/`：最小 WS 服务（hello / join / 收 cmd / 发假 state） | `websockets`，本地 `ws://127.0.0.1:8765` | [x] |
| T1.2 | `examples/`：用 `wscat` / 小脚本验证协议 | `scripts/ws_smoke_test.py` → `smoke OK` | [x] |
| T1.3 | 客户端：本地工程 + WebSocket 连接 | 连接成功、解析 `hello`、存 `session_id` | [x] |
| T1.4 | 客户端：发 `cmd` + 用假 `state` 移动 3D 对象 | 键盘操控「假机甲」可见移动 | [x] |
| T1.5 | 固化 `examples/contracts/tutorial_01.json` | 与客户端场景物体 ID 一致 | [x] |

> T1.3–T1.5 已在两个客户端上各验证一次：GDevelop `gdevelop/demo0`（Legacy）与 Godot `godot/spike`（现行基线，含无头验收 `godot --headless --path godot/spike --script res://headless/smoke_client.gd` → `smoke OK`）。客户端引擎选型定案 Godot，见 [adr/003](adr/003-client-engine-godot.md)。

**Phase 1 里程碑（M1）**：客户端 ↔ Gateway JSON 互通（✅ 双引擎均验证）。

---

## Next（Phase 2：真仿真）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| T2.1 | `mujoco/`：最小 MJCF（平地 + 盒子机甲，slide+hinge + 速度舵机） | 无头 10s 稳定；三组 cmd 配置轨迹与理论一致（`mujoco/scripts/headless_run.py` → T2.1 PASS） | [x] |
| T2.2 | Gateway 接入 MuJoCo：`cmd`→ctrl，`state`←qpos（`--physics mujoco`，`MujocoMech`） | 位姿由仿真驱动；Python + Godot 双冒烟在真物理下原样通过（`features: ["mujoco"]`）；`--physics fake` 保留回归回退 | [x] |
| T2.3 | 按契约加载 `static_obstacles`（盒体） | 碰到墙有物理反应 | [ ] |
| T2.4 | `take_control` / `release_control` | 事件入库与客户端 UI | [ ] |
| T2.5 | 录制：`sessions/<id>/header.json` + `frames.jsonl` | 单会话 ≥10s 可落盘 | [ ] |
| T2.6 | 传感器最小出口：`state` 带 `joints`/`joint_vels`/`velocities`（来自 `MjData`） | 为 AI 同视图打底（见 `04` §5.1）；非 M2 阻塞项 | [ ] |
| T2.7 | 输入延迟补偿 v0：cmd 缓冲 1–2 tick（ADR-002 待细化 #1） | 局域网下主观手感可接受即可 | [ ] |

**Phase 2 里程碑（M2+M3）**：真物理驱动 + 可录制。

---

## Later（Phase 3–4）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| T3.1 | 终点触发器 → `objective_complete` | 网关判定，防客户端作弊 | [ ] |
| T3.2 | `scripts/replay-session.py` | 读 JSONL 画轨迹 / 可选开环重算 | [ ] |
| T3.3a | 素材准备：Kenney `platformer-kit` + `city-kit-commercial` 已入库（`assets/kenney/`，26MB，GLB/OBJ/FBX，含 License.txt）；`ASSETS.md` 已登记；Truck Town 按需 `gh-proxy` 克隆参照（不入库） | 资产入库 + 台账条目 | [x] |
| T3.3b | Godot 拼 `tutorial_02` 场景（`05` §6.1 标准工作流） | 场景可 F5 漫游（人工验收通过：城市街区 + 跑道件 + 朝向箭头） | [x] |
| T3.3c | 手写契约 `examples/contracts/tutorial_02.json` + 节点 `mujoco_entity_id` 对齐 | Schema 校验通过（jsonschema + 本地 Registry，6 实体） | [x] |
| T3.3d | 联调：`--contract tutorial_02` + 客户端进新关 | 接管 → state 回显已通（无头 + F5 人工）；`objective_complete` 依赖 T3.1 触发器判定，随 POC-B 做 | [-] |
| T3.4 | 客户端导出 + 托管说明 | Godot `--export-release` 桌面包；Web 导出后置（ADR-003） | [ ] |
| T4.1 | 多会话 / Worker 池 | 水平扩展无头 MuJoCo | [ ] |
| T4.2 | 场景契约从 Godot 编辑器插件导出 | 替代手写 JSON；插件直读 `.tscn` | [ ] |
| T4.3 | Blender → 资产管线（可选 MCP） | 非 MVP 阻塞项 | [ ] |
| T4.4 | 学习/评测 API 草案 | 数据对外接口 | [ ] |
| T4.5 | AI Agent 遥操替换：复用 `cmd` 通道 + `ext.sensor` 视图 | 同一契约下人/机可互换（04 §5.1） | [ ] |
| T4.6 | 动态可交互物 L1：运动学门/电梯（`kinematic_obstacles` + Gateway 驱动 + 傀儡插值） | 分级见 `02` §2.2；L2/L3 后置 | [ ] |

---

## 建议执行顺序（最短路径）

```text
T0.1–T0.3 决策
    → T0.4–T0.6 Schema / 频率
    → T1.1 Gateway echo
    → T1.3–T1.4 客户端联调（已双引擎验证，基线 Godot）
    → T2.1–T2.2 真 MuJoCo
    → T2.5 录制
    → T3.1 任务闭环
```

---

## 本周建议（若只做 3 件事）

1. **建模** T2.1：最小 MJCF（平地 + 自建盒子机甲），无头 `mj_step` 10s 稳定
2. **接入** T2.2：Gateway 接 MuJoCo，`cmd`→ctrl、`state`←qpos（关掉假积分）
3. **落盘** T2.5：录制 `sessions/<id>/header.json` + `frames.jsonl` ≥10s

---

## 明确不做（MVP 范围外）

- 引擎自带多人联机当物理桥
- 自托管完整编辑器 SaaS
- 账号体系 / 计费 / 数据合规模板（可后置）
- 关节级 50Hz 全量录制优化（先能录再优化）
