# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-17 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | 打通 MVP：进关 → 接管 → MuJoCo 驱动 → 落盘 |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md)（POC 规格 + MVP 薄架构） |

勾选约定：`[ ]` 未做 · `[x]` 完成 · `[-]` 取消

---

## Now（本周 / Phase 0→1 启动）

### A. 钉死 3 个决策（阻塞后续实现）

> 默认提案已写入 [11 §3](11-poc-mvp-architecture.md#3-poc-冻结默认讨论通过即-closed)；评审勾选即可。

| ID | 任务 | 建议默认 | 状态 |
|----|------|----------|------|
| T0.1 | 坐标系：米 + 右手系；**Z-up**（对齐 MuJoCo）还是 Y-up（对齐部分游戏引擎） | **Z-up**，GDevelop 侧做一次映射 | [x] |
| T0.2 | MVP 控制模式 | **`velocity`**（vx, vy, yaw_rate） | [x] |
| T0.3 | Gateway 语言 | **Python 3.11+** | [x] |
| T0.3b | 机甲策略 + POC 工期 | **自建盒子**；**5 工作日**（见 `11` §9.1） | [x] |

已完成：`10-open-questions` C2/P2/P3/E2/C3 Closed；`11` §9.1 已填；ADR-001/002 → Accepted。

### B. 补齐契约 SSOT

| ID | 任务 | 产出 | 状态 |
|----|------|------|------|
| T0.4 | 补 `schemas/ws-messages.v0.json` | 与 `03` 对齐；可扩展信封 | [x] |
| T0.5 | 补 `schemas/recording-session.v0.json` | header + frame；可扩 features/extensions | [x] |
| T0.6 | 定 `dt` / `tick_rate` 默认值 | `dt=0.02`、sim 50Hz、state 20Hz（`11` D4 + schema README） | [x] |
| T0.7 | 弹性化 `scene-contract` + `common.v0` + 示例 | `shape`、extensions、开放枚举 | [x] |

### C. Phase 1 连通（假物理即可）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| T1.1 | `gateway/`：最小 WS 服务（hello / join / 收 cmd / 发假 state） | `websockets`，本地 `ws://127.0.0.1:8765` | [x] |
| T1.2 | `examples/`：用 `wscat` / 小脚本验证协议 | `scripts/ws_smoke_test.py` → `smoke OK` | [x] |
| T1.3 | GDevelop：本地工程 + WebSocket Client | 连接成功、解析 `hello`、存 `session_id` | [ ] |
| T1.4 | GDevelop：发 `cmd` + 用假 `state` 移动 3D 对象 | 键盘操控「假机甲」可见移动 | [ ] |
| T1.5 | 固化 `examples/contracts/tutorial_01.json` | 与 GDevelop 场景物体 ID 一致 | [ ] |

**Phase 1 里程碑（M1）**：GDevelop ↔ Gateway JSON 互通。

---

## Next（Phase 2：真仿真）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| T2.1 | `mujoco/`：最小 MJCF（平地 + 简化机甲） | 无头 `mj_step` 10s 稳定 | [ ] |
| T2.2 | Gateway 接入 MuJoCo：`cmd`→ctrl，`state`←qpos | 位姿由仿真驱动，非假数据 | [ ] |
| T2.3 | 按契约加载 `static_obstacles`（盒体） | 碰到墙有物理反应 | [ ] |
| T2.4 | `take_control` / `release_control` | 事件入库与客户端 UI | [ ] |
| T2.5 | 录制：`sessions/<id>/header.json` + `frames.jsonl` | 单会话 ≥10s 可落盘 | [ ] |

**Phase 2 里程碑（M2+M3）**：真物理驱动 + 可录制。

---

## Later（Phase 3–4）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| T3.1 | 终点触发器 → `objective_complete` | 网关判定，防客户端作弊 | [ ] |
| T3.2 | `scripts/replay-session.py` | 读 JSONL 画轨迹 / 可选开环重算 | [ ] |
| T3.3 | 第二关卡（验证编辑器工作流） | 仍手写契约即可 | [ ] |
| T3.4 | HTML5 导出 + 静态托管说明 | `gdexporter` 或官方 CLI | [ ] |
| T4.1 | 多会话 / Worker 池 | 水平扩展无头 MuJoCo | [ ] |
| T4.2 | 场景契约从 GDevelop 导出扩展 | 替代手写 JSON | [ ] |
| T4.3 | Blender → 资产管线（可选 MCP） | 非 MVP 阻塞项 | [ ] |
| T4.4 | 学习/评测 API 草案 | 数据对外接口 | [ ] |

---

## 建议执行顺序（最短路径）

```text
T0.1–T0.3 决策
    → T0.4–T0.6 Schema / 频率
    → T1.1 Gateway echo
    → T1.3–T1.4 GDevelop 联调
    → T2.1–T2.2 真 MuJoCo
    → T2.5 录制
    → T3.1 任务闭环
```

---

## 本周建议（若只做 3 件事）

1. **拍板** T0.1–T0.3（坐标系 / velocity / Python）
2. **写** T1.1 Gateway echo（半天级）
3. **联调** T1.3–T1.4 GDevelop WebSocket（一天级）

---

## 明确不做（MVP 范围外）

- GDevelop 官方多人联机当物理桥
- 自托管完整 GDevelop SaaS 编辑器
- 账号体系 / 计费 / 数据合规模板（可后置）
- 关节级 50Hz 全量录制优化（先能录再优化）
