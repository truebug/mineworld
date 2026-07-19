# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | 多人本机 Demo 已通；F0–F8 融合完成 |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md) |
| **Web/多人路线** | [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) |
| **融合路线** | [14-godot-mujoco-fusion.md](14-godot-mujoco-fusion.md) |
| **阶段评审** | [12-status-review.md](12-status-review.md) |

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
| T4.6 | 动态可交互物 L1 | [ ] |

---

## 明确不做（近期）

- 账号 / 计费 / 编辑器 SaaS  
- Godot 内嵌 MuJoCo / 引擎 Multiplayer 同步位姿  
- 未选许可证清晰模型前批量接入「任意 URDF」  
- 公网 Demo 优先于 F0–F2（除非明确要对外）
