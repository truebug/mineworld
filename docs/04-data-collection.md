# 04 · 数据采集与录制

| 字段 | 值 |
|------|-----|
| **状态** | Draft v0（Schema SSOT 已落盘）；管道可用，**内容深度待纠偏** |
| **日期** | 2026-07-17 · 续记 2026-07-19 |
| **定位** | 产品核心资产管道，与娱乐壳同等优先级 |
| **SSOT** | [`schemas/recording-session.v0.json`](../schemas/recording-session.v0.json) |
| **纠偏** | [15-course-correction.md](15-course-correction.md) · **[16-value-sprint.md](16-value-sprint.md)**（IL 优先 · 成对 cmd/joints） |

---

## 1. 采集目标

| 数据类 | 用途 |
|--------|------|
| **遥操轨迹** | 模仿学习、行为克隆、人在环纠偏 |
| **仿真状态** | 回放、离线评测、重现实验 |
| **任务/交互事件** | 有目标的行为数据、成功率统计 |
| **场景元数据** | 按关卡/难度/契约版本分层售卖或训练 |

---

## 2. 会话模型

一次「从进关到结束」为 **Session**：

| 字段 | 说明 |
|------|------|
| `session_id` | UUID，与 WS 一致 |
| `level_id` | 关卡标识 |
| `contract_version` | 场景契约版本 |
| `contract_hash` | 契约内容哈希，可复现 |
| `mech_model_ref` | 机甲 MJCF 引用 |
| `player_id` | 可选，匿名化策略另定 |
| `started_at` / `ended_at` | UTC 时间戳 |
| `outcome` | `success` / `fail` / `abort` / `disconnect` |

---

## 3. 录制内容（SSOT 方向）

### 3.1 时间序列（推荐列式或分段 JSONL）

每条记录最小字段：

```json
{
  "tick": 1204,
  "t_sim": 2.408,
  "cmd": { "entity_id": "mech_player", "control_mode": "velocity", "vx": 0.5 },
  "state": { "entities": [ "..."] },
  "events": []
}
```

- **cmd**：玩家有输入的 tick 写入；无输入可省略或记 null。
- **state**：按固定间隔或每 tick 快照（存储成本 trade-off）。
- **events**：该 tick 发生的离散事件。

### 3.2 关卡与任务快照（会话头）

```json
{
  "session_id": "...",
  "scene_contract": { },
  "objectives": [ ],
  "random_seed": 42
}
```

### 3.3 衍生指标（后处理）

- 路径长度、完成时间、碰撞次数、接管时长占比
- 按 `objective_id` 的成功/失败标签

---

## 4. 存储格式（规划）

| 阶段 | 格式 | 说明 |
|------|------|------|
| MVP | `sessions/<session_id>/header.json` + `frames.jsonl` | 易调试；字段见 schema `$defs/header` / `$defs/frame` |
| 规模 | Parquet / Zarr + 对象存储 | **语义不变**：列从 frame/header 映射，不必改 WS |

Schema：[`schemas/recording-session.v0.json`](../schemas/recording-session.v0.json)。扩展用 `features[]`、`extensions`、`stats`（后处理可写）。

---

## 5. 隐私与合规（占位）

- 玩家标识脱敏策略
- 是否录制聊天/语音（默认否）
- 数据保留周期与删除请求流程

---

## 5.1 仿真传感器出口（与真人/AI 同视图）

传感器读数**单向闭环在 MuJoCo**：编码器/IMU/接触等来自 `MjData`，未来视觉类由 MuJoCo 对仿真场景离屏渲染（相机为 MJCF sensor）。出口通道按消费方区分（P1+）：

| 通道 | 消费方 | 说明 |
|------|--------|------|
| `state.entities[].joints / joint_vels / velocities` | 客户端呈现 + 录制 | 关节/基座运动学（现有） |
| `event`（`contact`、`objective_*`） | 任务与统计 | 离散事件（现有） |
| `ext.sensor` 顶层消息（逃逸舱，P1） | AI Agent / 数据侧 | 连续传感器读数；与真人遥操共享同一 `cmd` 通道构成闭环 |

原则：**真人与 AI Agent 看到的状态视图一致**——AI 复用同一 `cmd` 通道注入控制量，演示数据与策略数据同构可比。

---

## 6. 回放

1. 读 `header.json` 重建契约与初始状态。
2. 按 `frames.jsonl` 的 `tick` 驱动 MuJoCo 重放或 Godot 幽灵显示。
3. 可选：仅回放 `cmd` + 契约，在 MuJoCo 中**开环重算**以验证确定性。

---

## 7. 与客户端（Godot）的关系

- Godot **不**负责持久化录制；仅发送 `cmd`、展示 `state`。
- 任务完成/失败由 Gateway 判定并写入 `event`，避免客户端作弊。

---

## 8. MVP 验收

- [x] 单次会话完整落盘（header + 至少 10s 帧数据）
- [x] 可用脚本读取 JSONL 并绘制基座轨迹
- [x] `session_id` 与 WS 日志可关联排错
- [x] 本机 Recordings 列表 + 2D/3D 回放 + CSV 批量导出（D5/D8/D13）
- [ ] 关节级 `cmd`/`joints` 成对密度足够支撑 IL（见纠偏 V1）
- [ ] 任务标签 / 难度分层进 header（见纠偏 V4）

POC 阶段「能录能导出」已达成；**提高单条轨迹信息密度**见 [15-course-correction.md](15-course-correction.md)。
