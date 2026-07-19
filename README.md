# MineWorld

> Godot 世界编辑 + MuJoCo 机甲物理权威 + WebSocket 桥接的仿真娱乐与遥操数据采集底座
>
> 做的不是游戏，也不是仿真器，而是「用游戏壳规模化采集真物理人类遥操数据」的管道。

| 字段 | 值 |
|------|-----|
| **状态** | POC 管道已通（Web 单人/本机多人、`demo_city`、录制回放导出）；**主线纠偏：提高遥操数据价值（控制/任务深度）** |
| **创建日期** | 2026-07-17 |
| **定位** | 「头号玩家」式初始底座：可编辑共享世界 + 真物理机体 + 可回放的人类行为档案 |
| **跑偏与纠偏（必读）** | [docs/15-course-correction.md](docs/15-course-correction.md) |
| **阶段评审** | [docs/12-status-review.md](docs/12-status-review.md) |
| **执行待办** | [docs/09-todo.md](docs/09-todo.md)（纠偏项讨论后再开 `Now（V）`） |
| **Web / 多人** | [docs/13-web-multiplayer-demo.md](docs/13-web-multiplayer-demo.md) |

---

## 一句话

**Godot 负责关卡/任务/地图与可视化 Viewer；无头 MuJoCo 负责机甲关节级物理仿真；WebSocket 交换控制与状态；旁路录制遥操与交互轨迹，支撑学习、娱乐与商业多种模式。**

---

## 开发跑偏与纠偏（摘要）

详细叙事、时间线与 V1–V5 计划见 **[docs/15-course-correction.md](docs/15-course-correction.md)**。此处只给结论，避免 README 与专项文档分叉。

### 我们最初要什么

娱乐壳获客 → MuJoCo **真机体** 权威 → 有任务约束的 **人类遥操档案**（`cmd` + `state`/`joints` + 事件可训、可回放）。  
**不是**自动驾驶，**不是**用游戏引擎硬扛机器人动力学。

### 实际发生了什么（跑偏）

工程上把 **管道** 打通了，且方向正确：

- 契约 / Schema / Gateway / MuJoCo 权威 / Godot 傀儡
- Web Demo、Room 多人、录制、2D/3D 回放、SQLite 索引与 CSV 导出
- `demo_city` 城市皮、空气墙、seed 重生、通关反馈等演示打磨

但 **控制语义长期停在平面 DiffBot + `velocity(vx,vy,ω)`**，任务以「开到绿点 + 轻推箱」为主。  
体感与数据都更像 **遥控小车/履带车**，信息密度偏低——这是 **优先级跑偏（演示皮与壳超前于控制深度）**，不是把产品做成了 AD，也不是双引擎架构错了。

| 维度 | 评价 |
|------|------|
| 架构铁律（Godot 不权威 / MuJoCo 不叙事） | 未破 |
| 数据管道（录、回放、导出） | 超前、可用 |
| 控制与任务深度 | **滞后 · 纠偏主战场** |
| 城市观感 / seed / 路面 | 已够用；纠偏期克制再扩 |

### 纠偏计划（方向已定，细项待讨论）

原则：**先加深控制与任务，再扩关卡皮与公网。**

| ID | 主题 | 一句话 |
|----|------|--------|
| **V1** | 控制升维 | `joint_targets`（或轮臂混合），与 `joints` 成对录制 |
| **V2** | 机体升维 | 多关节 / 非纯 planar 主线机体 |
| **V3** | 接触任务 | 推箱升级：对准、堆叠、门/抓取；失败可纠偏 |
| **V4** | 数据分层 | outcome + 子目标 + 难度进 header / 导出 |
| **V5** | 演示克制 | 城市皮只必要修补，不再开地图包专题 |

公网 HTTPS、T2.7 手感补偿仍可暂缓。  
**具体勾选等本轮文档入库后的 todo 讨论** 再写入 `docs/09-todo.md`。

---

## 本地 5 分钟演示

### A. 编辑器预览

```bash
cd mineworld
source .venv/bin/activate
python gateway/echo_server.py --physics mujoco
godot --path godot/spike    # 或 F5；主场景 demo_city
```

### B. Web 本地 Demo

```bash
bash scripts/export_godot.sh web
.venv/bin/python gateway/echo_server.py --physics mujoco   # 终端 1
bash scripts/serve_web.sh restart                          # 终端 2 → http://127.0.0.1:8080/
```

- 通关：沿街道东行至绿色终点；右下角可换 **seed** 重生街区  
- 录制：右上角 **Recordings** → 2D Play / **3D Replay**（`/?replay=<session_id>`）  
- 导出：`GET /api/recordings/export.csv` 或  
  `.venv/bin/python scripts/export_trajectories.py --rebuild-index`

可选：`window.MINEWORLD_GATEWAY = "ws://127.0.0.1:8765"`；`?room=demo` 本机双人。  
托管必须带 COOP/COEP（`serve_web_demo.py` 已加）；勿直接双击 `index.html`。

### C. 冒烟

```bash
.venv/bin/python scripts/ws_smoke_test.py
.venv/bin/python scripts/push_box_smoke.py
.venv/bin/python scripts/ws_smoke_test.py --expect-objective   # demo_city 开环到终点
```

### D. macOS 桌面包（备选）

```bash
bash scripts/export_godot.sh macos
open dist/macos/MineWorldSpike.app
```

详见 [gateway/README.md](gateway/README.md) · [godot/spike/README.md](godot/spike/README.md) · [docs/adr/003](docs/adr/003-client-engine-godot.md)。

首次环境：

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt
```

---

## 文档导航

| 文档 | 说明 |
|------|------|
| **[docs/15-course-correction.md](docs/15-course-correction.md)** | **跑偏纪要与纠偏计划（当前战略 SSOT）** |
| [docs/00-vision.md](docs/00-vision.md) | 愿景、问题陈述、产品定位 |
| [docs/01-architecture.md](docs/01-architecture.md) | 系统架构、职责边界、数据流 |
| [docs/02-scene-contract.md](docs/02-scene-contract.md) | 场景契约：Godot 关卡 → MuJoCo 世界映射 |
| [docs/03-websocket-protocol.md](docs/03-websocket-protocol.md) | WebSocket 消息协议（cmd / state / event） |
| [docs/04-data-collection.md](docs/04-data-collection.md) | 会话录制 schema、遥操与交互数据采集 |
| [docs/05-godot.md](docs/05-godot.md) | Godot 本地环境、坐标映射、导出 |
| [docs/06-mujoco.md](docs/06-mujoco.md) | MuJoCo 无头仿真与网关 |
| [docs/07-tooling.md](docs/07-tooling.md) | 工具链 |
| [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md) | 学习/娱乐/商业模式与路线图 |
| [docs/09-todo.md](docs/09-todo.md) | **可执行待办清单（当前执行入口）** |
| [docs/10-open-questions.md](docs/10-open-questions.md) | 待决事项 |
| [docs/11-poc-mvp-architecture.md](docs/11-poc-mvp-architecture.md) | POC 规格 + MVP 目标架构 |
| [docs/12-status-review.md](docs/12-status-review.md) | 阶段回顾与方案评审 |
| [docs/13-web-multiplayer-demo.md](docs/13-web-multiplayer-demo.md) | Web / 多人 Demo |
| [docs/14-godot-mujoco-fusion.md](docs/14-godot-mujoco-fusion.md) | Godot ↔ MuJoCo 融合与 URDF |
| [docs/README.md](docs/README.md) | 文档目录索引 |
| [schemas/README.md](schemas/README.md) | JSON Schema SSOT |
| [docs/adr/001-dual-engine-split.md](docs/adr/001-dual-engine-split.md) | ADR：双引擎职责分离 |
| [docs/adr/002-authority-and-sync.md](docs/adr/002-authority-and-sync.md) | ADR：物理权威与时序同步 |
| [docs/adr/003-client-engine-godot.md](docs/adr/003-client-engine-godot.md) | ADR：客户端引擎 → Godot |

---

## 仓库结构

```
mineworld/
├── README.md                 # 本文件（含跑偏/纠偏摘要）
├── docs/                     # 设计文档（15 = 纠偏 SSOT）
├── godot/                    # Godot 客户端（spike 基线 + 导出预设）
├── gdevelop/                 # Legacy：GDevelop 存档（不再演进）
├── gateway/                  # WS 网关 + 录制 + fake/mujoco + recording_store
├── mujoco/                   # MJCF、无头验收脚本
├── schemas/                  # JSON Schema（场景契约、录制格式）
├── examples/                 # 契约 / WS / 录制样例
├── scripts/                  # 冒烟、Web 托管、街区生成、轨迹导出
└── dist/                     # 本地导出产物（gitignore）
```

---

## 最小可玩闭环（已达成的 POC 形态）

1. 进世界（Web 或编辑器 · `demo_city`）
2. 接管机甲（T）并遥操（WASD/QE）
3. 状态由 MuJoCo 驱动回显
4. 到达终点 / 推箱等事件可触发
5. 会话落盘，可在 Recordings 回放并导出 CSV

**下一阶段**不再以「更好看的城」为主，而以 [15](docs/15-course-correction.md) 的 **V1–V4 数据价值** 为主。详见 [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md)。
