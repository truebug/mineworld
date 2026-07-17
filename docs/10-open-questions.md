# 10 · 待决事项与评审清单

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-17 |

---

## 1. 产品

| ID | 问题 | 选项 / 备注 | 负责人 | 状态 |
|----|------|-------------|--------|------|
| P1 | 对外产品名是否使用「头号玩家」类比 | 建议内部愿景，对外用「MineWorld」或独立品牌 | — | Open |
| P2 | MVP 机甲形态 | **Closed**：POC/MVP 自建盒子机甲；真人形/g1 后置 | — | Closed |
| P3 | 默认控制模式 | **Closed**：`velocity`（见 `11` §3/§9.1） | — | Closed |
| P4 | 是否需要账号与进度存档 | MVP 可匿名会话 | — | Open |

---

## 2. 场景契约

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| C1 | 契约文件由谁生成 | MVP 手写 JSON；P1 GDevelop 扩展 | Open |
| C2 | 坐标系与单位 | **Closed**：米 · 右手系 · **Z-up**；GDevelop 侧映射（`11` D1） | Closed |
| C3 | 静态障碍精度 | **Closed（POC）**：盒体近似 | Closed |
| C4 | `game_logic_only` 物体是否进入录制 | 影响训练分布声明 | Open |

---

## 3. 协议与性能

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| N1 | state 广播频率 | 20–60 Hz，按关节数压测 | Open |
| N2 | 是否引入 `state_delta` | P1 优化项 | Open |
| N3 | WS 是否 TLS / wss | 生产必须；本地 ws:// | Open |
| N4 | 多客户端观战 | 同 session 多连接只读 | P2 |

---

## 4. 数据与合规

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| D1 | 录制存储位置 | 本地目录 / S3 / 时序库 | Open |
| D2 | 玩家标识脱敏 | UUID 映射表 | Open |
| D3 | 数据许可法律模板 | 商业前必备 | Open |

---

## 5. 工程与仓库

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| E1 | mineworld 是否并入数聚球 monorepo | 当前独立目录 `projects/mineworld` | Open |
| E2 | Gateway 语言 | **Closed**：Python 3.11+（`11` D3） | Closed |
| E3 | CI 导出 GDevelop | gdexporter 版本锁定 | Open |

---

## 6. 评审会议建议议程

1. 过 [00-vision.md](00-vision.md) 与 MVP 范围（[08-modes-roadmap.md](08-modes-roadmap.md)）
2. 确认 ADR-001 / ADR-002
3. 钉死坐标系（C2）与控制模式（P3）
4. 指定 Phase 1 负责人与两周目标

---

## 7. 文档维护

- 决策关闭后：更新对应 ADR 状态为 Accepted，并在此表填 `Closed` + 链接。
- 协议破坏性变更：升 `contract_version` / `protocol_version`，写入 CHANGELOG（待建）。
