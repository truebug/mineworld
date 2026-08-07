# 31 · 会话交接 · 体验二梯队（Fun-H/Q/S/R/G/E）+ 留存切片

| 字段 | 值 |
|------|-----|
| **状态** | 进行中（新 session 从此续做） |
| **创建** | 2026-08-07 |
| **关联** | [09-todo.md](09-todo.md) Fun-H/Q/S/R/G/E · [19-changelog.md](19-changelog.md) |
| **范围** | 真机遥操**不开**（商业闭源走通用桥接）· 只做「有趣/好玩/易用/好看」 |

## 0. 背景

- 前提：mineworld 暂不接入其他真机（真机遥操是商业闭源项目，仅用通用桥接集成）。HW-2.5 真机联调继续挂起。
- 方向：把「能玩」变「想回来玩」。第一梯队（音效/棋牌计分/Race幽灵/围观）暂不排，本次先做**第二梯队 4 项** + 追加 2 项留存切片。

## 1. 待办（todolist 已入 [09-todo.md](09-todo.md)）

| ID | 任务 | 验收 | 建议做法 |
|----|------|------|----------|
| ~~Fun-H~~ ✅ | Hub 母港氛围 **Done 2026-08-07** | `hub_daynight.gd` 150s 昼夜（sky shader + Sun/ambient）；`hub_orbit_ring.gd` 全息环灯；NPC 游走/环境音乐此前已在 | 见 [19-changelog.md](19-changelog.md) |
| ~~Fun-Q~~ ✅ | 一键开局 **Done 2026-08-07** | chessroom 右下「⚡ 快速入座 (J)」+ J 键；优先加入 AI 单机组（不重置），全满聊天提示 | 纯客户端 `chessroom.gd`；见 [19-changelog.md](19-changelog.md) |
| Fun-S | 皮肤自选 | Portal「我的」页选 Blocky 皮肤（18 款 character-a..r）存 player profile；Hub/桌面对应 | `mw_platform` players 表加 `skin` 字段；`me.html` 加下拉/缩略图；Gateway join 时下发；`paper_doll` 换 `model_ref` |
| Fun-R | 邀请链接 | `?room=xxx` 私密房码，复制链接拉人开黑（双人进同房） | join 已支持 `room_id`（`gateway/echo_server.py:3330`）；Web 端读 query 参数注入 join payload；UI 加「复制邀请链接」按钮 |
| Fun-G | 幽灵挑战 | `MWGhost` 今日最佳榜 + 一键挑战，每日重置（demo_race 可见幽灵车） | `mw/ghost_car.gd` 已 fetch 最快 session；加「今日最佳」筛选（按 date）+ HUD 一键挑战按钮 + 每日重置逻辑 |
| Fun-E | 围观席 + 表情 | 桌满可旁观任意牌局（当前只能站着看 HUD）；4-6 快捷表情/喝彩复用 chat | 旁观：桌满入座被拒时给旁观 view（`chess_table_update` 已全员广播）；表情：`echo_server.py:3049` `action == "chat"` 通道，客户端 4-6 按钮快捷发 predefined emote |

## 2. 环境 / 权限要点

- 沙箱：`.git` 只读，**所有 git 写操作需 `require_escalated`**；本地 gateway 绑端口（8765）跑 smoke 也需提权。
- 已批准前缀可复用：`[".venv/bin/python","scripts/*"]`、`["bash","scripts/deploy_playground.sh"]`、`["bash","scripts/check_scenes_boot.sh"]`、`["/Applications/Godot.app/Contents/MacOS/Godot"]`、`["git","add|commit|push"]`。
- 部署：`bash scripts/deploy_playground.sh`（rsync 无 `--delete`，勿删 `/xr/` `/arm/` `/g1/`）。发版后 curl 验证三前台 + `?level=demo_chessroom` 200。
- 事件线格式：`chess_table_update` detail 在 `msg["payload"]["detail"]`（**不是** `msg["detail"]`）。
- playground gateway：`10.200.0.14:18081`（wss://playground.dev.databall.tech/ws），admin `127.0.0.1:8770`。
- 验证链：`scripts/wudui_smoke.py` / `scripts/blackjack_smoke.py` / `scripts/ws_smoke_test.py` + `scripts/gdscript_lint.py` + 6 场景编译门（`bash scripts/check_scenes_boot.sh`）。

## 3. 最近修复备忘（勿再踩）

- `_draw_blackjack_board`：`rows` 改 Array 后循环索引已修为 `side["cards"]`/`side["y"]`（`4a99c3c`）。
- GDScript 不支持元组字面量 `in ("a","b")` → 用 `in ["a","b"]`。
- GDScript 字典 `.get()` 返回 Variant 触发「推断为 Variant」编译门 → 显式 `str()`。
- 五对 `JOKER` 已改 `JOKER1/JOKER2`（`rank_of` 用 `startswith`），重洗排除在手/在弃牌堆的卡。
- wudui_smoke 红色过牌 flake：`pass_turn` 先抓牌后验弃牌，预选散牌可能被补牌配成对 → 拒着后 `chess_sit` 刷新重选（已修，8 重试）。

## 4. 建议首刀

从 **Fun-Q 一键开局** 或 **Fun-H Hub 氛围** 开刀（纯客户端/轻量，快速出效果）。Fun-G 幽灵挑战复用现有 `MWGhost` 最成熟。Fun-S/Fun-R 涉及 `mw_platform` schema + join 流程，放后。
