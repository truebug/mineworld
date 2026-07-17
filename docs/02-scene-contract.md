# 02 · 场景契约（Scene Contract）

| 字段 | 值 |
|------|-----|
| **状态** | Draft v0 |
| **日期** | 2026-07-17 |
| **SSOT 方向** | `schemas/scene-contract.v0.json`（待建） |

---

## 1. 目的

GDevelop 关卡自由度高，MuJoCo 需要可解析、可实例化的世界描述。**场景契约**是两者之间的 SSOT：

- **输入**：GDevelop 导出或网关从工程中抽取的结构化描述。
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
| 可交互物 | 门、开关、可推动物体；需定义是否进 MuJoCo 物理 |
| 导航区 | 仅 GDevelop AI 或仅任务判定 |
| 环境参数 | 重力、地面材质、光照（光照仅客户端） |

### 2.3 明确不通过契约传递

- GDevelop 事件表逻辑、UI 布局、音效资源路径（客户端本地）。
- 完整 GDevelop `game.json` 原文（过大且非仿真 SSOT）。

---

## 3. 导出路径（规划）

| 方式 | 说明 | 优先级 |
|------|------|--------|
| **A. 手工 JSON** | MVP 手写契约文件，GDevelop 关卡与 JSON 人工对齐 | P0 |
| **B. GDevelop 扩展导出** | 自定义扩展：读取场景对象自定义属性 → 写 JSON | P1 |
| **C. 外部工具** | Blender 布局 → 契约中的 `static_obstacles` | P2 |

---

## 4. 对象 ID 与引用规则

- 所有可引用实体使用 **全局唯一字符串 ID**（如 `spawn_mech_01`, `wall_north_03`）。
- GDevelop 3D 对象通过 **对象变量** 或 **自定义扩展字段** 绑定 `mujoco_entity_id`。
- Gateway 维护 `entity_id → MuJoCo body/site 索引` 映射表，随契约热更新策略另议。

---

## 5. 物理归属分类

每个契约实体必须标注 `physics_role`：

| 值 | 含义 |
|----|------|
| `mujoco_authoritative` | 状态以 MuJoCo 为准，GDevelop 只显示 |
| `game_logic_only` | 仅 GDevelop 碰撞/任务，不进训练分布 |
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
    type: box
    size: [2, 0.2, 1]
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

正式 SSOT 以 JSON Schema 为准，见 `schemas/`（待建）。

---

## 7. 待决事项

见 [10-open-questions.md](10-open-questions.md) § 场景契约。
