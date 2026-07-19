# MineWorld

> Godot 世界编辑 + MuJoCo 机甲物理权威 + WebSocket 桥接的仿真娱乐与遥操数据采集底座
>
> 做的不是游戏，也不是仿真器，而是「用游戏壳规模化采集真物理人类遥操数据」的管道。

| 字段 | 值 |
|------|-----|
| **状态** | POC M1–M4 已入库；**主线转向 Web Demo（W1→W3 多人）**；T2.7 手感暂缓 |
| **创建日期** | 2026-07-17 |
| **定位** | 「头号玩家」式初始底座：可编辑共享世界 + 真物理机体 + 可回放的人类行为档案 |
| **阶段评审** | [docs/12-status-review.md](docs/12-status-review.md) |
| **Web / 多人** | [docs/13-web-multiplayer-demo.md](docs/13-web-multiplayer-demo.md) |

---

## 一句话

**Godot 负责关卡/任务/地图与可视化 Viewer；无头 MuJoCo 负责机甲关节级物理仿真；WebSocket 交换控制与状态；旁路录制遥操与交互轨迹，支撑学习、娱乐与商业多种模式。**

POC 机甲为**自建盒子**（验证权威链路与协议）；真实人形/四足 MJCF 是后置换皮，不改 WS 契约形状。交付重心转向 **浏览器可玩的线上 Demo**（先单人可部署，再会话隔离，再同关多人）。

---

## 本地 5 分钟演示

### A. 编辑器预览

```bash
cd mineworld
source .venv/bin/activate
python gateway/echo_server.py
godot --path godot/spike    # 或 F5
```

### B. Web 本地 Demo（当前主线 W1）

```bash
# 一次：Godot → 管理导出模板 → 安装 **Web**（版本对齐编辑器）
bash scripts/export_godot.sh web
python gateway/echo_server.py                 # 终端 1
python scripts/serve_web_demo.py              # 终端 2 → http://127.0.0.1:8080/
```

可选：页面注入 `window.MINEWORLD_GATEWAY = "ws://127.0.0.1:8765"`。  
托管必须带 COOP/COEP（`serve_web_demo.py` 已加）；勿直接双击 `index.html`。

### C. macOS 桌面包（备选）

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
| [docs/00-vision.md](docs/00-vision.md) | 愿景、问题陈述、产品定位（RPO 底座叙事） |
| [docs/01-architecture.md](docs/01-architecture.md) | 系统架构、职责边界、数据流 |
| [docs/02-scene-contract.md](docs/02-scene-contract.md) | 场景契约：Godot 关卡 → MuJoCo 世界映射 |
| [docs/03-websocket-protocol.md](docs/03-websocket-protocol.md) | WebSocket 消息协议草案（cmd / state / event） |
| [docs/04-data-collection.md](docs/04-data-collection.md) | 会话录制 schema、遥操与交互数据采集 |
| [docs/05-godot.md](docs/05-godot.md) | Godot 本地环境、坐标映射、导出与无头自动化 |
| [docs/06-mujoco.md](docs/06-mujoco.md) | MuJoCo 无头仿真、网关职责、与现网资产对齐 |
| [docs/07-tooling.md](docs/07-tooling.md) | Blender / Godot / MCP / CLI 工具链 |
| [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md) | 学习/娱乐/商业模式与 MVP 路线图 |
| [docs/09-todo.md](docs/09-todo.md) | **可执行待办清单（当前执行入口）** |
| [docs/10-open-questions.md](docs/10-open-questions.md) | 待决事项与评审清单 |
| [docs/11-poc-mvp-architecture.md](docs/11-poc-mvp-architecture.md) | **POC 规格 + MVP 目标架构（讨论入口）** |
| [docs/12-status-review.md](docs/12-status-review.md) | **阶段回顾与方案评审（2026-07-19）** |
| [docs/13-web-multiplayer-demo.md](docs/13-web-multiplayer-demo.md) | **Web / 线上多人 Demo 路线与审核** |
| [schemas/README.md](schemas/README.md) | **JSON Schema SSOT 与扩展规则** |
| [docs/adr/001-dual-engine-split.md](docs/adr/001-dual-engine-split.md) | ADR：双引擎职责分离 |
| [docs/adr/002-authority-and-sync.md](docs/adr/002-authority-and-sync.md) | ADR：物理权威与时序同步 |
| [docs/adr/003-client-engine-godot.md](docs/adr/003-client-engine-godot.md) | ADR：客户端引擎 GDevelop → Godot（含 POC 过程） |

---

## 仓库结构（规划）

```
mineworld/
├── README.md                 # 本文件
├── docs/                     # 设计文档
├── godot/                    # Godot 客户端（spike 基线 + 导出预设）
├── gdevelop/                 # Legacy：GDevelop 时代存档（不再演进，ADR-003）
├── gateway/                  # WS 网关 + 录制 + fake/mujoco 物理
├── mujoco/                   # MJCF、无头验收脚本
├── schemas/                  # JSON Schema（场景契约、录制格式）
├── examples/                 # 契约 / WS / 录制样例
├── scripts/                  # 冒烟、回放、导出
└── dist/                     # 本地导出产物（gitignore）
```

---

## 最小可玩闭环（MVP 目标）

1. 进世界（Godot 大厅/入口场景）
2. 选一关、选一机甲
3. 玩家接管遥操
4. 状态由 MuJoCo 驱动回显
5. 会话落盘，可回放

详见 [docs/08-modes-roadmap.md](docs/08-modes-roadmap.md)。
