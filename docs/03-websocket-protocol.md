# 03 · WebSocket 协议草案

| 字段 | 值 |
|------|-----|
| **状态** | Draft v0（Schema SSOT 已落盘）；**V1a 将增 `joint_targets`（见 [16](16-value-sprint.md)）** |
| **日期** | 2026-07-17 · 续记 2026-07-19 |
| **传输** | WebSocket 文本帧，JSON 载荷 |
| **SSOT** | [`schemas/ws-messages.v0.json`](../schemas/ws-messages.v0.json) · 扩展规则见 [`schemas/README.md`](../schemas/README.md) |

---

## 1. 设计原则

1. **字符串 JSON**：客户端引擎无关的最小公约数（Godot `WebSocketPeer` 文本帧；二进制留作未来优化）。
2. **信封稳定、载荷可长**：顶层 `type` / `session_id` / `tick` / `t_sim` / `payload` / `extensions`；新能力进 payload 或 `extensions`。
3. **开放枚举**：`event_type`、`control_mode`、`action` 允许自定义 snake_case；未知键消费者忽略。
4. **仿真 tick 为时间轴**：`t_sim ≈ tick * dt`。
5. **POC 频率**：`dt=0.02`（50Hz sim）、`state_hz=20`（见 `hello.payload`）。
6. **逃逸舱**：未来顶层类型可用 `ext.*`（见 schema `msg_extension`），避免立刻 fork 文件。

---

## 2. 连接生命周期

```text
Client --WS connect--> Gateway
Gateway --{ type: "hello", session_id, tick_rate, protocol_version }--> Client
Client --{ type: "join", level_id, player_name? }--> Gateway
Gateway --{ type: "scene", contract_summary, entities[] }--> Client
[ 仿真循环：state 广播 + cmd 上行 + event 异步 ]
Client/Gateway --{ type: "bye" }--> 关闭
```

---

## 3. 消息信封

所有消息共用顶层字段：

```json
{
  "type": "cmd | state | event | hello | scene | error | bye",
  "session_id": "uuid",
  "tick": 1204,
  "t_sim": 2.408,
  "payload": {}
}
```

| 字段 | 说明 |
|------|------|
| `tick` | 仿真步计数，整数 |
| `t_sim` | 仿真时间（秒），`tick * dt` |
| `payload` | 类型相关体 |

---

## 4. cmd（客户端 → Gateway）

玩家遥操与意图指令。

### 4.1 控制模式（待选一种为 MVP 默认）

| 模式 | payload 示例 | 适用 |
|------|--------------|------|
| `velocity` | `{ "vx", "vy", "yaw_rate" }` | 地面机甲粗控 |
| `target_pose` | `{ "x", "y", "z", "yaw" }` | 中层策略 |
| `joint_targets` | `{ "joints": { "hip_l": 0.2, ... } }` | 关节级 IL 数据 |

### 4.2 示例

```json
{
  "type": "cmd",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "tick": 1205,
  "payload": {
    "entity_id": "mech_player",
    "control_mode": "velocity",

`control_mode: "drive"`（R1 · demo_race）：模拟量驾驶通道，与 `velocity` 并存、向后兼容。

```json
{"control_mode": "drive", "throttle": 0.6, "brake": 0.0, "steer": -0.35, "handbrake": 0}
```

- `throttle [-1,1]`（<0 倒车）、`brake [0,1]`、`steer [-1,1]`（+ 左）、`handbrake [0,1]`（预留）
- 手感曲线参数集中在契约 `extensions.mw.drive`（`steer_max_rad` / `steer_speed_gain` / `v_max` / `v_taper` / `brake_torque` / `reverse_gain`），网关强制执行，客户端用同参数做 HUD 预览
    "vx": 0.5,
    "vy": 0.0,
    "yaw_rate": 0.1,
    "buttons": { "fire": false, "jump": false }
  }
}
```

### 4.3 接管 / 释放

```json
{
  "type": "cmd",
  "payload": {
    "action": "take_control",
    "entity_id": "mech_player"
  }
}
```

---

## 5. state（Gateway → 客户端）

周期性广播（建议 20–60 Hz，按关节数与带宽调优）。

```json
{
  "type": "state",
  "tick": 1204,
  "t_sim": 2.408,
  "payload": {
    "entities": [
      {
        "entity_id": "mech_player",
        "base_pose": { "x": 1.2, "y": 0.1, "z": 0.52, "qw": 1, "qx": 0, "qy": 0, "qz": 0 },
        "joints": {
          "hip_l": 0.15,
          "knee_l": -0.3
        },
        "velocities": { "vx": 0.48, "vy": 0.02 }
      }
    ]
  }
}
```

**优化（P1）**：增量 `state_delta`、仅变化关节、关键帧 + 插值。

---

## 6. event（双向 / 以 Gateway 推送为主）

离散事件：任务、接触、接管、错误。

```json
{
  "type": "event",
  "tick": 1204,
  "payload": {
    "event_type": "objective_complete",
    "objective_id": "obj_reach_zone",
    "detail": {}
  }
}
```

| event_type | 说明 |
|------------|------|
| `player_take_control` | 玩家接管机甲 |
| `player_release_control` | 释放 |
| `contact` | 碰撞（可选，注意频率） |
| `objective_complete` / `objective_failed` | 任务 |
| `sim_error` | 仿真异常 |

---

## 7. error

```json
{
  "type": "error",
  "payload": {
    "code": "INVALID_CMD",
    "message": "entity_id not found"
  }
}
```

---

## 8. 客户端（Godot）侧实现要点

1. 用内置 **`WebSocketPeer`** 连接（参考实现：`godot/spike/scripts/ws_client.gd`）。
2. 连接成功后解析 `hello`，存 `session_id`。
3. 定时（POC 为 20Hz）：读输入 → 组 `cmd` JSON → `send_text`。
4. 收包按 `type` 分发：`state` 驱动傀儡插值（`mech_puppet.gd`），`event` 驱动任务 UI。
5. 坐标映射集中在傀儡层：`godot = (x, z, -y)`，`rotation.y = yaw`（D1 Z-up → Y-up）。

---

## 9. 带宽与频率

| 参数 | POC 默认 | 说明 |
|------|----------|------|
| `dt` / `sim_hz` | 0.02 / 50 | 仿真步进 |
| `state_hz` | 20 | 广播给客户端；录制可用 `record_every_n_ticks` 单独控制 |

- 全关节名+浮点 JSON 在高频率下可能偏大 → POC 盒子机甲几乎无关节。
- P1：`payload.kind = "delta"` 增量 state。

---

## 10. 版本与兼容

- `hello.payload.protocol_version`: `"0.1"`（`0.x` 内可加可选字段）
- 破坏性变更：升 `1.0` 或新 schema 文件；Gateway 拒绝不兼容客户端
- 扩展规则：[schemas/README.md](../schemas/README.md)

---

## 11. 客户端实现契约（引擎无关）

任何引擎/技术栈只要满足以下 4 条，即可作为客户端接入本协议——客户端可替换性由此保证（实证：[adr/003](adr/003-client-engine-godot.md)，GDevelop→Godot 协议零改动）：

1. **传输**：WebSocket **文本帧**（不要求二进制）。
2. **流程**：实现生命周期 `hello → join → scene → 稳态（cmd 上行 / state 下行 / event 异步）→ bye`。
3. **纪律**：权威实体傀儡**只插值不积分**；控制量只走 `cmd` 上行；时间轴服从 `tick`（[adr/002](adr/002-authority-and-sync.md)）。
4. **映射**：完成一次坐标系换算（`mineworld_zup_m` → 本引擎轴向），集中在傀儡层一处实现。

## 12. 契约的三层体系与修改流程

| 层 | 文件 | 作用 |
|----|------|------|
| 语义层 | 本文档 | 给人读：原则、生命周期、示例、版本政策 |
| **SSOT 层** | [`schemas/ws-messages.v0.json`](../schemas/ws-messages.v0.json) | 机器校验：所有消息的合法形状（JSON Schema 2020-12） |
| 实例层 | [`examples/ws/*.json`](../examples/ws/) | 具体消息样例，`ajv validate` 对着 SSOT 层跑 |

**修改契约 = 三层一起改**：改 Schema → 补/改示例 → `ajv validate` 通过 → 双端冒烟（`scripts/ws_smoke_test.py` + `godot --headless --path godot/spike --script res://headless/smoke_client.gd`）→ 回写本文档。

**两层契约勿混淆**：

- **WS 消息契约**（本文）：管「怎么说话」，引擎无关——换引擎时不动。
- **场景契约**（[02](02-scene-contract.md) / `schemas/scene-contract.v0.json`）：管「世界是什么」——换关卡时动它；经 `join(level_id)` 加载、`scene` 消息下发摘要。
- 加消息能力：只动本契约的 `payload`（或 `ext.*` 先进场实验）。
