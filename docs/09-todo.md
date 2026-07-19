# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | 演示/管道已收口；**下一阶段：纠偏提高数据价值（讨论后开 V\*）** |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md) |
| **Web/多人路线** | [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) |
| **融合路线** | [14-godot-mujoco-fusion.md](14-godot-mujoco-fusion.md) |
| **阶段评审** | [12-status-review.md](12-status-review.md) |
| **跑偏与纠偏** | **[15-course-correction.md](15-course-correction.md)**（战略 SSOT） |

勾选约定：`[ ]` 未做 · `[x]` 完成 · `[-]` 取消 · `[~]` 暂缓

---

## Now（F · Godot ↔ MuJoCo 融合）

> 公网 W2.1/2/4、T2.7 **暂缓**。  
> 详设见 [14](14-godot-mujoco-fusion.md)。铁律不变：Godot 不权威、MuJoCo 不叙事。

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

## Now（D · 演示打磨）

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

> **D 线已收口。** 城市皮/seed/路面不再作为主投入；见 [15](15-course-correction.md) V5。

---

## Next（V · 数据价值纠偏 · 待讨论后开干）

> 诊断与优先级见 **[15-course-correction.md](15-course-correction.md)**。  
> **本表在讨论前不落具体实现勾选**——只占位，避免又开新的观感专题。

| ID | 主题 | 状态 |
|----|------|------|
| V1 | 控制升维（`joint_targets` / 成对录制） | [ ] 待讨论 |
| V2 | 机体升维（多关节 / 非纯 planar） | [ ] 待讨论 |
| V3 | 接触任务加深（堆叠 / 门 / 抓取） | [ ] 待讨论 |
| V4 | 数据分层（标签 / 难度 / 导出过滤） | [ ] 待讨论 |
| V5 | 演示克制（观感项默认暂缓） | [ ] 待讨论 |

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
| W2.1 / W2.2 / W2.4 | 公网 HTTPS / wss / 运维页 | [~] |
| T2.7 | 输入延迟补偿 v0 | [~] |
| — | `demo` 房录制双实体抽检 | [ ] 可选 |
| F7 | 机甲互撞（共享 MjData） | 见 Now F7 | [x] |
| F4 / T4.2 | `.tscn` → 契约导出 | 见 Now F4 | [x] |

---

## Done（POC 基线，摘要）

| 里程碑 | 状态 |
|--------|------|
| M1–M4 · T3.4 macOS · W1 Web · T2.3 障碍 | [x] |
| W2.3 隔离 · W3 同关两人 · T2.6 joints | [x] |

---

## Later（原 Phase 4 余项）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| T3.2 | 开环重放增强 | `replay_xy` 已覆盖轨迹 | [ ] |
| T4.1 | Worker 池 | 与 W2.3 对齐 | [ ] |
| T4.4 / T4.5 | 评测 API / AI 同通道 | [ ] |
| T4.6 | 动态可交互物（推箱 L2 / D2） | `dynamic_props` + `push_box_smoke.py` | [x] |

---

## 明确不做（近期）

- 账号 / 计费 / 编辑器 SaaS  
- Godot 内嵌 MuJoCo / 引擎 Multiplayer 同步位姿  
- 未选许可证清晰模型前批量接入「任意 URDF」  
- 公网 Demo 优先于 F0–F2（除非明确要对外）
