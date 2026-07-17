# 03 · WebSocket 协议草案

| 字段 | 值 |
|------|-----|
| **状态** | Draft v0 |
| **日期** | 2026-07-17 |
| **传输** | WebSocket 文本帧，JSON 载荷 |
| **SSOT 方向** | `schemas/ws-messages.v0.json`（待建） |

---

## 1. 设计原则

1. **字符串 JSON**：对齐 GDevelop [WebSocket Client](https://wiki.gdevelop.io/gdevelop5/extensions/web-socket-client/) 扩展能力（不支持二进制）。
2. **消息类型三分**：`cmd`（控制）、`state`（状态）、`event`（离散事件）。
3. **仿真 tick 为时间轴**：所有消息带 `tick` 或 `t_sim`。
4. **会话绑定**：`session_id` 在握手后由 Gateway 分配。

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

## 8. GDevelop 侧实现要点

1. 安装 **WebSocket Client** 扩展。
2. 连接成功后解析 `hello`，存 `session_id` 到场景变量。
3. 每帧或定时器：读输入 → 组 `cmd` JSON → `Send data to the server`。
4. `An event was received`：解析 `type`，`state` 更新 3D 对象位置/旋转；`event` 驱动任务 UI。
5. 复杂 JSON 解析可用 **JavaScript Code 事件** 或封成自定义扩展（推荐）。

---

## 9. 带宽与频率（粗算）

- 全关节名+浮点 JSON 在 50Hz 下可能偏大 → MVP 可用 `velocity` + 精简 `state`（基座位姿 + 少量关节）。
- 录制侧保留完整 `state`；客户端展示可降频。

---

## 10. 版本与兼容

- `hello.protocol_version`: `"0.1"`
- 破坏性变更升 minor，Gateway 拒绝不兼容客户端。
