# 01 · 系统架构

| 字段 | 值 |
|------|-----|
| **状态** | Draft |
| **日期** | 2026-07-17 |
| **关联 ADR** | [adr/001-dual-engine-split.md](adr/001-dual-engine-split.md) · [adr/002-authority-and-sync.md](adr/002-authority-and-sync.md) |
| **POC / MVP 落地** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md)（范围、冻结默认、验收；本文保留完整职责说明） |

---

## 1. 架构总览

```text
┌─────────────────────────────────────────────────────────────┐
│                    GDevelop 客户端（Viewer + 游戏壳）          │
│  关卡/任务/UI/输入/相机/3D 表现傀儡                             │
└───────────────────────────┬─────────────────────────────────┘
                            │ WebSocket (JSON 文本)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      仿真网关（Gateway）                      │
│  会话管理 · 场景契约加载 · 协议转换 · 录制旁路 · 多副本路由    │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 MuJoCo 无头仿真（权威物理）                    │
│  机甲 MJCF · 关节/接触 · 固定 dt · 控制接口                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 组件职责

### 2.1 GDevelop 客户端

| 负责 | 不负责 |
|------|--------|
| 世界编辑产物（场景、对象、任务流）的运行时呈现 | 机甲关节级物理权威 |
| 玩家输入采集与 UX | MuJoCo 步进与接触解算 |
| 相机、HUD、音效、关卡叙事 | 二进制高频全状态协议（默认用 JSON + 网关聚合） |
| 3D 机甲「视觉傀儡」的插值显示 | 长期真物理的静态障碍（除非契约同步进 MuJoCo） |

**技术要点**：

- 导出 **HTML5** 作为轻客户端；桌面导出可选。
- 使用 **WebSocket Client** 扩展（或自定义 JS 扩展）与网关通信。
- 内置 **Multiplayer** 扩展用于玩家联机，**不**作为 MuJoCo 桥接通道。

### 2.2 仿真网关（Gateway）

| 职责 |
|------|
| 维护客户端 WS 连接与会话 ID |
| 加载场景契约，实例化/更新 MuJoCo 世界中的可仿真实体 |
| 将玩家 `cmd` 转为 MuJoCo 控制输入 |
| 按约定频率广播 `state` / `event` |
| 旁路写入录制存储（对象存储 / 时序库，待选型） |
| 多会话/多副本调度（水平扩展无头 MuJoCo worker） |

### 2.3 MuJoCo 无头仿真

| 职责 |
|------|
| 机甲本体动力学权威 |
| 关节状态、基座位姿、接触事件 |
| 固定仿真步长 `dt`，与网关时钟对齐 |
| 接收高层或低层控制指令（模式见 [03-websocket-protocol.md](03-websocket-protocol.md)） |

---

## 3. 数据流

### 3.1 控制流（玩家 → 仿真）

```text
输入设备 → GDevelop 事件/变量 → WS cmd → Gateway → MuJoCo ctrl
```

### 3.2 状态流（仿真 → 呈现）

```text
MuJoCo qpos/qvel/contact → Gateway 打包 state → WS → GDevelop 更新 3D 对象
```

### 3.3 录制流（旁路）

```text
cmd + state + event + 任务进度 → Gateway Recorder → 存储（带 session_id, ts, tick）
```

---

## 4. 权威与一致性原则

1. **机甲动力学状态以 MuJoCo 为准**；GDevelop 仅做插值与外推展示。
2. **装饰性物体**（纯视觉、无训练价值）可仅存在于 GDevelop，不进入 MuJoCo。
3. **影响物理或训练分布的障碍/可交互物**必须通过场景契约进入 MuJoCo，或明确标注为「仅游戏逻辑」。
4. **时间基准**：仿真 `tick` 为 SSOT；客户端用 `tick` + 插值，不用各自 `Date.now()` 对齐物理。

详见 [adr/002-authority-and-sync.md](adr/002-authority-and-sync.md)。

---

## 5. 部署视图（目标态）

```text
[CDN / 静态托管]  GDevelop HTML5 导出包
        │
        ▼
[WS Gateway 服务]  ←→  [MuJoCo Worker Pool]
        │                      │
        ▼                      ▼
[录制存储]              [场景契约 / MJCF 仓库]
```

本地开发：GDevelop 预览 + 本机 Gateway + 本机 MuJoCo 进程。

---

## 6. 非目标（架构层）

- 不把 GDevelop 编辑器本身部署为 SaaS（除非单独评估内网编辑器需求）。
- 不用 GDevelop Multiplayer 同步机甲物理状态。
- 不在 GDevelop 内嵌 MuJoCo 原生库（职责分离，WS 桥接）。
