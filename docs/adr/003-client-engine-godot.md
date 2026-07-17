# ADR-003：客户端引擎切换 GDevelop → Godot

| 字段 | 值 |
|------|-----|
| **状态** | Accepted |
| **日期** | 2026-07-17 |
| **决策编号** | ADR-MW-003 |
| **修订** | [ADR-001](001-dual-engine-split.md)（客户端引擎具体选型被本决策替换） |
| **落地证据** | `godot/spike/`（含 M1 无头验收输出） |

---

## 背景

ADR-001 确立了双引擎架构，并选定 GDevelop 作为客户端引擎。POC-A（M1 连通）用 GDevelop demo0 打通后，在正式投入 POC-B 之前，我们用一个等价 spike 重新评估了客户端引擎选型。此时切换的沉没成本最低：GDevelop 侧仅 demo0 一个场景（约 1 天工作量），契约/协议/Schema/Gateway/录制全部在引擎之外，不受影响。

## 决策

**客户端引擎由 GDevelop 切换为 Godot 4（当前 4.6.2）。**

ADR-001 的双引擎职责分离**不变**；本决策只替换「游戏引擎」一侧的具体实现：

1. **Godot 4**：世界编辑产物运行时呈现、任务/UI、输入、Viewer、客户端发布。
2. **MuJoCo**：机甲及契约内物理实体的仿真权威。
3. **Gateway + WebSocket**：唯一集成边界，载荷为 JSON 文本（不变）。

## 理由

| 维度 | GDevelop | Godot 4 | 对本项目的影响 |
|------|----------|---------|----------------|
| 3D 能力 | 2D 引擎后期叠加（Three.js） | 一等公民 3D | 核心场景是 3D 机甲回显；GDevelop 相机/光照/动画会很快触顶 |
| 状态插值傀儡 | 需掉进 JavaScript Code 事件，与事件表混编 | 十几行 GDScript（见 `godot/spike/scripts/mech_puppet.gd`） | V3（时序/插值）是 POC 验收硬指标，开发体验差距大 |
| 资产管线 | GLB 可用但生态弱 | glTF/GLB 一等公民 | 现网资产已是 GLB |
| 团队语言一致性 | JS 事件表 + JS 扩展 | GDScript ≈ Python 风格 | 与 Gateway（Python）同构，切换成本低 |
| WebSocket | 官方 WebSocket Client 扩展（文本） | 内置 `WebSocketPeer`（文本/二进制） | 协议零改动；未来有二进制通道空间 |
| CI / 无头验证 | gdexporter（社区）或 Electron `--run-command` | 原生 `--headless --script` | M1 可无头自动验收（见「POC 过程」） |
| 导出形态 | HTML5 纯 JS 小包（优势） | Web 导出包体大、需 COOP/COEP；原生桌面/移动干净 | GDevelop 唯一保留优势，MVP 阶段非硬需 |
| 无代码编辑 | 事件表，非程序员可搭关卡（优势） | 编辑器面向开发者 | 仅当「玩家 UGC 搭世界」是硬诉求才翻盘（见「翻盘条件」） |

**关键判断**：短期内关卡由开发者手写契约/搭场景（`10-open-questions` C1：MVP 手写、编辑器扩展后置 P1），ADR-001 也明确不把编辑器 SaaS 化——因此 GDevelop 的「无代码 UGC」优势在 MVP 阶段用不上，而它的 3D/插值短板恰好卡在 POC 验证路径上。

## 架构变动

集成边界、协议、Schema、坐标系（米·右手·Z-up）、冻结频率（dt=0.02 / sim 50Hz / state 20Hz）、录制管道**全部不变**。变动集中在客户端一侧：

| 项 | 变动前（GDevelop） | 变动后（Godot 4） |
|----|--------------------|--------------------|
| 工程目录 | `gdevelop/` | `godot/`（`gdevelop/demo0` 保留为历史 spike，不再演进） |
| WS 接入 | WebSocket Client 扩展 | 内置 `WebSocketPeer`，封装 `MWWsClient` |
| 轴映射 | 引擎内 JS 换算 | `godot = (x, z, -y)`，`rotation.y = yaw`，集中在傀儡脚本一处 |
| 客户端工程文件 | `game.json`（单文件 JSON） | `project.godot` + `*.tscn` + `*.gd`（文本，Git 友好） |
| 无头验收 | 无（靠人工预览） | `godot --headless --script res://headless/smoke_client.gd` |
| 契约自动导出（P1） | GDevelop 扩展读 `game.json` | Godot 编辑器插件读 `.tscn`（更直接） |
| 渲染表现 | Three.js 3D 叠加层 | 原生 3D 场景/相机/光照 |

双世界一致性治理（`physics_role`、tick 为 SSOT、插值策略）沿用 ADR-002，无任何放松。

## POC 过程（本次 spike 实录）

目标：复刻 M1 同款验收（`docs/11` §7.1），证明「换引擎后集成风险不升反降」。

| 步骤 | 内容 | 结果 |
|------|------|------|
| S1 | 环境：Python venv + `websockets`，启动 `gateway/echo_server.py`（`ws://127.0.0.1:8765`） | `scripts/ws_smoke_test.py` → `smoke OK` |
| S2 | 新建 `godot/spike` 工程：3D 场景（地面/墙/终点区/胶囊/相机/HUD）+ `MWWsClient` + `MWMechPuppet` | 工程可文本化提交，无二进制资产 |
| S3 | 无头协议验收：`godot --headless --path godot/spike --script res://headless/smoke_client.gd` | hello → join → `event player_take_control` → state x 0.04→1.42 递增 → **`smoke OK`，exit 0** |
| S4 | 主场景无头加载：连接、hello/scene 正常、无脚本错误 | 通过 |
| S5 | 可视化手感验收（人工，F5 运行；WASD/QE） | 胶囊随 20Hz state 插值平滑移动；杀 Gateway 后傀儡即停（权威在服务端） |

对照 `docs/11` §7.1（M1）：gateway 可启动 ✅ · 独立脚本完成 hello→join→state ✅（Godot 无头脚本，含 x 增大断言）· 客户端连接/键盘 cmd/3D 对象随 state 移动 ✅ · 协议字段与 `03` 一致、无私货 ✅。

**结论**：M1 在 Godot 侧复现成功，且多出一个 GDevelop 时代没有的资产——**可 CI 化的无头协议验收脚本**。

## 后果

| 正面 | 代价 |
|------|------|
| 3D/相机/动画/插值进入引擎主场 | GDevelop demo0 弃用（沉没 ≈1 天） |
| 无头验收进 CI，M2/M3 回归可自动化 | Web 分发变重（包体大、COOP/COEP），MVP 先用原生桌面/预览 |
| GDScript 与 Gateway Python 同构，一人可贯通全栈 | 无代码 UGC 搭世界的路径后置（见翻盘条件） |
| 契约导出可走编辑器插件直读 `.tscn` | 文档体系需批量改术语（本次一并完成） |

## 翻盘条件（何时应重新评估回 GDevelop 或另选）

1. 「非程序员/玩家在编辑器内搭关卡」成为 MVP 后的**硬性产品诉求**（UGC 共享世界），且不愿为此自建工具。
2. 分发必须**极轻量纯 Web**（点开即玩、不可装包），且无法接受 Godot Web 导出的包体与响应头要求。

触发任一条，回到本 ADR 复议；双引擎边界（ADR-001）与协议（`03`）保证再次切换的成本仍然可控。

## 不采纳

- 继续 GDevelop 到 POC-B 再说：插值与 3D 表现恰是 POC-B/MVP 高频改动区，越往后切换越贵。
- 自研 Viewer（Three.js/Babylon 手写）：编辑器能力归零，违背 ADR-001「不重复造编辑器」。
