# 16 · 数据价值冲刺（V 线冻结规格）

| 字段 | 值 |
|------|-----|
| **状态** | Active · 产品决策已冻结 |
| **日期** | 2026-07-19 |
| **仓库** | https://github.com/truebug/mineworld |
| **执行勾选** | [09-todo.md](09-todo.md) `Now（V）` |
| **战略背景** | [15-course-correction.md](15-course-correction.md) |
| **数据用途** | **优先服务 IL / 行为克隆**（成功示范为主；失败样本为辅） |

> 本文把「拍板后的纠偏」落成可执行规格：机体、UX、关卡、任务与验收。  
> 改规格先改本文 + `09`；实现细节仍服从 ADR 铁律。

---

## 1. 已冻结的产品决策（2026-07-19）

| # | 议题 | 决策 |
|---|------|------|
| 1 | 下一机体形态 | **平面底盘 + 附加臂/夹爪**（不直接上全身人形） |
| 2 | 控制 UX | **键鼠 + 关节滑条**（Web/桌面同一套语义） |
| 3 | 主关卡 | **新开 `demo_workshop`：较大室内封闭车间/沙盘**（`demo_city` 降为次要壳） |
| 4 | 数据用途优先级 | **近期服务 IL / 行为克隆** |

推论：

- 成功通关轨迹是正样本；失败/中止也要可筛（负样本或过滤掉）。
- 录制必须能稳定导出 **`cmd`（含 joint_targets）↔ `joints`/`joint_vels` 成对**。
- 车间关服务「对准 / 抓取或推入料箱」类接触子目标，而不是街道巡航。

---

## 2. 目标体验（验收叙事）

玩家在 **封闭大车间** 内：

1. 底盘仍可用 WASD/QE 粗定位（`velocity` 保留）。
2. 用 **关节滑条 / 快捷键** 控制臂与夹爪（`joint_targets`）。
3. 完成 IL 友好任务：例如 **把箱子推入/放入目标料箱区**（首版允许「夹爪接触 + 推入 AABB」，真抓取动力学可第二跳）。
4. 会话落盘；Recordings / CSV 可按 `level_id=demo_workshop`、`control_mode`、`outcome` 过滤出成功示范。

---

## 3. 范围切分

### 3.1 In Scope（本冲刺）

| 域 | 内容 |
|----|------|
| 机体 | DiffBot（或现有 planar）底盘 + **2–3 DoF 臂 + 1 DoF 夹爪** MJCF；Godot 跟皮 |
| 控制 | `velocity` + `joint_targets` 并存；滑条绑定臂/爪关节名 |
| 关卡 | `demo_workshop` 契约 + Godot 场景：地面、四面墙/封闭壳、工作台、料箱区、可动物体 |
| 任务 | ≥1 个 `objective`（reach/push-into-region 或 grasp-and-place 的简化版） |
| 数据 | header 标签；export 含关节 cmd；IL 成功样本可筛 |

### 3.2 Out of Scope（明确不做）

- 全身人形 / 四足主线
- 手柄多轴 / VR
- 继续扩 `demo_city` 地图包、seed 玩法
- 公网 HTTPS、T2.7
- 自动驾驶评测集
- 真灵巧手 / 高 DoF 抓取（可作为 V3 第二跳）

---

## 4. 建议实现顺序（依赖）

```text
V4a 标签（无物理依赖）
    │
    ├─► L1 workshop 壳（契约+场景+空气墙/墙体）     ─┐
    │                                                 │
    └─► V2a 臂+爪 MJCF + Godot 皮  ─► V1a/b 协议与网关 │
                              ─► V1c 滑条 UX            ├─► V3a 车间任务
                              ─► V1d 成对录制/导出     ─┘
                                                         │
                                                         ▼
                                                      V3b 失败可筛 + V4b 导出过滤
                                                         │
                                                         ▼
                                                      V-IL smoke（一条成功示范会话）
```

并行建议：`V4a` ∥ `L1` ∥ `V2a` 开工；控制栈（V1\*）等 V2a 关节名稳定后再合入。

---

## 5. 任务 ID 与验收（与 09 对齐）

### 5.1 数据标签 · V4

| ID | 任务 | 验收 |
|----|------|------|
| **V4a** | header / index 最小 IL 标签 | 字段含：`level_id`, `task_id`, `difficulty`, `control_modes[]` 或主 `control_mode`, `outcome`, `seed`；写入 `header.json` + `index.sqlite` |
| **V4b** | 轨迹导出服务 IL | CSV/JSONL 含 `cmd` 关节目标（若有）+ `joints`；支持按 `level_id`/`outcome`/`task_id` 过滤 |

### 5.2 车间关 · L（Level）

| ID | 任务 | 验收 |
|----|------|------|
| **L1** | `demo_workshop` 契约 + 封闭车间壳 | `examples/contracts/demo_workshop.json`；四面墙/屋顶可选；spawn；无街道巡航叙事；Godot `demo_workshop.tscn`（viewer 皮可用简单几何或 CC0 室内件） |
| **L2** | 车间静态工作区 | 至少：工作台/料箱目标 AABB（trigger）、地面摩擦合理；权威墙进 `static_obstacles` |
| **L3** | 默认关切换 | Gateway 默认契约或文档明确主演示改为 workshop；Web 导出主场景可切；`demo_city` 仍可手动加载 |

### 5.3 机体 · V2

| ID | 任务 | 验收 |
|----|------|------|
| **V2a** | 底盘 + 臂 + 夹爪 MJCF | `model_ref` 可加载；headless 步进不炸；关节名稳定并写入文档表 |
| **V2b** | Godot 跟皮 | 臂/爪 mesh 或简化几何跟 `joints`；底盘沿用 DiffBot 皮 |
| **V2c** | 资产/许可登记 | `ASSETS.md` / `mujoco` 侧说明；仅 CC0/MIT 或自建 |

### 5.4 控制 · V1

| ID | 任务 | 验收 |
|----|------|------|
| **V1a** | Schema：`joint_targets` | `schemas/ws-messages.v0.json` + `examples/ws/`；与 `velocity` 可并存（同 tick 允许底盘 velocity + 臂 targets） |
| **V1b** | Gateway 执行 `joint_targets` | MuJoCo 位置伺服或等价；非法关节名 → error；smoke 改角可见 |
| **V1c** | 键鼠关节滑条 UX | Web DOM 或 Godot UI：每关节一条滑条；可选 `[` `]` / 数字键微调；文档列出映射 |
| **V1d** | 成对录制 | frames 中有 cmd 时写出关节目标；export 列对齐；回放 3D 可见臂动 |

### 5.5 任务（IL）· V3

| ID | 任务 | 验收 |
|----|------|------|
| **V3a** | 车间主目标 v1 | 推荐：**推入/置入料箱区**（`prop` 进入 trigger AABB → `objective_complete`）。允许首版「夹爪辅助推」；真抓取作为 V3c |
| **V3b** | outcome 语义服务 IL | `success` / `fail` / `abort` / `disconnect` 写入 header；失败不污染默认「正样本」导出过滤 |
| **V3c** | （可选第二跳）夹取抬起 | 夹爪闭合 + 接触 + 提升高度阈值；不阻塞 V3a |
| **V-IL** | IL 冒烟会话 | 脚本或人工：完成一次 success；`export` 滤出该 `task_id` 且 `outcome=success` ≥1 条 |

### 5.6 克制 · V5

| ID | 任务 | 验收 |
|----|------|------|
| **V5** | 演示克制 | `demo_city` 观感项默认不再开新专题；bugfix only |

---

## 6. 关节与控制约定（V2a 已钉死名）

| 子系统 | 控制 | 说明 |
|--------|------|------|
| 底盘 | `velocity` vx/vy/yaw_rate | 保留；IL 可学「接近」段 |
| 臂 | `joint_targets` 字典 `name → q` | 2–3 hinge；限幅在 MJCF |
| 夹爪 | `joint_targets` 开合 | 1 DoF；或对称两指同一目标 |

### 6.1 `mechs/diffbot_arm_gripper.xml` 关节名表

| 名 | 类型 | 用途 | 执行器 |
|----|------|------|--------|
| `slide_x` / `slide_y` / `yaw_z` | slide / hinge | 平面底盘 | `vx` / `vy` / `yaw_rate`（velocity） |
| `left_wheel_joint` / `right_wheel_joint` | hinge | DiffBot 皮（运动学） | 无 |
| `arm_yaw` | hinge Z | 臂基座偏航 | `arm_yaw`（position） |
| `arm_shoulder` | hinge Y | 上臂俯仰 | `arm_shoulder`（position） |
| `arm_elbow` | hinge Y | 肘 | `arm_elbow`（position） |
| `gripper` | slide | 指开合（0=合，0.05=开） | `gripper`（position） |

录制：每一帧若有 cmd，保留完整 payload；state 继续带全量相关 `joints`。

### 6.2 V1c 滑条映射

| UI | 关节 | 范围 |
|----|------|------|
| yaw | `arm_yaw` | −2.8 … 2.8 rad |
| shoulder | `arm_shoulder` | −1.4 … 1.6 |
| elbow | `arm_elbow` | −2.4 … 0.2 |
| gripper | `gripper` | 0 … 0.05 m（开） |

- **Web**：`shell.html` `#mw-joints` → `window.MW_JOINT_TARGETS`；与 `velocity` 同 20 Hz cmd。
- **桌面**：左下 `HSlider` 面板（`main.gd`）。
- 底盘仍 WASD/QE；T/R = 接管/释放（非夹爪）。

---

## 7. 关卡契约草图（`demo_workshop`）

```text
level_id: demo_workshop
mech_spawns: planar+arm model_ref
static_obstacles: 四面墙 + 可选立柱/工作台底座
dynamic_props: prop_crate（或小零件盒）
triggers: trigger_bin（料箱 AABB）
objectives: obj_stow_crate → reach/push into trigger_bin
tags: [poc, workshop, il, arm_gripper]
extensions.mw.editor.client_scene: res://demo_workshop.tscn
```

尺度建议（可调）：车间地面约 **20–40 m** 边长量级，封闭；比 `demo_city` 街区小、接触密度高。

---

## 8. 与现有资产关系

| 现有 | 处理 |
|------|------|
| `demo_city` | 保留；非默认主线 |
| DiffBot / F6–F8 | 底盘复用 |
| D2 推箱 | 车间任务可继承 `dynamic_props` 模式 |
| D5/D8/D13 录制回放 | 直接服务 IL 样本检查 |
| T2.6 joints 出口 | V1/V2 依赖 |

---

## 9. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-19 | 初版：四项产品决策冻结 + L/V 任务拆解；同步 09 |
| 2026-07-19 | V4a + L1 + V2a：IL header 标签、`demo_workshop`、`diffbot_arm_gripper.xml` |
| 2026-07-19 | L3：默认主场景 / Gateway 契约切到 `demo_workshop`；city 手动回切 |
| 2026-07-19 | V1a/b：`joint_targets` schema + Gateway 位置伺服；MJCF `angle=radian` |
| 2026-07-19 | V1c 滑条 + V2b 几何臂跟 `joints` |
| 2026-07-19 | 车间 Factory 皮 + 铺地；Web `#mw-hud` 点击收起；V2c 台账；本批入库 |
| 2026-07-20 | L2+V3a prop 进料箱；V1d export 成对关节列；V3b 默认 success 过滤；V4b CLI/API 过滤 |
| 2026-07-20 | V-IL：`scripts/il_smoke.py` 录制 stow → export 断言 ≥1 行 |
