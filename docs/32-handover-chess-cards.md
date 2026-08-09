# 32 · 会话交接 · 棋牌室卡牌双人化 + Fun 二梯队续做

| 字段 | 值 |
|------|-----|
| **状态** | 进行中（新 session 从此续做） |
| **创建** | 2026-08-09 |
| **关联** | [09-todo.md](09-todo.md) Fun-S/R/E · [19-changelog.md](19-changelog.md) · [31-handover-fun-tier2.md](31-handover-fun-tier2.md) |
| **范围** | 棋牌室（21 点多人 / 五对人机）已交付并上线；下一步 Fun-S 皮肤 / Fun-R 邀请链接 / Fun-E 围观表情 |

## 0. 当前状态一句话

21 点已升级为**双座多手牌共享庄家**（轮转行动、旁观入座、禁止局中重置）；五对支持**人机**（5 秒无人加入自动匹配 AI 执红）并新增**显式 5 秒倒计时**（`ai_fill_at` 字段 + 客户端倒计时标签）；五对牌堆唯一性 bug（4×54 误建 + JOKER 身份歧义）、手牌溢出桌布 UI 均已修复；blackjack/wudui 牌桌已放大（felt 上限 920×520）；手牌配对归组 + 键盘选牌出牌 + AI 记牌策略 + Web 丢包修复 + 五对动画套件（发牌/出牌/吃牌飞行 + 配对闪光 + 胜利脉冲）已上线。线上 build `<BUILD>`（四批发版）。

> 2026-08-09 二批：五对倒计时 + 牌桌放大（见 [19-changelog.md](19-changelog.md) 同日条目）。`chess_table_update` wudui detail 新增 `ai_fill_at`（unix 截止时间戳，仅等待期下发）；客户端 `_sync_ai_countdown`/`_tick_ai_countdown` 0.25s Timer 驱动标签，关闭牌桌即停。验证链同第 2 节，wudui_smoke 已加 `ai_fill_at` 三态断言（等待期存在 / 双人入座清零 / AI 补位后清零）。

> 2026-08-09 三批：五对手牌体验 + AI 记牌 + Web 丢包修复（见 19-changelog 同日条目）。手牌按「对子|散牌」分区绘制（`_wudui_grouped_hand`/`_wudui_hand_rects` 绘制热区同函数）；轮到我自动选中风险最低散牌（`_wudui_default_discard`，与 AI `_ai_choose_discard` 同评分）；←/→ 切散牌、↑ 一键出牌（黑出牌/红吃或过），选中卡放大 + 卡上「出牌/吃牌/过牌」按钮。`wudui.py` 记牌靠 `_remaining_by_rank()`（deck 余量即出过牌），`to_detail` 新增 `deck_remaining`。Web 控制台 `Buffer payload full` 已缓解：出站缓冲 256KB + 空闲速度命令去重 + `ws.outbound_full()` 水位保护。wudui_smoke 新增 AI 选牌确定性断言 + `deck_remaining` 断言。

> 2026-08-09 四批：五对动画套件（发牌/出牌/吃牌飞行 + 配对闪光 + 胜利脉冲，见 19-changelog 同日条目）。纯客户端：`_wudui_anims` 走 diff→tick→draw 模式（与 `_piece_anims`/`_bj_anims` 一致），`_detect_wudui_changes` 在 `_refresh_board_from_authority` 的 wudui 分支调用；发牌全手 60ms 错峰飞入（0.32s ease-out、0.65→1.0 缩放、8°→0 旋转）；出牌 `fly_out`（0.28s ease-in、-10°→0、牌堆 ghost alpha 0.25）；吃牌 = 弃牌顶飞入红手 + 金环闪光（0.6s，奇→偶 rank 触发）；五对达成赢家整手胜利脉冲（0.9s 错峰 0.08s）。`_play_sfx` 新增 deal/swoosh（每批节流只播一次）。飞行中牌行内 alpha 0、由 `_draw_wudui_anim_overlay` 叠加绘制；首帧/开局快照只记录不动画。验证链 lint + 6 场景编译门全绿（gateway 无变更）。

## 1. 本批次交付清单（git）

| 提交 | 内容 |
|------|------|
| `ac8ff78` | 21 点多人：`gateway/blackjack.py` 重写（`players`/`hands{sid}`/`active_sid`/`results{sid}`），双座入座、resign status 跟随 phase、`chess_reset` 仅局间可用；客户端三行牌桌（庄家/对手/我）+ 对手手牌动画 |
| `9d227eb` | 五对人机：`wudui.py ai_red_move()`（能吃则吃否则过牌）；`ChessTable.ai_task` 5 秒计时补位；真人入座白座取消 vs_ai 接管；客户端等待提示 |
| `85fd5ac` | 自审修复：五对 `_new_deck()` 4×54→单副 54（同牌可在手+堆）；JOKER1/JOKER2 唯一 ID；`_draw` 重洗排除在场牌；21 点旁观不再冒充「你」；删死代码 |
| `72b87fb` | UI 修复：五对 11 张手牌溢出桌布→动态缩放（最小 40px/间距 4px，绘制+热区同步）；按钮行间距 10→6/字号 14（出牌不再被裁）；`MWQuickSit` 显式 preload（headless 类缓存漏注册） |

## 2. 验证链（全部全绿）

```bash
.venv/bin/python scripts/gdscript_lint.py godot/spike/scripts/chessroom.gd
bash scripts/check_scenes_boot.sh                    # 6 场景编译门
.venv/bin/python gateway/echo_server.py &            # 起本地 gateway（需提权）
.venv/bin/python scripts/wudui_smoke.py              # 双人+AI补位+AI应答+真人接管
.venv/bin/python scripts/blackjack_smoke.py          # 双人入座+错回合拒着+轮流停牌+结算
.venv/bin/python scripts/chessroom_smoke.py && .venv/bin/python scripts/ws_smoke_test.py
```

部署：`bash scripts/deploy_playground.sh`（export + rsync + 重启 + curl 校验），发版后线上应回 `MW_BUILD="<日期>-<时分秒>"`。

## 3. 关键实现要点（勿再踩）

- **21 点状态**：`board.phase`（idle/playing/finished）是权威，`table.status` 跟随；客户端按 `active_sid == _effective_sid()` 才显示 H/S 按钮；`results{sid}` 按 sid 取个人结果（`result` 仅向后兼容取第一手）。
- **五对人机**：黑座坐下启动 5s `ai_task`，白座真人入座/黑离座/桌重置都要 `_wudui_cancel_ai_timer`；黑弃牌后 AI 同步走红（`ai_red_move`）再广播。
- **牌面 ID**：五对牌是唯一字符串（`JOKER1/2` 区分双王，`rank_of`/`begins_with` 归一）；客户端选牌/点击热区按字符串匹配，绝不允许同牌字符串重复出现。
- **牌桌布局**：牌宽 64/间距 10 是基准，11 张必须用 `_wudui_card_w(count, area)` 动态缩放（最小 40px）；所有绘制/高亮/点击热区必须用同一套尺寸函数，别写死 `_BJ_CARD_W`。
- **Godot class_name**：headless 编译靠 `.godot/global_script_class_cache.cfg` 索引，新 `class_name` 脚本可能漏注册 → 用方显式 `preload("res://...gd")` 成常量最稳（`MWQuickSit` 教训）。
- **场景编译门盲区**：`check_scenes_boot.sh` 只查 parse error，不跑 draw 回调——`_draw_blackjack_board` 的 `rows[side]` 崩溃（4a99c3c 修）就是发牌后才暴露，运行时 UI 改动务必配合冒烟实测。

## 4. 下一步候选（按 handover-31 续）

| ID | 任务 | 建议入口 |
|----|------|----------|
| Fun-S | 皮肤自选 | `mw_platform` players 表加 `skin` 字段 → `me.html` 下拉选 18 款 Blocky → Gateway join 下发 → `paper_doll` 换 `model_ref` |
| Fun-R | 邀请链接 | join 已支持 `room_id`（`echo_server.py:3330`）；Web 读 `?room=` query 注入 join payload + UI「复制邀请链接」 |
| Fun-E | 围观席+表情 | 桌满入座被拒时给旁观 view（`chess_table_update` 已全员广播）；表情走 `action == "chat"` 通道（`echo_server.py:3049`）4-6 快捷按钮 |

另可打磨：21 点/五对计分榜（`mw_platform` best_lap 模式可复用）、棋室聊天已有（hub_chat_smoke）。

## 5. 环境 / 权限

- 沙箱 `.git` 只读：git add/commit/push、本地 gateway 起 8765、deploy、check_scenes_boot 均需 `require_escalated`。
- playground gateway `10.200.0.14:18081`（wss://playground.dev.databall.tech/ws）；rsync 无 `--delete`，勿删 `/xr/` `/arm/` `/g1/`。
- 事件线：`chess_table_update` detail 在 `msg["payload"]["detail"]`（不是 `msg["detail"]`）。
