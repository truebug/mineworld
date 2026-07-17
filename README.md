# MineWorld

> GDevelop 世界编辑 + MuJoCo 机甲物理权威 + WebSocket 桥接的仿真娱乐与遥操数据采集底座

| 字段 | 值 |
|------|-----|
| **状态** | 规划 / 文档先行 |
| **创建日期** | 2026-07-17 |
| **定位** | 「头号玩家」式初始底座：可编辑共享世界 + 真物理机体 + 可回放的人类行为档案 |

---

## 一句话

**GDevelop 负责关卡/任务/地图与可视化 Viewer；无头 MuJoCo 负责机甲关节级物理仿真；WebSocket 交换控制与状态；旁路录制遥操与交互轨迹，支撑学习、娱乐与商业多种模式。**

---

## 快速开始（POC-A Gateway）

```bash
cd mineworld
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt
python gateway/echo_server.py          # ws://127.0.0.1:8765
# 另开终端：
python scripts/ws_smoke_test.py        # 期望 smoke OK
```

详见 [gateway/README.md](gateway/README.md)。下一步：GDevelop 连同一地址（T1.3–T1.4）。

---

## 文档导航

| 文档 | 说明 |
|------|------|
| [docs/00-vision.md](docs/00-vision.md) | 愿景、问题陈述、产品定位（RPO 底座叙事） |
| [docs/01-architecture.md](docs/01-architecture.md) | 系统架构、职责边界、数据流 |
| [docs/02-scene-contract.md](docs/02-scene-contract.md) | 场景契约：GDevelop 关卡 → MuJoCo 世界映射 |
| [docs/03-websocket-protocol.md](docs/03-websocket-protocol.md) | WebSocket 消息协议草案（cmd / state / event） |
| [docs/04-data-collection.md](docs/04-data-collection.md) | 会话录制 schema、遥操与交互数据采集 |
| [docs/05-gdevelop.md](docs/05-gdevelop.md) | GDevelop 本地环境、扩展、导出与自动化 |
| [docs/06-mujoco.md](docs/06-mujoco.md) | MuJoCo 无头仿真、网关职责、与现网资产对齐 |
| [docs/07-tooling.md](docs/07-tooling.md) | Blender / GDevelop / MCP / CLI 工具链 |
| [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md) | 学习/娱乐/商业模式与 MVP 路线图 |
| [docs/09-todo.md](docs/09-todo.md) | **可执行待办清单（当前执行入口）** |
| [docs/10-open-questions.md](docs/10-open-questions.md) | 待决事项与评审清单 |
| [docs/11-poc-mvp-architecture.md](docs/11-poc-mvp-architecture.md) | **POC 规格 + MVP 目标架构（讨论入口）** |
| [schemas/README.md](schemas/README.md) | **JSON Schema SSOT 与扩展规则** |
| [docs/adr/001-dual-engine-split.md](docs/adr/001-dual-engine-split.md) | ADR：双引擎职责分离 |
| [docs/adr/002-authority-and-sync.md](docs/adr/002-authority-and-sync.md) | ADR：物理权威与时序同步 |

---

## 仓库结构（规划）

```
mineworld/
├── README.md                 # 本文件
├── docs/                     # 设计文档
├── gdevelop/                 # GDevelop 工程（待建）
├── gateway/                  # WS 网关 + 场景契约转换（待建）
├── mujoco/                   # MJCF、控制接口、无头运行脚本（待建）
├── schemas/                  # JSON Schema（场景契约、录制格式）
└── examples/                 # 最小可玩闭环示例（待建）
```

---

## 最小可玩闭环（MVP 目标）

1. 进世界（GDevelop 大厅/入口场景）
2. 选一关、选一机甲
3. 玩家接管遥操
4. 状态由 MuJoCo 驱动回显
5. 会话落盘，可回放

详见 [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md)。
