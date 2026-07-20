# MineWorld 文档索引

本目录收录 Godot + MuJoCo 融合底座的设计文档，按阅读顺序排列。

## 阅读顺序（首次）

1. [00-vision.md](00-vision.md) — 为什么做、做什么
2. **[21-ecosystem-federation.md](21-ecosystem-federation.md)** — **生态对接：Hub↔PMS/Spaces；统一身份**
3. **[22-identity-mapping.md](22-identity-mapping.md)** — **E2：`player_id` ↔ 外部 user 映射 + federated stub**
4. [15-course-correction.md](15-course-correction.md) — 跑偏纪要与纠偏诊断
4. **[16-value-sprint.md](16-value-sprint.md)** — V 线冻结规格（车间 / 臂爪 / IL）· **Done**
5. **[18-hub-dungeon.md](18-hub-dungeon.md)** — **3D 地下城 Hub（默认入口）**
6. **[20-platform-portal.md](20-platform-portal.md)** — **平台门户 / 身份 / 积分 / Admin（规划）**
7. [17-lobby-testfield.md](17-lobby-testfield.md) — 试验场文本菜单（`?menu=1`）
8. [01-architecture.md](01-architecture.md) — 怎么拆
9. [02-scene-contract.md](02-scene-contract.md) — 世界如何进仿真
10. [03-websocket-protocol.md](03-websocket-protocol.md) — 怎么连
11. [04-data-collection.md](04-data-collection.md) — 采什么（IL 优先）
12. [08-modes-roadmap.md](08-modes-roadmap.md) — MVP 与路线
13. [09-todo.md](09-todo.md) — **可执行待办（Now / Next）**
14. [19-changelog.md](19-changelog.md) — **变更记录**
15. [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md) — POC 规格 + MVP 薄架构
16. [12-status-review.md](12-status-review.md) — 阶段回顾
17. [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) — Web / 多人
18. [14-godot-mujoco-fusion.md](14-godot-mujoco-fusion.md) — 融合 + URDF/视觉

## 实施参考

- [05-godot.md](05-godot.md)
- [06-mujoco.md](06-mujoco.md)
- [07-tooling.md](07-tooling.md)

## 架构决策（ADR）

- [adr/001-dual-engine-split.md](adr/001-dual-engine-split.md)
- [adr/002-authority-and-sync.md](adr/002-authority-and-sync.md)
- [adr/003-client-engine-godot.md](adr/003-client-engine-godot.md)

## 治理

- [10-open-questions.md](10-open-questions.md)
- [12-status-review.md](12-status-review.md)
- [15-course-correction.md](15-course-correction.md)
- [16-value-sprint.md](16-value-sprint.md)
- [19-changelog.md](19-changelog.md)
