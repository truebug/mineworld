# 10 · 待决事项与评审清单

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **关联** | [12](12-status-review.md) · [15](15-course-correction.md) · [16](16-value-sprint.md) · [20](20-platform-portal.md) |

---

## 1. 产品

| ID | 问题 | 选项 / 备注 | 负责人 | 状态 |
|----|------|-------------|--------|------|
| P1 | 对外产品名是否使用「头号玩家」类比 | 建议内部愿景，对外用「MineWorld」或独立品牌 | — | Open（**不阻塞 M4**） |
| P2 | MVP 机甲形态 | **纠偏期**：平面底盘 + **臂/夹爪**（见 [16](16-value-sprint.md)）；全身人形仍后置 | — | Partial |
| P3 | 默认控制模式 | **纠偏期**：`velocity`（底盘）+ **`joint_targets`（臂/爪）**；UX=键鼠滑条 | — | Partial |
| P5 | 主演示关 | **纠偏期**：新开 **`demo_workshop`**；`demo_city` 次要 | — | Partial |
| P6 | 近期数据用途 | **冻结**：优先 **IL / 行为克隆** | — | Closed |
| P4 | 是否需要账号与进度存档 | 见 [20](20-platform-portal.md)：Phase A 起唯一 `player_id`；完整 SaaS 后置 | — | Partial |
| P9 | 积分 / 排行 / 门户登录 | 旅程已写入 [20](20-platform-portal.md)；计分公式与反作弊未定 | — | Open |

---

## 2. 场景契约

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| C1 | 契约文件由谁生成 | MVP 手写 JSON；P1 Godot 编辑器插件读 `.tscn` | Open（**不阻塞 M4**；改场景必同步改契约） |
| C2 | 坐标系与单位 | **Closed**：米 · 右手系 · **Z-up**；客户端（Godot）侧映射（`11` D1；实现于 `godot/spike/scripts/mech_puppet.gd`） | Closed |
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
| D1 | 录制存储位置 | 本地目录 / S3 / 时序库 | **Partial**：POC 已本地 `recordings/sessions/<id>/`；索引 SQLite。**Next PL1** 将抽象为可配置 DB + 独立 API |
| D2 | 玩家标识脱敏 | UUID 映射表 | Open |
| D3 | 数据许可法律模板 | 商业前必备 | Open |
| L1 | 成品 Godot 地图包作默认关 | KayKit 楼宇 + `gen_demo_city_block.py` 随机街区空气墙 | **Closed（v0）**（D6/D7；整张第三方成品地图仍可再换） |
| P7 | 独立 API / 管理控制台边界 | 与 Gateway WS 权威分离；见 [09](09-todo.md) Phase A · [20](20-platform-portal.md) | Open |
| P8 | 首屏与关卡过场 | UX1/UX2-v0 已落地；UX2b/UX3 仍 Open | Partial |

---

## 5. 工程与仓库

| ID | 问题 | 备注 | 状态 |
|----|------|------|------|
| E1 | mineworld 是否并入数聚球 monorepo | 当前独立目录 `projects/mineworld` | Open |
| E2 | Gateway 语言 | **Closed**：Python 3.11+（`11` D3） | Closed |
| E2b | 客户端引擎 | **Closed**：Godot 4（[adr/003](adr/003-client-engine-godot.md)；GDevelop 已评估并归档） | Closed |
| E3 | CI 导出客户端 | Godot `--export-release` + 导出模板版本锁定；无头 smoke 已可跑 | Open |

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
