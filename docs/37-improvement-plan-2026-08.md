# 37 · 平台观感/体验/扩展性改进计划（2026-08-20）

| 字段 | 值 |
|------|-----|
| **状态** | Active · P0+P1 Done · P2-1 刀1 Done（2026-08-20）· Next = P2-1 刀2（rules adapters）/ P2-2 rooms 基类 |
| **日期** | 2026-08-20 |
| **来源** | 全量 review（2026-08-20）：观感 3 短板 + 体验 3 短板 + 扩展性 3 风险 |
| **关联** | [09](09-todo.md) · [20](20-platform-portal.md) · [24](24-hub-mothership.md) · [25](25-qa-local-export.md) · [35](35-splat-render-handover.md) |

> 北极星不变：太空机器人学院 + 竞技场。本计划只解决「用户观感 / 操作体验 / 扩展性」三件事，不开新品类。
> 实测基线（2026-08-20）：`dist/web` 68MB，其中 `index.wasm` 39.5MB、`index.pck` 11MB；`chessroom.gd` 3468 行（全仓最大 god-object）；`ws_client.gd` 已有链接层 auto-reconnect，缺房间态恢复。

---

## P0 · 留存生死线（先做，2 个切片）

### P0-1 · Splat-P1d + 断线状态恢复（合并切片）

P1d（看/走提频 pose、静止降频）按 [35](35-splat-render-handover.md) §2 执行，**同刀**补状态恢复：

| 步 | 做啥 | 验收 |
|----|------|------|
| a | Gateway：join 幂等化——同 `player_id`+`room` 重 join 返回当前房间快照（成员/桌位/棋局进行态/计时态），不重置 | `ws_smoke` 增补：断线重 join 后桌位不变 |
| b | Godot `ws_client.gd`：reconnect 成功后自动重发 hello→join（带断前 room/level/mode），`_on_scene/_on_state` 幂等重建傀儡 | 拔网 10s 恢复：自机位姿 ≤2s 收敛，桌局不丢 |
| c | HUD：重连横幅三态已有，补「恢复中…/已恢复」终点文案；重连期间输入本地缓冲不丢字（聊天框） | 公网手动验证一遍过 |

红线：P1d 的 pose 提频不得破坏 chessroom 节流 hardening（2026-08-17 教训）。

### P0-2 · 统一新手指引层 `MWTutorial`

| 步 | 做啥 | 验收 |
|----|------|------|
| a | 抽 `godot/spike/scripts/mw/mw_tutorial.gd`：数据驱动按键提示浮层（每关一张「控制卡」：键位表 + 目标一句 + 成功条件），首进关卡强制 3 步高亮，可 Esc 跳过；`localStorage` 记「已看」 | 四关（hub/workshop/city+rake/chessroom）各挂一份控制卡，硬刷新首进可见 |
| b | 把 `tutorial_place_*` 的引导话术迁入同层，工坊不再私有 | 既有 smoke 不回归 |
| c | Portal `index.html`：触屏/移动 UA 检测 → 降级提示页（「本作需键鼠，建议桌面浏览器」+ 仍可逛 Portal/榜单/回放），不是白屏进不去 | 手机 UA 开 `/` 见提示页，`/portal/` 可用 |

## P1 · 观感与平台化（接下来 2–3 个切片）

### P1-1 · 首屏性能预算与量化

| 步 | 做啥 | 验收 |
|----|------|------|
| a | 服务端压缩：ALB/nginx 对 `.wasm/.pck` 开 gzip（wasm 39.5MB 期望 → ~12MB）；`deploy_playground.sh` 后 curl `-H 'Accept-Encoding: gzip'` 断言 `Content-Encoding` | 部署脚本内建检查，FAIL 即报警 |
| b | 构建报告：`export_godot.sh` 末尾输出体积表 + TTI 探针页（performance.timing 打点，`?perf=1` 时上报首帧耗时）；目标 4G <8s 首帧 | 报告入库 changelog 一行 |
| c | 首屏 v1：品牌进度条按 pck 下载真实百分比；wasm 编译期给静态视觉（不再是 v0 转圈） | 本地限速 4G 录屏确认 |

### P1-2 · Splat 皮肤机制化 + 场景观感提升

| 步 | 做啥 | 验收 |
|----|------|------|
| a | 把棋牌室 splat 挂载（occupancy/floor-snap/节流）抽成「场景皮肤」通用机制：关卡侧声明 `skin = splat:<id>`，Hub 门卡片可预告 | city 或 hub 外场任选一处挂第二个 splat 皮肤验证通用性 |
| b | 观感预算：每关一处「惊艳点」——race 起点线光带、city 天际线 emissive、hub 已有昼夜；用现成 CC0 HDRI/粒子，不写新渲染管线 | 截图进 PR |
| c | 资产台账：全部进 `ASSETS.md`，NC/SA 零容忍（铁律重申） | 台账 diff 随 PR |

## P2 · 结构性还债（与 P1 并行排队，不阻塞 P0/P1）

### P2-1 · 拆 chessroom.gd（3468 → 目标 <1200）

| 步 | 做啥 | 验收 |
|----|------|------|
| a | 抽 `mw/mw_table.gd`：桌位/入座/旁观/表情/皮肤同步（桌游域公共件） | 行为零变化，`chessroom_smoke/wudui_smoke/blackjack_smoke` 全绿 |
| b | 每游戏一个 rules adapter（gomoku/halma/junqi/wudui/blackjack 各一文件，统一 `init/apply_cmd/render` 接口） | 新增「井字棋 demo 桌」≤100 行验证扩展性 |
| c | 先写 ADR（`docs/adr/`）落接口再动手；分两刀合并，每刀 smoke 全绿 | ADR 入库 |

### P2-2 · Gateway 房间管理器 `rooms/`

| 步 | 做啥 | 验收 |
|----|------|------|
| a | 抽 `Room` 基类：成员/旁观/满员策略/模式字段（solo/duel/shared_ffa）/生命周期钩子；`echo_server.py` 只留路由 | race/chess/city 三房迁移后全 smoke 绿 |
| b | 为 B3 后续铺路：私密房（`?room=` 已有雏形）、匹配队列 stub、观战席通用化 | 文档冻结边界，实现只做 stub |

### P2-3 · TD1/TD2 解冻条件

P0-1（重 join 快照）和 P1d 会反复触碰 main.gd net 层与 hub.gd 门系统——若这两刀中任一处改动 >150 行，则先把对应 TD 的 ADR 补写再动手；否则继续暂缓，不提前拆。

## 明确不做（本期）

- 触屏/摇杆复活（只做降级提示，见 P0-2c）
- Hub 上 MuJoCo、棋牌室新桌型、独立匹配 SaaS、`databall.cloud` 双域名推进
- 新渲染管线 / 自研 PBR 美术（观感提升只用现成资产 + 光照/后处理调参）

## 排期建议（切片粒度）

| 序 | 切片 | 依赖 | 估计 |
|----|------|------|------|
| 1 | P0-1 P1d+状态恢复 | 无 | 1–2 session |
| 2 | P0-2 MWTutorial+触屏降级 | 无 | 1 session |
| 3 | P1-1 压缩+构建报告+首屏 v1 | 需碰部署链 | 1 session |
| 4 | P1-2 皮肤机制化+惊艳点 | P0-1 | 1–2 session |
| 5 | P2-1 chessroom 拆分（两刀） | 无（早还早轻松） | 2 session |
| 6 | P2-2 rooms 基类 | P2-1 之后更顺 | 1–2 session |
