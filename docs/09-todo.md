# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | Hub H4–H6 已落地；**Now：P1 接触/IL · Next：平台 API / 控制台 / UX 过场** |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md) |
| **Web/多人路线** | [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) |
| **融合路线** | [14-godot-mujoco-fusion.md](14-godot-mujoco-fusion.md) |
| **阶段评审** | [12-status-review.md](12-status-review.md) |
| **跑偏与纠偏** | [15-course-correction.md](15-course-correction.md) |
| **V 线规格** | [16-value-sprint.md](16-value-sprint.md)（冻结项 Done） |
| **试验场入口** | [17-lobby-testfield.md](17-lobby-testfield.md)（`?menu=1`） |
| **地下城 Hub** | **[18-hub-dungeon.md](18-hub-dungeon.md)**（默认主场景） |
| **变更记录** | **[19-changelog.md](19-changelog.md)** |

勾选约定：`[ ]` 未做 · `[x]` 完成 · `[-]` 取消 · `[~]` 暂缓

---

## Now（数据价值续 · 2026-07-20）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| P1a | 真摩擦抓取（替换 sticky） | grasp_lift 不靠 kinematic weld | [ ] |
| P1b | 最小 BC 离线检查 | notebook/脚本读 success CSV 关节列 | [ ] |
| H7 | Hub UI / 门 C–E 占位打磨 | 左栏 lore、右栏地图、名片可读；C–E 门有 stub 文案 | [ ] |

> Hub 展示壳（半层二楼 + 静态电梯）已入库，见 [18](18-hub-dungeon.md) · [19](19-changelog.md)。

---

## Next（平台与体验 · 规划）

> 与当前 POC Gateway（单进程 WS + 本地 FS）**解耦**；先定配置与边界，再独立仓/目录落地。不阻塞 P1。

### UX · 首屏与过场

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| UX1 | 加载动画 / 首屏画面 | 替换 Godot Web 默认 logo/splash；品牌首屏 + 进度（壳 HTML 或自定义 boot splash） | [ ] |
| UX2 | 关卡过场动画 | Hub ↔ 工坊/训练场不再瞬间切景；淡入淡出或门洞过场 ≥300ms；可跳过 | [ ] |
| UX3 | Hub 加载与重连提示 | 断线/重连有明确文案，避免静默白屏 | [ ] |

### PL · 独立 API 与后台

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| PL1 | 可配置持久化 + 消息中间件的 **API 服务**（独立进程） | 配置切换 DB（如 SQLite→Postgres）与 MQ（如内存/Redis/NATS）；REST/HTTP API 与现网 Gateway WS **并存**；会话/录制索引/房间元数据可查 | [ ] |
| PL2 | Web 控制台（后台管理） | 只读/运维：在线房、录制列表、契约/level 开关、基础健康检查；鉴权最小可用（token/本地） | [ ] |
| PL3 | API 与 Gateway 契约 | 文档化：哪些能力仍走 WS Gateway，哪些走 HTTP API；禁止双写权威位姿 | [ ] |
| PL4 | 配置 SSOT | `config`/`env` 驱动 DB/MQ/存储根路径；本地默认零依赖可跑 | [ ] |

### Hub 后续

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| H8 | 可乘电梯 + 可上 L2 | 轿厢运动或瞬移上二楼；栏杆碰撞；小地图层切换 | [ ] |
| H9 | Hub 交互台玩法雏形 | Party board / Vendor 至少一个有真实 UI 面板（非仅 Label3D） | [ ] |

### 运维 / 公网（原暂缓，仍排后）

| ID | 任务 | 状态 |
|----|------|------|
| W2.1 / W2.2 / W2.4 | 公网 HTTPS / wss / 运维页 | [~] 可与 PL2 合并规划 |
| T2.7 | 输入延迟补偿 v0 | [~] |

---

## Done（H · 3D Hub · 2026-07-20）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| R1 | 录制列表过滤 + joints 覆盖提示 | `recordings.html` level/outcome；详情显示 joints keys | [x] |
| R2 | 回放验收 smoke | `scripts/replay_verify_smoke.py`（需 serve_web） | [x] |
| H0 | 试验场入口场景 | `demo_lobby.tscn`（现为 `?menu=1`） | [x] |
| H1 | Gateway 多契约 `join.level_id` | workshop / city 同进程可进 | [x] |
| H2 | Esc 回入口 | 玩法关 Esc → Hub | [x] |
| H4 | 3D Hub 外壳 + 门 A/B | `demo_hub` 为主场景；`?menu=1` 文本菜单 | [x] |
| H5 | Hub 互见（无 MuJoCo） | `room=hub` 两浏览器可见纸片人 | [x] |
| H6 | 本地 Profile 昵称/简卡 | localStorage；头顶显示 | [x] |
| H6b | Hub 观感打磨 | 实心机库 + 星空；靠墙摆设；NPC 静站缩小；DOM HUD 贴 canvas；展示电梯+半层二楼 | [x] |

---

## Done（V · 数据价值纠偏 · 冻结项）

> 规格见 [16](16-value-sprint.md)。冻结项均已完成（2026-07-20）。

## Done（F · Godot ↔ MuJoCo 融合）

> 公网 W2.1/2/4、T2.7 **暂缓**。详设见 [14](14-godot-mujoco-fusion.md)。

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| F0 | 机甲 A/B 外观区分（染色 + 头顶标签） | `?room=demo` 一眼可辨 | [x] |
| F1 | tutorial_01 加 CC0 装饰 / 地面（viewer_only） | 物理冒烟不变；观感提升 | [x] |
| F2 | 试点真实 URDF/MJCF → 转 MJCF + `model_ref` | headless + smoke 可控 | [x] |
| F3 | Godot 加载同款视觉 mesh（换胶囊） | 位姿仍跟 state | [x] |
| F4 | `.tscn` → 契约导出（T4.2） | `export_scene_contract.py --check` | [x] |
| F5 | 第三方 DiffBot URDF 换皮（planar 包装） | headless + mujoco smoke | [x] |
| F6 | 真差速：左右轮 hinge + body `vx/ω`→轮速；`joints` 含轮 | headless 平面跟踪仍 PASS；smoke 见轮关节 | [x] |
| F7 | 机甲互撞（同房共享 MjData） | `?room=demo` 两机可撞；`scripts/mech_collision_smoke.py` PASS | [x] |
| F8 | Godot 自动跟皮（少手抄 URDF 常量） | 改 URDF 重生成后傀儡尺寸自动对齐 | [x] |

顺序：F6 → F7 → F8（已完成）。`main` 已含 W2.3 / W3 / T2.6 与 F0–F8。

---

## Done（D · 演示打磨）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| D1 | `demo_city` 主演示关（最小权威墙+终点；spawn/相机） | 默认契约/场景；smoke + `--expect-objective` | [x] |
| D2 | T4.6 推箱玩法 | 契约 `dynamic_props` + MuJoCo 平面箱；`push_box_smoke.py` PASS | [x] |
| D3 | Web HUD 彻底修好（custom shell · `#mw-hud` 在 body） | 导出校验 body 内 HUD；浏览器无左裁切 | [x] |
| D4 | 通关反馈 SUCCESS 大字 + 短蜂鸣 | `objective_complete` → 横幅 + beep | [x] |
| D5 | 录制历史列表 + 选择回放（多会话） | `GET /api/recordings` + `recordings.html` 轨迹预览；本地 FS | [x] |
| D6 | 导入成品免费地图包作默认关（CC0） | KayKit City Bits 换皮 `demo_city`；权威障碍仍走契约 | [x] |
| D7 | 随机街区 + 楼宇占地空气墙 | `gen_demo_city_block.py` + `city_block_dress.gd`；棕墙隐藏 | [x] |
| D9 | Web 选 seed / 一键重生街区 | `POST /api/city-block` + shell 控件；Gateway 契约 mtime 热加载 | [x] |
| D10 | 路面贴花 / 更密路网观感（仍空气墙权威） | 楼宇间深色沥青带 + 浅灰人行底（无 KayKit 标线砖） | [x] |
| D8 | 客户端内帧回放 | Recordings 2D Play + `/?replay=` 3D 离线驱动傀儡 | [x] |
| D11 | KayKit 街道小品 | layout `props`（灯/椅/灌木/消防栓） | [x] |
| D12 | demo_city 终点开环 smoke | `--expect-objective` 直道东行至绿区 | [x] |
| D13 | 录制索引 SQLite + 批量轨迹导出 | `recording_store` + `export_trajectories.py` + API | [x] |

> **D 线已收口。** 城市皮/seed/路面不再作为主投入；见 [15](15-course-correction.md) V5 · [16](16-value-sprint.md)。

---

## Done（V · 数据价值 · 明细）

> 规格 SSOT：[16-value-sprint.md](16-value-sprint.md)。

### 冻结决策（摘要）

| 项 | 选择 |
|----|------|
| 机体 | 平面底盘 + 附加臂/夹爪 |
| UX | 键鼠 + 关节滑条 |
| 关卡 | 新开 `demo_workshop`（大封闭车间）；`demo_city` 次要 |
| 数据 | IL / 行为克隆优先 |

### V4 · 数据标签（可先做）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| V4a | header/index IL 最小标签 | `task_id` · `difficulty` · `control_mode(s)` · `outcome` · `seed` 入 header + sqlite | [x] |
| V4b | 导出服务 IL | CSV/JSONL 含关节 `cmd`+`joints`；可按 level/task/outcome 过滤 | [x] |

### L · 车间关

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| L1 | `demo_workshop` 契约 + 封闭车间壳 | 契约 JSON + `demo_workshop.tscn`；四面墙权威；无街道巡航叙事 | [x] |
| L2 | 工作台 / 料箱 trigger | 料箱 AABB + 工作区；`dynamic_props` 可动物 | [x] |
| L3 | 默认主演示切车间 | Gateway/Web 默认或文档明确主线为 workshop；city 可选手动 | [x] |

### V2 · 机体（臂+爪）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| V2a | 底盘+臂+爪 MJCF | headless 可步进；关节名表进 16/ASSETS | [x] |
| V2b | Godot 跟皮 | 臂/爪随 `joints`；底盘复用 DiffBot 皮 | [x] |
| V2c | 许可登记 | 仅 CC0/MIT 或自建；ASSETS 记账 | [x] |

### V1 · 控制（joint_targets + 滑条）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| V1a | Schema `joint_targets` | ws-messages + examples；可与 velocity 同会话并存 | [x] |
| V1b | Gateway 执行关节目标 | MuJoCo 伺服；smoke 改角可见 | [x] |
| V1c | 键鼠关节滑条 UX | Web/桌面：每关节滑条 + 可选快捷键；映射文档化 | [x] |
| V1d | 成对录制 | frames/export 含关节 cmd↔joints；3D 回放臂动 | [x] |

### V3 · IL 任务

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| V3a | 车间主目标 v1 | 箱子进入料箱区 → `objective_complete`（允许夹爪辅助推） | [x] |
| V3b | outcome 服务 IL | success/fail/abort 可筛；正样本导出默认 success | [x] |
| V3c | （可选）真夹取抬起 | 闭合+接触+离地；不阻塞 V3a | [x] |
| V-IL | IL 冒烟 | 至少 1 条 `demo_workshop` + success 可被 export 滤出 | [x] |

### V5 · 克制

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| V5 | 演示克制 | 不再开 city 观感专题；city 仅 bugfix | [x] 策略已生效 |

### 演示打磨（本批入库）

| 项 | 说明 | 状态 |
|----|------|------|
| Workshop Factory 皮 + 铺地 | `workshop_dress.gd` + Kenney Factory 子集；viewer_only | [x] |
| Web `#mw-hud` 点击收起 | `shell.html` + `MW_SET_HUD`；`localStorage` 记忆 | [x] |

---

## Done（W2.3 → W3 → T2.6 · 2026-07-19）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W2.3 | **一会话一 MjData**（Room 私房） | 两标签互不踩仿真 | [x] |
| W3.1 | Room + 多实体 state fan-out | 两人互见对方傀儡 | [x] |
| W3.2 | 客户端多傀儡 | 按 entity_id；己方可控 | [x] |
| W3.3 | `join.room_id`（默认私房；`demo` 共享） | 满员 `ROOM_FULL`；各控一台 | [x] |
| T2.6 | state/录制输出 `joints`(+`joint_vels`) | 样例 + smoke | [x] |

本机双端 e2e：

```bash
.venv/bin/python gateway/echo_server.py --no-record
.venv/bin/python scripts/serve_web_demo.py
# http://127.0.0.1:8080/?room=demo
.venv/bin/python scripts/ws_smoke_test.py
```

---

## Done（W1 · 本地 Web 单人）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W1.1–W1.4 | Web 模板 / 导出 / 托管 / 浏览器遥操 | 见历史 | [x] |

---

## Later / 暂缓

| ID | 任务 | 状态 |
|----|------|------|
| W2.1 / W2.2 / W2.4 | 公网 HTTPS / wss / 运维页 | [~] 见 Next PL2 |
| T2.7 | 输入延迟补偿 v0 | [~] |
| — | `demo` 房录制双实体抽检 | [ ] 可选 |
| F7 | 机甲互撞（共享 MjData） | 见 Done F7 | [x] |
| F4 / T4.2 | `.tscn` → 契约导出 | 见 Done F4 | [x] |

---

## Done（POC 基线，摘要）

| 里程碑 | 状态 |
|--------|------|
| M1–M4 · T3.4 macOS · W1 Web · T2.3 障碍 | [x] |
| W2.3 隔离 · W3 同关两人 · T2.6 joints | [x] |
| V 线冻结 · D 线演示 · H4–H6 Hub | [x] |

---

## Later（原 Phase 4 余项）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| T3.2 | 开环重放增强 | `replay_xy` 已覆盖轨迹 | [ ] |
| T4.1 | Worker 池 | 与 W2.3 对齐 | [ ] |
| T4.4 / T4.5 | 评测 API / AI 同通道 | 可与 PL1 API 合并设计 | [ ] |
| T4.6 | 动态可交互物（推箱 L2 / D2） | `dynamic_props` + `push_box_smoke.py` | [x] |

---

## 明确不做（近期）

- 完整账号体系 / 计费 / 编辑器 SaaS（PL2 仅最小运维鉴权，不等于账号产品）
- Godot 内嵌 MuJoCo / 引擎 Multiplayer 同步位姿  
- 未选许可证清晰模型前批量接入「任意 URDF」  
- 公网 Demo 优先于 P1 / PL1（除非明确要对外）
