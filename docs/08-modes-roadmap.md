# 08 · 模式设想与路线图

| 字段 | 值 |
|------|-----|
| **状态** | Draft |
| **日期** | 2026-07-17 |

---

## 1. 三类模式（同一底座）

### 1.1 学习模式

| 模式 | 数据/能力 |
|------|-----------|
| 行为克隆 / IL | 通关成功轨迹作正样本 |
| 层次策略 | GDevelop 任务子目标 + MuJoCo 低层控制 |
| 固定评测场 | 同契约 + 同 seed 横向比人机/模型 |
| 人在环纠偏 | 失败关卡人工接管补数据 |

### 1.2 娱乐模式

| 模式 | 说明 |
|------|------|
| 机甲对战 / 协作任务 | 爽感来自关卡与反馈，底层真动力学 |
| 解谜闯关 | 任务系统由 GDevelop 编排 |
| 大师回放 / 幽灵 | 录制轨迹作对手或教学 |
| 观众模式 | 只看 state 驱动 Viewer，不采输入 |

### 1.3 商业模式

| 模式 | 说明 |
|------|------|
| 数据许可 | 脱敏轨迹包，按任务/难度/成功率分层 |
| 仿真即服务 | 客户用编辑器搭场景，租无头算力 |
| 品牌/教育营 | 短周期活动关卡 + 垂直领域数据 |
| 模型评测榜 | 公开关卡集 + 私有持出集 |

---

## 2. MVP：最小可玩闭环

**范围刻意收窄**——验证双引擎 + 录制，不追求大世界。

| 项 | MVP 内容 |
|----|----------|
| 关卡 | 1 个教程关（平地 + 终点区） |
| 机甲 | 1 台简化机体 |
| 控制 | 一种 `control_mode`（建议 `velocity`） |
| 网络 | 单客户端 ↔ 单 Gateway ↔ 单 MuJoCo |
| 录制 | header.json + frames.jsonl |
| 客户端 | GDevelop HTML5 预览或导出 |

### 2.1 用户旅程

```text
打开客户端 → 连接 Gateway → 进入 tutorial_01
→ 接管 mech_player → 遥操至终点 → 任务成功
→ 会话落盘 → （可选）脚本回放轨迹
```

### 2.2 MVP 不包含

- 多人在线大厅（可用 Multiplayer 扩展后续加，与仿真网关分离）
- 完整场景契约自动导出
- 商业计费与账号体系
- 关节级全量 50Hz 录制（可先降采样）

---

## 3. 路线图

### Phase 0 — 文档与契约（当前）

- [x] 文档结构落盘
- [x] POC 规格 + MVP 薄架构：[11-poc-mvp-architecture.md](11-poc-mvp-architecture.md)
- [x] JSON Schema v0：`scene-contract`、`ws-messages`、`recording-session`、`common`（见 `schemas/`）
- [x] 评审冻结 D1–D7 + 5 日 POC + 盒子机甲（`11` §9.1）
- [ ] （可选）`ajv` / 脚本校验 examples

### Phase 1 — 连通（POC-A / M1 ✅）

- [x] Gateway echo / 假 state（`gateway/echo_server.py`）
- [x] `scripts/ws_smoke_test.py` 冒烟
- [x] GDevelop `gdevelop/demo0` + WebSocket：hello/join/WASD 驱动 MechPlayer

### Phase 2 — 真仿真（POC-B，下一步）

- [ ] MuJoCo 单机甲 + 契约障碍
- [ ] state 广播 + 客户端驱动 3D 对象
- [ ] 接管 / 释放 + 基础录制

### Phase 3 — 可玩与数据（预计 4–8 周）

- [ ] 任务成功/失败判定
- [ ] 回放脚本
- [ ] 第二关卡验证编辑器工作流

### Phase 4 — 扩展

- [ ] 多副本 Gateway
- [ ] 学习/评测 API
- [ ] 资产管线（Blender → GDevelop + 契约）

---

## 4. 里程碑验收标准

| 里程碑 | 验收 |
|--------|------|
| M1 连通 | GDevelop 与 Gateway WS 互通 JSON |
| M2 真物理 | 机甲位姿由 MuJoCo 驱动，非本地假移动 |
| M3 可录可放 | 一次完整会话可落盘并用脚本回放 |
| M4 可玩 | 一关完整任务流程（进关→操控→结算） |

---

## 5. 风险

| 风险 | 缓解 |
|------|------|
| JSON 状态带宽过大 | 增量 state、降频、关节子集 |
| GDevelop/MuJoCo 坐标系不一致 | 契约中统一右手系与单位（米） |
| 双世界漂移 | 严格 physics_role 分类 |
| 确定性回放失败 | 录 `mujoco_version` + seed + 模型哈希 |
