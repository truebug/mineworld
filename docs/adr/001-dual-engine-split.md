# ADR-001：双引擎职责分离（GDevelop + MuJoCo）

| 字段 | 值 |
|------|-----|
| **状态** | Accepted |
| **日期** | 2026-07-17 |
| **确认** | 与 [11-poc-mvp-architecture.md](../11-poc-mvp-architecture.md) §9.1 同日评审通过 |
| **决策编号** | ADR-MW-001 |

---

## 背景

单一引擎难以同时满足：面向玩家的关卡编辑体验，与面向机器人的关节级物理仿真与数据采集。

## 决策

采用 **双引擎架构**：

1. **GDevelop**：世界编辑、任务/UI、输入、Viewer、客户端发布。
2. **MuJoCo**：机甲及契约内物理实体的仿真权威。
3. **Gateway + WebSocket**：唯一集成边界，载荷为 JSON 文本。

## 理由

- 各取所长，避免在 GDevelop 内嵌 MuJoCo 或让 MuJoCo 承担完整游戏编辑器。
- WebSocket Client 为 GDevelop 官方扩展能力，落地成本低。
- 无头 MuJoCo 便于水平扩展与 CI。

## 后果

| 正面 | 代价 |
|------|------|
| 职责清晰，团队可分工 | 需维护场景契约与协议版本 |
| 客户端可 Web 化 | 双世界一致性需治理 |
| 录制管道自然落在 Gateway | 多一层服务部署 |

## 不采纳

- 仅用 GDevelop 内置 3D 物理驱动机甲训练数据。
- 仅用 MuJoCo + 自研编辑器替代 GDevelop 关卡能力（短期成本过高）。
