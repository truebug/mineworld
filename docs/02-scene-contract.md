# 02 · 场景契约（Scene Contract）

| 字段 | 值 |
|------|-----|
| **状态** | Draft v0（Schema SSOT 已落盘） |
| **日期** | 2026-07-17 |
| **SSOT** | [`schemas/scene-contract.v0.json`](../schemas/scene-contract.v0.json) |

---

## 1. 目的

Godot 场景自由度高，MuJoCo 需要可解析、可实例化的世界描述。**场景契约**是两者之间的 SSOT：

- **输入**：Godot 编辑器插件（P1）从 `.tscn` 抽取、或 MVP 阶段手写的结构化描述。
- **输出**：Gateway 在 MuJoCo 中生成的 bodies、sites、geoms、spawn、触发器映射。

> 原则：编辑器越自由，契约字段越要严格。

---

## 2. 契约应描述什么

### 2.1 必须项（MVP）

| 类别 | 字段示例 | MuJoCo 侧 |
|------|----------|-----------|
| 元数据 | `contract_version`, `level_id`, `seed` | 会话与复现 |
| 机甲出生 | `mech_spawns[]`: id, model_ref, pose, player_slot | 加载 MJCF + 初始 qpos |
| 静态障碍 | `static_obstacles[]`: aabb / mesh_ref, pose, friction | 追加 geom 或引用子模型 |
| 任务 | `objectives[]`: type, target_id, success_condition | 网关逻辑，事件写入录制 |
| 触发器 | `triggers[]`: region, on_enter, on_exit | 网关 → `event` 消息 |

### 2.2 可选项（后续）

| 类别 | 说明 |
|------|------|
| 可交互物 | 门、开关、可推动物体；需定义是否进 MuJoCo 物理；演进分级见下 |
| 导航区 | 仅客户端 AI 或仅任务判定 |
| 环境参数 | 重力、地面材质、光照（光照仅客户端） |

#### 动态可交互物演进分级（2026-07-18 定稿）

原则：**动态元素要进 MuJoCo 物理，必须且只需进契约**；其运动驱动源永远在 Gateway/仿真侧，客户端只做插值——禁止客户端动画驱动物理（防双世界漂移，见 [adr/002](adr/002-authority-and-sync.md)）。

| 级别 | 类型 | 契约表达（草案） | Gateway 职责 | 阶段 |
|------|------|------------------|--------------|------|
| L1 | 运动学门 / 电梯 | `kinematic_obstacles[]`（轨迹/规则参数） | 每 tick 按规则推进 pose，随 `state` 广播 | Phase 3–4 |
| L2 | 可推动轻物 | `dynamic_props[]`（自由刚体 + 质量/摩擦） | 交求解器；先评估多实体 `state` 带宽（`10` N1） | P2 |
| L3 | 载具 / 多机甲 | `mech_spawns[]` 多实例 | 多控制通道 + 多傀儡（`hello.features: multi_mech`） | 远期 |

协议兼容性：均为契约/消息 payload 的**可选新增字段**，向后兼容，不触发破坏性升级（[schemas/README](../schemas/README.md) 规则 5）。

### 2.3 明确不通过契约传递

- 客户端场景脚本逻辑、UI 布局、音效资源路径（客户端本地）。
- 完整客户端工程原文（`.tscn` 等，过大且非仿真 SSOT）。

---

## 3. 导出路径（规划）

| 方式 | 说明 | 优先级 |
|------|------|--------|
| **A. 手工 JSON** | MVP 手写契约文件，Godot 场景与 JSON 人工对齐 | P0 |
| **B. Godot 编辑器插件导出** | 插件直读 `.tscn` 场景对象与元数据 → 写 JSON | P1 |
| **C. 外部工具** | Blender 布局 → 契约中的 `static_obstacles` | P2 |

---

## 4. 对象 ID 与引用规则

- 所有可引用实体使用 **全局唯一字符串 ID**（如 `spawn_mech_01`, `wall_north_03`）。
- Godot 3D 节点通过 **节点元数据（`set_meta`）** 或 **导出变量** 绑定 `mujoco_entity_id`。
- Gateway 维护 `entity_id → MuJoCo body/site 索引` 映射表，随契约热更新策略另议。

---

## 5. 物理归属分类

每个契约实体必须标注 `physics_role`：

| 值 | 含义 |
|----|------|
| `mujoco_authoritative` | 状态以 MuJoCo 为准，Godot 只显示 |
| `game_logic_only` | 仅 Godot 碰撞/任务，不进训练分布 |
| `hybrid` | 网关同步简化碰撞体到 MuJoCo，细节在客户端 |

MVP 建议：机甲 = `mujoco_authoritative`；纯装饰 = `game_logic_only`；障碍默认 `mujoco_authoritative`（简化盒体）。

---

## 6. 示例片段（YAML 示意）

```yaml
contract_version: "0.1"
level_id: "tutorial_01"
seed: 42

mech_spawns:
  - id: mech_player
    model_ref: "mechs/g1_minimal.xml"
    pose: { x: 0, y: 0, z: 0.5, yaw: 0 }
    player_slot: 0
    control_mode: "velocity"  # 或 joint_torque，见协议文档

static_obstacles:
  - id: wall_01
    shape: box
    size: [0.2, 2, 1]  # Z-up: [x, y, z] 全边长；挡路栅栏应长边沿 Y
    pose: { x: 5, y: 0, z: 0.5, yaw: 0 }
    physics_role: mujoco_authoritative

objectives:
  - id: obj_reach_zone
    type: reach_region
    target: trigger_finish
    description: "到达终点区"

triggers:
  - id: trigger_finish
    type: aabb
    min: [9, -1, 0]
    max: [11, 1, 2]
```

正式 SSOT：[`schemas/scene-contract.v0.json`](../schemas/scene-contract.v0.json)。障碍用 `shape`（非 `type`），以免与 objective/trigger 的 `type` 混淆；未知 `shape`/`objective.type` 用开放字符串 + `extensions`。

---

## 7. 待决事项

见 [10-open-questions.md](10-open-questions.md) § 场景契约。
