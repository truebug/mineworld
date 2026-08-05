# 28 · 真机接入计划（hw_* 后端 · 桌面键鼠遥操）

| 字段 | 值 |
|------|-----|
| **状态** | Draft · 待评审 |
| **日期** | 2026-08-05 |
| **关联** | [00-vision.md](00-vision.md) · [09-todo.md](09-todo.md) · [16-value-sprint.md](16-value-sprint.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) · [27-pico-webxr.md](27-pico-webxr.md) |

> MineWorld 的真机线：**台式机普通浏览器 + 键盘鼠标** 遥操边缘真机（SO-101、JetRover，后续 G1 / Go 系列），  
> 不依赖 Pico / WebXR / 游戏手柄。真机通过**仓外闭源桥接服务**接入，本仓只定义开放协议与客户端。

---

## 1. 边界原则（SSOT · 合规红线）

| 原则 | 说明 |
|------|------|
| **黑盒对接** | 真机桥接服务（下称 `arm-bridge`）是商业闭源、含私有资产（真机资源、部署凭证、串口拓扑）的外部服务；其实现、端点、凭证 **永不进入本仓**。 |
| **本仓只有协议** | 本仓只落：开放 WS 协议子集（`schemas/`）、Gateway `hw_*` 适配层、Godot 键鼠前端、录制 schema。协议文档不得出现真实主机名/IP/端口/token。 |
| **凭证零入库** | 连接串（URL/token）一律走环境变量（如 `MW_HW_BRIDGE_URL` / `MW_HW_BRIDGE_TOKEN`），本地 `.env` 与 `docs/ops.local.md` 均 gitignore。 |
| **安全在边缘** | 急停、软限位 clamp、速率上限、鉴权、断线归零——全部归 bridge/边缘侧；Gateway 不做真机安全兜底，只透传与录制。 |
| **仿真可独立** | `hw_fake` 仿真后端（无硬件）必须能跑通全链路，保证开源贡献者无真机也能开发/冒烟。 |

> 类比：本仓之于 `arm-bridge`，正如本仓之于 PMS/Spaces——统一前台对接外部执行能力（[21](21-ecosystem-federation.md)），不吞并实现。

---

## 2. 拓扑

```text
台式机浏览器（Godot Web · 键盘+鼠标）
   │  cmd.velocity / cmd.joint_targets（MW 协议 · 现有通道）
   ▼
MineWorld Gateway --physics hw_so101|hw_jetrover|hw_fake
   │  薄翻译层（本仓新增 · 唯一新代码）
   │  WS 客户端 → 仓外 arm-bridge（黑盒 · 商业服务）
   ▼
┌──────────────────────────────┐
│ arm-bridge（仓外 · 闭源）      │  急停/限位/鉴权/串口
│  ├─ SO-101（Feetech 总线）    │
│  ├─ JetRover（rosbridge）     │
│  └─ G1 / Go 系列（后续）       │
└──────────────────────────────┘
   │ state ~20 Hz（present/goal）→ Gateway → MW state.joints
   ▼
录制：既有 recording_store（真机示教 = IL 飞轮同一 schema）
```

---

## 3. 协议对齐（开放子集 · 本仓 SSOT）

| MW（本仓） | arm-bridge（外部 · 仅引用语义） | 翻译 |
|-----------|------------------------------|------|
| `cmd.velocity`（底盘 vx/ω） | `dq`（counts/s 增量）/ Twist | 量纲换算 + 限幅 |
| `cmd.joint_targets`（关节目标） | `joint_targets` / `go_to_xyz` | 名字映射（`arm_*`/`gripper` ↔ 电机 ID） |
| `state.joints`（关节角/速度） | `state.present` / `goal` | counts → rad（按机型换算表，表本身无私密信息） |
| enable / 僵尸手 | `enable` 语义 | 断线/离房 → 发 `enable=false` 一次（安全归零仍在 bridge 侧兜底） |

- 机型换算表（关节名、软限位弧度、HOME 弧度）属于**公开机械参数**，可入本仓 `examples/contracts/hw_*.json`；不含任何部署信息。
- 真机房强制 `max_members=1` + 超员旁观（复用 B3 spectate 机制）。

---

## 4. 切片计划

| 步 | 做啥 | 验收 |
|----|------|------|
| HW-0 | ADR 冻结边界（本文 §1）+ `hw_fake` 仿真后端（关节积分+限位+HOME，参考公开 SO-101 规格） | `ws_smoke` 带 `--physics hw_fake` 通过 |
| HW-1 | Godot `demo_arm_lab`：键盘关节增量（仿既有键位习惯）+ HUD 关节条；鼠标点选发 `joint_targets` | 桌面 Web 硬刷新可玩 fake 臂 |
| HW-2 | 翻译层接真 bridge（env 配置 URL/token）；录制进 session | 真机示教落 `recordings/`；旁观席位可看 |
| HW-3 | 第二机型（JetRover 底盘+臂）；机型表驱动 | 切契约即换机；双机冒烟 |
| HW-4 | 视频皮肤（可选）：既有公网视频反代嵌 HUD | 遥操同时见真机画面 |

**不做**：不搬 arm 仓代码/部署脚本；不在 Gateway 实现急停；不做 Pico/WebXR 前端（那是 arm 仓定位）；G1/Go2 等按 HW-3 模式后挂。

---

## 5. 风险

| 风险 | 缓解 |
|------|------|
| 协议语义漂移（外部 bridge 演进） | 翻译层集中一处；契约测试钉住开放子集 |
| 真机独占与排队 | `max_members=1` + spectate；远期预约队列（不在本刀） |
| 速率域不匹配（MW 50Hz vs 真机 ~20Hz） | `hw_*` 后端独立 tick，不套 MuJoCo substeps |
| 误把私有信息写进本仓 | 文档评审 checklist；`ops.local.md` 惯例延续 |
