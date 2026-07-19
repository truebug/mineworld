# 14 · Godot 场景与 MuJoCo 仿真的交互融合

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **目标** | 在不破坏「Gateway 权威」的前提下，让 Godot 关卡/外观与 MuJoCo 物理世界更一致、更可玩、更可换真机模型 |
| **关联** | [01](01-architecture.md) · [02](02-scene-contract.md) · [05](05-godot.md) · [06](06-mujoco.md) · [09](09-todo.md) · [adr/001](adr/001-dual-engine-split.md) · [adr/002](adr/002-authority-and-sync.md) |

> 方向来自 W2.3/W3 本机多人验收之后：下一阶段重心从「能连能控」转为 **场景/模型融合 + 可视化提升**，并探索 **真实 URDF/MJCF** 换皮。

---

## 1. 问题陈述

当前 POC 已验证：

- Godot 做 Viewer + 输入；Gateway + MuJoCo（或 fake）做权威
- 契约障碍物可进 MuJoCo；state 驱动傀儡；`demo` 房两人同关

仍粗的地方：

| 缺口 | 表现 |
|------|------|
| **视觉 ≠ 物理语义** | Godot 胶囊傀儡 ↔ MuJoCo 盒子机甲，只靠 pose 对齐 |
| **关卡双边维护** | `.tscn` 摆件与契约/`MjSpec` 障碍需人工对齐 |
| **真机模型未进主线** | 仍用自建 `box_mech.xml`；URDF/第三方 MJCF 未接 |
| **场景贫瘠** | tutorial_01 平面 + 墙；tutorial_02 城市资产未成「仿真同源」 |

**融合**不是把 MuJoCo 嵌进 Godot，而是：**同一逻辑世界用两套呈现**——Godot 做好看可玩的壳，MuJoCo 做可信动力学；契约与 `model_ref` 是胶水。

---

## 2. 铁律（不可破）

1. Godot **不**权威物理；不回写接触/关节到仿真。  
2. MuJoCo **不**做关卡编辑器与叙事 UI。  
3. 换真机模型 = 换 `model_ref` + 控制映射，**不改** WS 信封主形状。  
4. 资产仅 CC0/MIT（或已登记归因）；见各目录 `ASSETS.md`。  
5. 坐标仍为米 · 右手 · Z-up；Godot 映射保持现有约定。

---

## 3. 融合架构（目标态）

```text
┌─────────────────────┐         scene contract + model_ref
│  Godot 关卡 / 编辑   │ ──────► schemas/examples/contracts
│  网格 · 装饰 · 灯光  │              │
└─────────────────────┘              ▼
                              ┌──────────────┐
                              │   Gateway    │
                              │  Room/tick   │
                              └──────┬───────┘
                     cmd / state     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
     Godot 傀儡渲染            MuJoCo MjModel/Data      录制 frames
     (mesh / 材质 / 标签)      (URDF→MJCF 或 MJCF)     joints/pose
```

**两种对齐策略（可并存）**：

| 策略 | 做法 | 适用 |
|------|------|------|
| **A. 契约驱动物理** | Godot 导出/手写契约 → Gateway 编译进 MjSpec | 静态障碍、触发器（现状 T2.3） |
| **B. 模型驱动双端** | 同一 `model_ref`：MuJoCo 吃 MJCF；Godot 吃配套 mesh（GLB） | 机甲、可动装置 |
| **C. 视觉仅装饰** | Godot 摆树/招牌等，标 `physics_role: viewer_only` | 不进 MuJoCo，降对齐成本 |

推荐默认：**机甲走 B，关卡静态走 A，装饰走 C**。

---

## 4. URDF / 真机模型路径

### 4.1 原则

- **仿真侧 SSOT 仍是 MJCF**（MuJoCo 原生）。URDF 作为**进口格式**：离线或启动时转为 MJCF（`compile` / 社区转换 / 手写薄包装）。  
- Godot **不**直接解析 URDF 做物理；只加载与之配套的 **视觉 mesh**（或简化胶囊，直到 mesh 就绪）。  
- 控制接口继续 `velocity`（或后续 `joint_targets`），关节名对齐 `joints` 出口（T2.6 已铺路）。

### 4.2 建议分期

| 阶段 | 内容 | 验收 |
|------|------|------|
| **F0** | 多人外观区分（A/B 染色 + 标签） | `?room=demo` 一眼可辨 | Done |
| **F1** | tutorial 场景加 CC0 装饰（viewer_only）+ 地面材质 | 不改物理，观感提升 | Done |
| **F2** | 自研 `planar_cart.urdf` → MJCF + `model_ref` | headless + smoke 能控 | Done |
| **F3** | Godot 视觉与 URDF 几何对齐（底盘/轮/鼻） | 位姿仍跟 state | Done |
| **F4** | 契约导出：从 `.tscn` 抽取障碍/trigger/spawn（T4.2） | `scripts/export_scene_contract.py --check` | Done |
| **F5** | 第三方 DiffBot URDF → planar MJCF 换皮 | headless + mujoco smoke；协议仍 velocity | Done |

**非目标（本阶段）**：在 Godot 内嵌 MuJoCo；自动从任意 URDF 一键生成完整可玩关；人形全身遥操手感（T2.7）。

---

## 5. 可视化改善（克制）

优先「有效装饰」而非重做引擎：

1. **机甲身份色**（F0）— 已落地方向。  
2. **tutorial_01 铺装**：地面贴图 / 简易护栏 / 终点标牌（CC0）。  
3. **tutorial_02 对齐**：城市资产保留为 viewer；物理障碍仍契约盒子。  
4. **灯光与天空**：轻微提对比，避免紫/霓虹风。  
5. 真模型到来后再替换胶囊，避免过早精修盒子美术。

---

## 6. 与现有主线关系

| 主题 | 状态 | 与本文关系 |
|------|------|------------|
| W2.3 / W3 / T2.6 | Done | 多人与 joints 为融合前置 |
| 公网 W2.1/2/4 | 暂缓 | 不阻塞 F0–F2 |
| 机甲互撞 | 可选 | 共享 MjData；可与 F2 后并行 |
| T4.2 契约导出 | Later | 对应 F4 |

执行勾选以 [09-todo](09-todo.md) 为准。

---

## 7. 开放决策（需产品拍板时再 ADR）

1. 首个真机模型候选：Unitree 系开源 MJCF vs 自研简化腿式 vs 继续盒子加装饰？  
2. URDF→MJCF 工具链：仓库脚本 vs 外部预编译产物入库？  
3. 关节控制是否从 `velocity` 基座扩展到 `joint_targets`（协议加字段，v0 兼容）？

未拍板前：**F0–F5 已落地**；下一步可选：真差速轮动、更复杂真机 URDF、互撞、公网 W2。

### F2 / F4 / F5 命令

```bash
# F5 default skin (DiffBot → diffbot_planar.xml)
.venv/bin/python mujoco/scripts/urdf_to_mjcf_planar.py --check
.venv/bin/python mujoco/scripts/headless_run.py
.venv/bin/python scripts/export_scene_contract.py --check
.venv/bin/python gateway/echo_server.py --physics mujoco
.venv/bin/python scripts/ws_smoke_test.py
```

默认机甲：`mechs/diffbot_planar.xml`（源 URDF：`third_party/diffbot/diffbot.urdf`，Apache-2.0）。  
`planar_cart` 仍可 `--urdf/--out` 重新生成作 fallback。  
Godot `mech_puppet.gd` 尺寸与 DiffBot URDF 对齐；队伍色只染底盘。  
注意：仓库目录名 `mujoco/` 会遮蔽 pip 包，脚本内已把 repo root 从 `sys.path` 去掉再 `import mujoco`。
