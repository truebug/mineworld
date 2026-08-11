# 19 · 变更记录（Changelog）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **关联** | [09-todo.md](09-todo.md) · [18-hub-dungeon.md](18-hub-dungeon.md) · [16-value-sprint.md](16-value-sprint.md) · [20-platform-portal.md](20-platform-portal.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) · [25-qa-local-export.md](25-qa-local-export.md) · [26-junqi-ssot.md](26-junqi-ssot.md) |


## 2026-08-11 · Web 输入：已知可进基线 + canvas 解锁会卡死（暂停修鼠标）

- **可进基线**：`110ca66` / playground 以该树部署；键盘可用。
- **对照结论（已复现）**：仅去掉 `#canvas{pointer-events:none}`（`mw_touch_pad.js` 永不锁画布）即可在 Hub `hub life` 打印后卡死；回退该改动即恢复。与是否改 `camera_rig`、是否重打 pck 无关。
- **机制（工作假设）**：Godot Web 单线程；解锁后指针事件涌入 `_unhandled_input`，叠在 HubLife 首帧负载上打满主线程。canvas 锁原为 Pico 防甩视角，现成为「能进」的护栏。
- **产品态**：主站暂保留触控盘/手柄路径与 canvas 锁；桌面鼠标失灵未解。下一步不走「直接解锁 canvas」；待定：主站默认关 Pico 盘（`?touch=1` 才开）以优先键鼠，或接受键鼠受损直至另案。
- **禁止**：在未找到非卡死方案前，勿再对 playground 默认部署「永不锁 canvas」。

## 2026-08-11 · 修复：Mac 触控板被粘性虚拟盘盖住

- **现象**：MacBook 强刷后左右虚拟盘仍全开，触控板点 canvas 无响应；另一台 PC 外接鼠标正常。
- **根因**：桌面点过「虚拟键」或 `?touch=1` 后 `localStorage.mw-touch-pad=1` 持久展开全屏叠层；即便不锁 `pointer-events`，高层 `#mw-touch-pad` 仍干扰触控板命中。
- **修复**：`desktopOS()` 排除 Mac/Win/Linux 桌面；桌面忽略粘性 localStorage、启动清掉 `=1`、收起态去掉全屏 inset；`camera_rig` 仅当 JS 严格 `=== true` 才吞鼠标。Pico/粗指针行为不变。
- 现网：`MW_BUILD=20260811-095606`。

## 2026-08-11 · 触控/手柄方向修正 + 出站缓冲加固（Buffer payload full）

- **摇杆方向修正**：`mw_touch_pad.js` `stickInvertOn()` 原默认开启（仅 `?stickInvert=0` 才关），叠加「上→W、右→E」自然映射后变成双重取反——上推后退、右推左转。改为默认不反转（`?stickInvert=1` 才反转），虚拟摇杆与 Gamepad 轴统一为自然方向（上=前进、右=右转）。
- **出站缓冲加固（Buffer payload full）**：`main.gd` 速度命令补上空闲去重（原先静止时仍每 20Hz 发全零命令，连接卡顿时快速灌满缓冲）+ 出站水位保护（`_send_drive_cmd` 同款）；`[MW] cmd ...` 打印改为命令变化时输出（原移动时每 tick 刷屏）；`ws_client.gd` 出站缓冲 256KB→512KB 留余量。
- 验证：node --check + gdscript lint 0 finding + 6 场景编译门全绿。

## 2026-08-11 · 修复：触控摇杆误锁桌面鼠标 + 手柄轮询与摇杆盘解耦

- **鼠标被干没的根因**：`mw_touch_pad.js` 自动开启条件过宽——`navigator.xr` 在桌面 Chrome 无头显也存在、`navigator.maxTouchPoints > 0` 命中带触摸屏的笔记本，普通桌面浏览器默认点亮摇杆盘 → `body.mw-tp-canvas-lock #canvas{pointer-events:none !important}` 锁死整个 canvas，`camera_rig.gd` 又按 `_MW_TOUCH_PAD_ACTIVE` 吞掉全部鼠标按键/移动事件（双保险把鼠标双杀）。
- **修复**：自动开启只认「粗指针/真触屏」——`(pointer: coarse)` 主指针或 Pico/Android/Mobile/Quest UA；删掉裸 `maxTouchPoints` 与 `navigator.xr` 两个桌面误触发。新增 `_MW_CANVAS_LOCKED`（仅粗指针设备才锁 canvas），`camera_rig.gd` 改读它；`?touch=1` 桌面强制显示摇杆盘也不再锁鼠标。
- **手柄不失效保证**：`pollGamepad()` 闸门从 `_MW_TOUCH_PAD_ACTIVE`（摇杆盘可见）改为 `_MW_TOUCH_PAD_LOADED`（脚本加载即常真），手柄轮询与摇杆盘 UI/canvas 锁彻底解耦；手柄 → `setKey` → `window._mw_keys` → `mw_web_input.gd`，与鼠标通道互不干扰。`gamepadconnected`/首推杆自动解锁/「启用双手柄」按钮路径均保留。
- 验证：node --check + gdscript lint 0 finding + 6 场景编译门全绿。

## 2026-08-09 · 五对动画套件（发牌/出牌/吃牌飞行 + 配对闪光 + 五对达成）

- **发牌动画**：开局/重发全手按 60ms 错峰飞入（`fly_in`，0.32s ease-out，0.65→1.0 缩放，8°→0 旋转），视觉上「牌飞上桌」。
- **出牌/吃牌动画**：出牌 `fly_out`（0.28s ease-in，-10°→0 旋转，飞向牌堆 ghost alpha 0.25）；吃牌 = 弃牌顶飞入红手 + 配对金环闪光（`flash` 0.6s，奇→偶 rank 触发，吃牌场景延迟 -0.28s 对齐）。
- **五对达成**：赢家整手胜利脉冲（0.9s 错峰 0.08s 缩放 + 金色高亮）。
- **音效**：`_play_sfx` 新增 `deal`/`swoosh`（web 一次性触发，每批节流只播一次，避免批量 AudioContext）。
- **实现**：`_wudui_anims` 走 diff→tick→draw 模式（与 `_piece_anims`/`_bj_anims` 一致），`_detect_wudui_changes` 在 `_refresh_board_from_authority` 的 wudui 分支调用；飞行中牌行内 alpha 0、由 `_draw_wudui_anim_overlay` 叠加绘制（旋转用 `draw_set_transform`）；首帧/开局快照只记录不动画。
- 验证：gdscript lint 0 finding + 6 场景编译门两次全绿（纯客户端，gateway 无变更）。

## 2026-08-09 · 五对手牌体验（配对归组 + 键盘出牌 + 智能选牌）+ AI 记牌策略 + Web 丢包修复

- **配对自动归组**：双方手牌按「对子 | 散牌」分区绘制（`_wudui_grouped_hand`/`_wudui_hand_rects`，绘制与热区共用同一布局），对子与散牌间画分隔线，一眼看出差几对。
- **默认选中智能散牌**：轮到我时自动选中风险最低的散牌（`_wudui_default_discard`，与 AI 同款评分：对手奇张可立即吃 → 1000 惩罚 + 牌堆剩余张数）。
- **键盘出牌**：←/→ 切换散牌选中（`_wudui_cycle_sel`），↑ 一键出牌（黑=出牌，红=可吃则吃否则过牌，`_on_wudui_primary`）；Web（ArrowLeft/Right/Up）+ 原生（KEY_LEFT/RIGHT/UP）双路径。
- **选中卡放大 + 卡上按钮**：选中的散牌放大 1.25× 并上浮（黑↑/红↓），旁边渲染「出牌/吃牌/过牌」按钮（`_wudui_btn_rect` 参与点击判定）。
- **AI 记牌策略**：`gateway/wudui.py` 新增 `_remaining_by_rank()`（牌堆余量 = 权威记牌）与 `_ai_choose_discard()`（对手奇张吃牌威胁 1000 惩罚 + 牌堆剩余概率，min 选最安全散牌），吃牌弃牌与过牌弃牌都走该策略；`to_detail` 新增 `deck_remaining` 下发，客户端默认选牌与 AI 同源。
- **Web 丢包修复**：Godot Web 导出 WebSocket 出站缓冲满（`Buffer payload full! Dropping data.`）→ 出站缓冲 64KB→256KB（`ws_client.gd`）+ 空闲速度命令去重（棋牌室/母港，全零命令不再每 tick 发送）+ 出站水位保护 `ws.outbound_full()`（拥堵时跳过 lossy 速度命令，main.gd 同步）。
- 验证：gdscript lint 0 finding + 6 场景编译门 + wudui（含 AI 选牌确定性断言、`deck_remaining` 断言）/blackjack/chessroom/ws 冒烟全绿。

## 2026-08-09 · 棋牌室卡牌双人化发版 + 五对 5 秒倒计时显式呈现 + 牌桌放大

- **21 点多人**（ac8ff78）：`gateway/blackjack.py` 重写为 `players`/`hands{sid}`/`active_sid`/`results{sid}`，双座入座、resign status 跟随 phase、`chess_reset` 仅局间可用；客户端三行牌桌（庄家/对手/我）+ 对手手牌动画。
- **五对人机**（9d227eb）：黑座入座后 5 秒无人加入则 AI 执红（`wudui.py ai_red_move` 能吃则吃否则过牌）；真人入座白座取消 vs_ai 接管；等待提示。
- **自审修复**（85fd5ac）：五对牌堆 4×54 误建→单副 54、`JOKER1/JOKER2` 唯一 ID、重洗排除在场牌；21 点旁观视角不再冒充「你」。
- **UI 修复**（72b87fb）：11 张手牌动态缩放（最小 40px/间距 4px，绘制+热区同函数）；按钮行间距/字号收紧；`MWQuickSit` 显式 preload（headless 类缓存漏注册）。
- **5 秒倒计时显式呈现**（本批）：`chess_table_update` wudui detail 新增 `ai_fill_at`（AI 补位截止时间戳，黑方入座即下发）；客户端 0.25s Timer 驱动倒计时标签「无人加入 · N 秒后自动匹配 AI」（i18n 中英）；第二人入座/离座/计时到期/重置均清零。
- **牌桌放大**（本批）：`_fit_board_panel` 对 blackjack/wudui 的 felt 上限 680×380 → 920×520（面板高度余量 150→170），1280×720 下约 968×680。
- 验证：gdscript lint 0 finding + py_compile + 6 场景编译门 + wudui（含 `ai_fill_at` 三态断言）/blackjack/chessroom/ws 冒烟全绿。

## 2026-08-07 · Fun-G 幽灵挑战（今日最佳 + 一键挑战）+ Fun-Q 模块化重构

- 平台：`/api/platform/best_lap` 新增 `today=1` 参数，`store.best_lap_session(level_id, since=)` 按 `created_at >= 当日 00:00 UTC` 过滤（每日重置天然成立）；SQLite 断言验证 all-time/今日/空结果三态。
- `mw/ghost_car.gd`：进场景先取今日最佳、落空自动回退全服最快；`reload()` 一键重载今日挑战；代际守卫（`_gen`）防快速重载时旧 HTTP 回包串档；`describe()` 承载 HUD 文案（今日最佳/全服最快 · 圈速 · G 提示）。
- `main.gd` 只剩分发：G 键（web + 原生双路径）→ `_challenge_today_ghost()`；`_on_ghost_loaded` 直接用 `MWGhost.describe()`。
- 重构：Fun-Q 选桌策略 + 按钮构建抽成 `mw/quick_sit.gd`（`MWQuickSit.pick_table/build_button` 静态方法），chessroom.gd 只留胶水——此前 Fun-Q 直塞 2871 行 god-object 的欠账还清。
- 验证：gdscript lint 0 finding + py_compile + 6 场景编译门 + platform smoke 全绿。

## 2026-08-07 · Fun-H Hub 母港氛围（昼夜循环 + 全息环灯）

- 新增 `hub_daynight.gd`：150 秒昼夜周期，正弦驱动 Sun 能量/色温/角度、环境光、星空 shader（`star_brightness`/`nebula_a/b`），深夜→星云黎明→暖昼→黄昏平滑过渡。
- 新增 `hub_orbit_ring.gd`：广场上方 10.5m 全息吊灯——外环 5.2m 青色缓旋 + 3 颗卫星、内环 3.1m 品红反向倾斜自旋、整体轻微浮沉；自发光材质吃 glow。
- NPC 游走（`hub_patrol_npc` ×3 带气泡）与机房低鸣（`hub_ambient_hum` 程序化音频）此前会话已就绪，本次仅补缺的两项。
- 接线均在 `hub_life.gd::_build`；纯 viewer 装饰，Gateway 无变更；lint 0 finding + 6 场景编译门全绿。

## 2026-08-07 · Fun-Q 一键开局（棋牌室快速入座）

- `chessroom.gd` 新增右下「⚡ 快速入座 (J)」按钮 + J 快捷键：扫描 `chess_table_update` 缓存的 `_tables`，免走路直接入座有空位的桌并开牌界面。
- 选桌策略：优先加入 `status=playing` 的单人 AI 局（入座变 PvP 不重置棋局），其次空桌/等人的桌；牌盘打开时按钮自动隐藏。
- 全满时在房间聊天流提示「所有牌桌已满」；入座成功回执桌名（i18n 中英）。
- 纯客户端改动，Gateway 无变更（`chess_sit` 本无距离校验）；gdscript lint 0 finding + 6 场景编译门 + ws smoke 全绿。

## 2026-08-06 · 代码自审修复：五对牌堆唯一性 + 21 点旁观视角

- **五对牌堆 bug（744ca38 遗留）**：`_new_deck()` 误建 4×54 张（docstring 写明 54 张），同一张牌可同时出现在手牌与弃牌堆，客户端按牌面字符串选牌会一次选中多张、冒烟断言偶发失败；改为单副 54 张。
- **JOKER 身份歧义**：两张王牌共用 `"JOKER"` 字符串，弃牌后再摸到另一张即「手牌+弃牌堆同牌」；改为 `JOKER1`/`JOKER2` 唯一 ID（`rank_of` 及客户端 `_wudui_rank`/`_card_tex_path` 统一 `begins_with("JOKER")` 归一）。
- **重洗污染**：`_draw()` 牌不足时整副重洗会带回在场牌 → 重洗排除双方手牌与弃牌堆；300 局随机+AI 对打 sanity 全程无重复牌。
- **21 点旁观视角**：旁观者不再把第一手牌（player_cards 回退）画在底行冒充「你」，全部手牌按对手行渲染；`_detect_bj_changes` 同步。
- **整洁**：删 `blackjack.py _settle_dealer` 未使用的 `live`；黑方 5 秒内离座时取消 AI 补位计时（原先靠守卫空转兜底）。
- 冒烟：wudui ×2 + blackjack 全绿；gdscript lint + py_compile 全绿。

## 2026-08-06 · 五对支持人机（5 秒无人加入自动匹配 AI）

- 规则不变、模式复用五子棋/军棋 `vs_ai` 机制：黑座（先手）坐下后启动 5 秒计时，无第二人加入则 `vs_ai=True` 自动发牌（AI 执红）；5 秒内真人入座则取消计时、立即双人发牌。
- `gateway/wudui.py` 新增 `ai_red_move()`：顶弃牌能凑对且有另一张散牌可弃则吃牌，否则过牌（抓 1 弃随机散牌）；天和/五对胜负照常判定。
- echo_server：`ChessTable.ai_task` 承载计时任务；黑方 `card_discard` 成功后 AI 同步走红方并广播；真人中途入座白座 → 取消 vs_ai、重新发牌接管红方；黑方离座/计时守卫防悬空任务。
- 客户端：黑方等待期状态行提示「等待对手加入… 5 秒后无人将匹配 AI」。
- 冒烟：`wudui_smoke.py` 新增三段——AI 补位发牌断言（vs_ai、黑 11/红 10）、黑弃牌后 AI 同步应答（`last_action∈{pass,eat}`、turn 回黑）、真人入座接管（vs_ai=False、重新发牌）。

## 2026-08-06 · 21 点升级为多人共享庄家（双座多手牌）

- Gateway `gateway/blackjack.py` 重写为多人权威：`players`（入座顺序，黑先白后）/ `hands{sid}` / `active_sid` 轮转 / `results{sid}`；天牌 21 直接 blackjack 并入 stands；庄家全员行动后统一补到 ≥17 再逐手结算（win/lose/push/blackjack）；`to_detail()` 新增 `players`/`hands`/`hand_values`/`active_sid`/`results`，保留 `player_cards`/`player_value`/`result` 向后兼容（取第一手）。
- echo_server 接线：乙桌双座可坐（黑先白后）；第二人入座时若局已结束立即对双座发牌，局中入座则旁观至下一局；`chess_reset` 仅 idle/finished 可用（**禁止局中重置**，防止对家掀桌）；离座 `remove_player` 自动判负并推进轮转；resign 后 status 跟随 `board.phase`（修复原先写死 finished 掩盖对手仍在行动的 bug）。
- 客户端 `chessroom.gd`：桌面三行布局（庄家顶行 / 对手中行带点数与结果标签 / 自己底行带结果标签）；hit/stand 按钮改为 `active_sid == 自己` 才显示；状态行区分「要牌 (H) 或 停牌 (S)」与「等待对手行动…」；结果横幅按 `results[my_sid]` 渲染；发牌/翻牌动画扩展到对手手牌（`_bj_prev` 按 sid 记录）。
- 五对顺手修复：结算后清 `_wudui_sel`、手牌无选中卡自动清选中、跨桌隐藏五对操作按钮。
- 冒烟：`scripts/blackjack_smoke.py` 扩展双人全流程（双 client 入座 → 双人发牌断言 → 错回合 `BJ_NOT_YOUR_TURN` 拒着 → 轮流停牌 → 各自 result + 庄家 ≥17 规则断言 → 旁观入座 → reset 双人发牌）；ws/chessroom/wudui/hub_chat/duel 五回归 + 6 场景编译门全绿。

## 2026-08-06 · 棋牌室：Kenney CC0 牌面贴图 + 规则说明弹窗

- 牌面美术：入库 Kenney Playing Cards Pack（CC0 · `godot/spike/assets/kenney_cards/`，含 `License.txt` 与目录台账；根 `ASSETS.md` 台账已登记）；`chessroom.gd` `_draw_bj_card` 改为贴图绘制（wire `AS`/`10H`/`JOKER`/`??` → `card_<suit>_<rank>.png` / `card_back.png`，contain-fit 保持 64×64 原比例，`scale_x<1` 翻牌动画兼容），21 点与五对共用；加载失败回退原代码绘制。
- 规则说明弹窗：`_rules_btn` 从仅军棋扩展到所有棋桌；`_rules_text_for()` 按游戏给出 zh/en 规则摘要（五子棋/跳棋/21 点/五对/军棋），`_toggle_junqi_rules` 泛化 + `_apply_rules_text()` 随当前桌刷新。
- 修复：`_card_tex_path` 字典 `.get()` 返回 Variant 触发「推断为 Variant」编译门 → 显式 `str()` 强转。
- 冒烟：`wudui_smoke.py` 修复红色过牌偶发 flake（`pass_turn` 先抓牌后验弃牌，预选散牌可能被补牌配成对 → `WUDUI_BAD_DISCARD`；改为拒着后 `chess_sit` 刷新手牌重选，8 次重试）；wudui/blackjack/ws 三回归 + 6 场景编译门全绿。

## 2026-08-06 · 五对（WuDui）双人纸牌桌 + 棋牌室扩容

- 棋牌室扩容：地板 32×22、墙 ±16/±11；新增 Table5（五子棋 丙桌）与 Table6（五对 双人桌）；契约 `demo_chessroom.json` bounds 扩到 half_x=16 / half_y=11，walkable ±15.5/±10.5。
- 新游戏「五对」（`gateway/wudui.py` 权威裁判）：54 张（含双王），双方各 10 张、先手 11 张；先手必弃散牌（剩牌恰好 5 对 = 天和胜出）；后手可吃牌（凑对后弃散牌）或过牌（抓 1 再弃 1）；任一方五对即胜，可认输；`chess_resign` 双人分支（离座判负 + 认输）皆接入。
- 新 cmd：`card_discard` / `card_eat` / `card_pass`；错座位/错回合回 `WUDUI_NOT_TURN` 拒着（`chess_reject`），非法牌回 `WUDUI_BAD_CARD` / `WUDUI_NOT_UNMATCHED` 等错误码。
- 客户端 `chessroom.gd`：五对面板（明牌双人、弃牌堆、回合/对数提示、选牌高亮）+ 出牌/吃牌/过牌按钮；房间标签更新为「甲乙丙五子棋 / 丁跳棋 / 戊军棋 / 己五对」。
- 冒烟：`scripts/wudui_smoke.py`（双人 sit→deal 11/10→弃→过→错回合拒着→认输→redeal 全链断言）；`ws_smoke` / `blackjack_smoke` 回归绿；`demo_chessroom` 场景编译门绿。

## 2026-08-06 · 21 点（Blackjack）接入棋牌室 · 替换乙桌五子棋

- Gateway `gateway/blackjack.py`：4 副牌靴、单人 vs 庄家（17 停）、soft ace、黑杰克/爆牌/平局判定；新 cmd `card_hit` / `card_stand`（`chess_reset` 重发一局）；`chess_table_update.detail` 带 `player_cards`/`dealer_cards`/点数/`phase`/`result`（庄家暗牌 `??` 结算前隐藏）。
- 契约：`demo_chessroom.json` `table_2` 改为 `game=blackjack`（乙桌 21 点）；坐庄单座（第二人旁观/不占座）。
- 客户端：代码绘制牌面（♠♥♦♣ Unicode + 点数），发牌滑入动画 + 庄家翻牌 flip 动画（`_bj_anims`）；要牌/停牌/再来一局按钮（H/S 快捷键）；庄家/玩家点数常显；结果横幅（Blackjack/赢/输/平）。
- 冒烟：`scripts/blackjack_smoke.py`（坐下→发牌→hit→stand→庄家≥17 或爆→结算断言）；`chessroom_smoke` / `ws_smoke` 回归绿。
- 素材：先代码牌面（零依赖）；Kenney Playing Cards 包替换留待下一刀（CC0，需联网下载 + `ASSETS.md` 台账）。

## 2026-08-06 · 21 点修复：桌签/提示文案 + Web 端 H/S 快捷键

- `TABLE_META` 兜底桌签与房间提示语改为「乙桌：21 点」（此前仍写五子棋乙桌）。
- Web 端 `_on_web_key_event` 补 `KeyH`/`KeyS`（此前 H/S 仅桌面 `_unhandled_input` 生效，Web 被 `_is_web` 短路）。

## 2026-08-06 · 21 点卡死修复：status 与 phase 同步

- **卡死根因**：`chess_sit`/`chess_reset` 发牌后只更新 `board.phase`，`table.status` 停在 `idle` → 客户端按 `status=="playing"` 显隐要牌/停牌按钮，按钮永不出现（首手/重开一局均卡死）。
- 修复：gateway 发牌后同步 `table.status` 到 `playing|finished`；客户端 `_refresh_board_from_authority` 对 blackjack 以 `phase` 为权威兜底。
- `blackjack_smoke` 增补：坐下→首手自然 Blackjack 容错、结算→`chess_reset` 重开→继续玩全流程断言；3 轮连跑 + 全套回归（chessroom/ws/hub_chat/duel）+ 6 场景编译门全绿。

## 2026-08-05 · 热修：mujoco 模式 join hw 契约崩连

- 线上 playground gateway 跑 `--physics mujoco`；join `demo_arm_lab` 时 `_ensure_mj_model` 试图编译 `hw/so101`（非 MJCF）→ handler 异常断连。
- 修复：hw_machine 契约与 Hub 同待遇——跳过 MuJoCo 编译，直接走 HwArmMech/HwBridgeMech。
- 验证：本地 mujoco 模式 hw_fake_smoke 全绿（hello/scene/chase/clamp）。

## 2026-08-05 · HW-2.5a：bridge 激活改 env 驱动 + playground 发版

- 重构：`MW_HW_BRIDGE_URL` 存在即在任意 physics 模式激活 bridge client；`hw_machine` 契约自动路由（有链走真桥，无链回退仿真臂）；`--physics hw_fake/hw_bridge` 保留为显式选择。
- 效果：playground 不设 env → `?level=demo_arm_lab` 公网仿真臂即玩；设 env → 同源切真臂 B，无需改代码/重启策略。
- 回归：默认 fake 模式 hw_fake_smoke / hw_bridge_smoke / ws_smoke 三绿。

## 2026-08-05 · HW-2：真机桥翻译层（hw_bridge）

- `gateway/hw_bridge_client.py`：连仓外 arm-bridge（env `MW_HW_BRIDGE_URL`/`MW_HW_BRIDGE_TOKEN`，ADR-004 零凭证入库）；hello 软限位建表；rad↔counts 线性映射（pan 翻转）；outbox fire-and-forget + 断线指数重连。
- `HwBridgeMech` + `--physics hw_bridge`：`joint_targets` 转发真桥；state 镜像 bridge present（权威在边缘）；链路断开报 `HW_LINK_DOWN`。
- 冒烟 `scripts/hw_bridge_smoke.py`（内嵌假桥全闭环）：UNKNOWN_JOINT / rad→counts 回环 pan=0.499 / 软限位 clamp 1.92 全过；hw_fake 回归绿。

## 2026-08-05 · HW-1：桌面键鼠臂遥操前端（demo_arm_lab）

- 新场景 `demo_arm_lab.tscn` + 自包含 `arm_lab.gd`：1-6 选关节、,/. 或 ←/→ 调目标（20 Hz `joint_targets`）、H 回 HOME、左键点台面 shoulder_pan 对准；HUD ASCII 关节条 present→target。
- 程序化 3 段臂 + 夹爪视觉（近似 FK，权威仍在 gateway）；Web 走 `MWWebInput` 键桥。

## 2026-08-05 · HW-0：hw_fake 真机仿真后端 + ADR-004

- [ADR-004](adr/004-hw-real-robot-boundary.md) 冻结边界：黑盒外部桥、本仓零私有资产、安全归边缘、无真机可开发。
- `--physics hw_fake`：`gateway/hw_machines.py` SO-101 公开参数表（6 关节弧度限位/HOME/速率）+ `HwArmMech`（joint_targets 限速追踪 + 软限位 clamp + 未知关节拒绝）；契约 `demo_arm_lab`。
- 冒烟 `scripts/hw_fake_smoke.py`：HOME 位姿 / 追踪 / clamp / UNKNOWN_JOINT 全过；既有 `ws_smoke`（fake）无回归。

## 2026-08-05 · 真机接入计划入库（docs/28）+ Next 候选改向

- [28-hw-real-robot-plan.md](28-hw-real-robot-plan.md)：桌面键鼠遥操真机（SO-101/JetRover→G1/Go），**黑盒对接仓外闭源 arm-bridge**；协议/前端/录制在本仓，凭证与实现永不入库。
- Next 候选改：**HW-0–HW-2**（可开）/ E6–E7（blocked 待 PMS）；XR-1.6/XR-2 划线——Pico 线归仓外 mine-world-arm（真机臂遥操+视频已通）。

## 2026-08-05 · E8 参观者壳侧栏文档

- `#mw-visitor-shell` 加右侧 doc 面板（280px）：标题 + 展柜 lore + `space_id`；空则自动隐藏；关壳清空。
- Hub 进展柜时把 `lore_zh`/`lore_en` 作为 `doc` 传给 `MW_OPEN_VISITOR_SHELL`；E8 薄壳「中央 iframe + 侧栏文档 + 关闭」三件套补齐。

## 2026-08-02 · B3 旁观态复位热修

- `_leave_room` 复位 `session.spectate`：duel 旁观者再 join 不再卡「joined 但不在 members」僵尸态；`duel_smoke` 回归断言。
- 清理死常量 `DUEL_MAX_RACERS`（超员判断实际走 `free_spawn_id`）。

## 2026-07-31 · F6 假物理车轮回归修复 + 棋室聊天

- FakeMech 补 F6 运动学车轮导出（`left_wheel_joint`/`right_wheel_joint`，半径 0.15 轮距 1.0 对齐 diffbot_planar.xml）；`ws_smoke` 恢复 `smoke OK`。
- 棋室复用 hub/city/race 同一 DOM 聊天栏与 `cmd.action=chat`：进房开 `MW_SET_ROOM_CHAT`，头顶气泡走 avatar `show_chat`，桌面端 print 兜底。

## 2026-07-31 · demo_workshop 物理边界 50×50 m

- `examples/contracts/demo_workshop.json` 四面墙由约 30×24 扩到 **50×50**（x∈[0,50]，y∈[-25,25]），方便 XR InteriorGS 漫游；出生点/道具位未改。

## 2026-07-30 · XR 傀儡验收 + JihuLab 入库

- Quaternius 机甲：`SkeletonUtils.clone` + 去 Hand*，整机跟 `base_pose`（不再漂臂/蓝盒默认）。
- 并列仓正式远程：JihuLab `databall-group/infra/mine-world-xr`；playground `MW_XR_BUILD=20260730-110053`。
- 文档澄清：XR 桌面 Panda 臂仍是视觉皮；MuJoCo 臂/爪仅 workshop DiffBot（XR-1.6 下一步）。见 [27](27-pico-webxr.md)。

## 2026-07-30 · B3 房间模式 solo|duel|shared_ffa

- join `extensions.mw.mode`（schema 枚举 + `examples/ws/join_race_duel.json`，非法值拒绝）；公共 `race` 房固定 `shared_ffa`，私房默认 `solo`。
- Gateway：`solo` 永不 `duel_result`；`duel` 恰好 2 手武装、超员转旁观（同场景、无机位、不录 session）；`shared_ffa` 保持原行为；`duel_result.detail.mode` 回传。
- 客户端：`?mode=duel` 进私房对决，HUD room 行显示 单/双/混；旁观者不建傀儡不抢控制。
- 验收：`duel_smoke` 按三模式 + 旁观断言；jsonschema 校验通过；playground 发版待下一刀。

## 2026-07-29 · 聊天扩到 city/race + 气泡对比度

- 气泡 one-shot：白字 + 深色底板/描边，避免跟 accent / 亮背景糊在一起。
- `demo_city` / 公共 `demo_race` 复用同一 DOM 聊天栏与 `cmd.action=chat`（棋室后置）。

## 2026-07-29 · Hub 广场聊天（可复用到 city/race）

- `cmd.action=chat` → 同房广播 `event_type=chat`（限长 80、冷却 0.75s）；协议不绑 Hub。
- Hub：左下聊天栏 + 头顶气泡；Web 输入时不抢 WASD。

## 2026-07-29 · Blocky 全套 a–r + 四角石像

- Kenney Blocky 2.0 全套 18 皮入库；profile `skin` / gateway 透传扩到 `a..r`（`skin_pool=18` 时按 id 重哈希一次）。
- 大厅四角各一座 Poly Haven `gothic_statue`（同 mesh 复用、约 0.72 倍）；SE 略内收避开电梯。

## 2026-07-29 · Hub 傀儡按 profile 分配 Blocky 造型

- 首次进母港按 profile id 哈希稳定分配 `skin`（Kenney Blocky）；join / state 透传，他人可见。
- 避免原先全员默认 accent 蓝 → 同一套皮。

## 2026-07-29 · Hub L2 栏杆缺口可跳下

- 观景廊开敞边（电梯西侧）栏杆留缺口；走出 `bounds.floor2_drop_gap` → `hub_floor=1` 落地（视觉下落）。
- 契约 `demo_hub.json` + gateway clamp 降级；`hub_dress` / `hub.gd` / `avatar_puppet`。

## 2026-07-28 · Pico WebXR 计划建议书

- 产品拍板方向入库：[27-pico-webxr.md](27-pico-webxr.md)——Pico 以 WebXR 为主路径，同协议接 MineWorld Gateway；3DGS/视频为皮肤；UE 非默认。下一刀建议 XR-0→XR-1。
- 并列仓 `mine-world-xr` 已初始化 XR-0（Vite + Three.js + Gateway WS stub）；XR-1 同网遥操已通。
- Playground 双前台：`/` Godot Web · `/xr/` WebXR（`MW_XR_BUILD=20260728-123716`，共用 `wss://…/ws`）。
- **XR-1.5**：摇杆轴向可切换、HUD（房间/控权/延迟/链路）、掉线自动重连、CC0 类人 GLB 傀儡；Portal/Hub 入口链到 `/xr/`。

## 2026-07-27 · 军棋交战后双方互等

- **现象**：军长吃工兵等交战后，双方都显示在等对方。
- **根因**：客户端用缓存 `_session_id` / 空 sid 匹配座位 → 双方误判成同一阵营；交战后文案「等待红方」叠在碰撞行上易误读；click 未与 phase 对齐。
- **修复**：`turn_sid` 权威行棋人；`ws.session_id` 同步；碰撞文案中文 + 行棋提示置底；广播 `to_detail` 单人失败不拖死全桌。
- Deployed `MW_BUILD=20260727-175217`。

## 2026-07-27 · 军棋 PvP：单播迷雾 + 拒着回传

- **现象**：人对人走子后双方都显示「等待对手」、棋盘看似不动（非法着法静默丢弃 + 同包双视图/明文盘易搅乱客户端状态）。
- **Gateway**：`chess_table_update` 按 session 单播个人迷雾；去掉 `junqi_open`；非法走子/布阵回 `chess_reject`。
- **客户端**：拒着提示；走子等权威回包再清选中；等待文案区分黑/红方。
- **冒烟**：`chessroom_smoke` 覆盖走子+AI 回手；本地双端 PvP 走子后黑等/红可走。
- Deployed `MW_BUILD=20260727-172138`。

## 2026-07-27 · B2 收口 · Next→B3

- **事实**：B2 薄 1v1（`duel_result` + 录制 + HUD + B2.5 AI 陪练）早已入库；`09`/`AGENTS` 仍写 Next=B2 为文档漂移。
- **收口**：B2 勾 Done；**Next = B3**（`solo|duel|shared_ffa` 显式分流）— 可执行四步见 [09](09-todo.md)「B3 可执行切片」。推箱对决不纳入。

## 2026-07-27 · Chess-FX Phase 2 军棋终局动画

- **军棋终局明牌**：finished 时触发 `_trigger_junqi_reveal`，所有棋子按曼哈顿距离波次翻转（stagger delay 0.05s），胜方棋子金色脉冲 + win 音效。
- **翻转动画**：`_draw_junqi_tile` 增加 `alpha`/`flip_x` 参数；flip_x 余弦插值模拟 Y 轴卡牌翻转（0→1→0→1），<0.15 时隐藏文字保真实感。
- **棋子动画基础设施**：`_tick_piece_anims` 支持负 t（stagger 延迟）；`_anim_scale`/`_anim_alpha`/`_anim_y_offset` 对负 t 返回安全值；新增 `flip` 动画类型。
- Deployed `MW_BUILD=20260727-081422`。


---

## 2026-07-26 · 军棋山界视觉

- 两半场中间留山界带；列 1/3 画圆形「山界」，列 0/2/4 为前线通道；铁路改虚线。

## 2026-07-26 · 军棋盘横置

- 12×5 改为横向：行沿 X、列沿 Y；本方半场在左，更适合宽屏。

## 2026-07-26 · 军棋面板飞出屏幕

- **根因**：`CanvasLayer` 下直接 `PRESET_CENTER` + 负 position，Web 视口锚点基准错误。
- **修复**：全屏 Control 根节点；面板 `TOP_LEFT` + 视口绝对居中；规则条文不再写死 520 宽。

## 2026-07-26 · 棋牌室空位傀儡闪现

- **根因**：`chessroom._on_state` 把缺 `occupied` 当已占用，且 delta 未带上的实体整帧隐藏 → 空槽/远端闪现。
- **修复**：对齐 Hub（默认未占用）；空槽不生成傀儡；服务端显式 `occupied=false`；delta 漏帧不再误隐藏。

## 2026-07-26 · 三桌实体棋盘观感

- **统一**：木框 + 木纹面；视口自适应防溢出。
- **五子棋**：暖色围棋盘 + 黑白亮面棋子。
- **跳棋**：木格盘 + 红/蓝塑胶兵；阵营角染色。
- **军棋**：沿用木框绿盘与长方块棋子，本方在下。

## 2026-07-26 · 军棋盘观感 + 防溢出

- **溢出**：军棋盘按视口自适应高度，面板居中裁切；状态栏不再顶出屏幕外。
- **观感**：木框绿盘、行营圆/大本营金格、铁路示意线；棋子改为带阴影的长方块（仿实体塑胶子）；本方半场翻到屏幕下方。

## 2026-07-26 · 军棋产品拍板 + 布阵确认 / 认输举手 / 离座判负

- **定位**：先人机/内测；公网 PvP 等 Chess-P4 迷雾单播。
- **先手**：先入座（黑席）先走；雷与旗 **仅禁同格**；第二人入座 reset 接受。
- **布阵**：`junqi_layout` 支持 `ready=false` 草稿；随机后可拖换手调，再「确认布阵」。
- **操作**：`chess_resign` 认输；`chess_hand` 举手；对局中离座 → 判负。

## 2026-07-26 · 军棋 SSOT + 可玩桌 + 规则显隐

- **SSOT**：[`docs/26-junqi-ssot.md`](26-junqi-ssot.md) + [`assets/junqi-board-12x5.png`](assets/junqi-board-12x5.png)（12×5 附图拓扑 · 任意子扛旗 · 无需清雷 · Frozen）。
- **Gateway**：`gateway/junqi.py` 权威裁判；桌面 FSM 接 `junqi_layout`（含 `auto` 一键布阵）/ `chess_move`；人机时黑方布阵后自动补红方阵；先手 = 先入座黑方。
- **客户端**：丁桌可玩（12×5 雾盘、「随机布阵」、选子走子）；**规则说明**按钮显示/隐藏 SSOT 摘要；桌名/壳层 tips 去掉 WIP。
- **契约 / 冒烟**：`demo_chessroom` `table_4` 标题「军棋」；`chessroom_smoke` 覆盖军棋入座+布阵+透视计数。
- **已知债（未拦人机试玩）**：`chess_table_update` 仍同包广播 `junqi_open` / 全员 `junqi_views` → **PvP 暗棋可被旁路窥视**；断线/认输未按 SSOT 判负；仅随机布阵、AI 随机合法步。

## 2026-07-26 · 棋牌室对齐传送门（presence + 薄桌面权威）

- **动机**：一期纯离线与 Hub/Workshop/City/Race 分叉，导致 WASD 等反复「修键桥无效」。改为与其他门同构。
- **契约**：`examples/contracts/demo_chessroom.json` — `extensions.mw.mode=hub`、room 默认 `chess`、max 8、24×18 可行走 AABB、4 桌 id。
- **Gateway**：`ChessTable` FSM（`chess_sit` / `leave` / `place` / `reset`）+ `chess_table_update` 广播；规则/AI 在 `gateway/gomoku.py`（对齐 `gomoku.gd`）。单人坐 → `vs_ai`；第二人入座 → PvP。
- **客户端**：`chessroom.gd` 接 `WsClient` join/state/cmd；棋盘只渲染权威快照；Hub 过门设 `?room=chess`，Esc 清 room 回母港；Hub `_resolve_room_id` 忽略 play rooms（含 race/chess）。
- **样例 / 冒烟**：`examples/ws/cmd_chess_sit.json`、`event-chess-table-update.json`；`scripts/chessroom_smoke.py`。

## 2026-07-26 · 棋牌室一期（门 P + 五子棋人机）

- **场景**：`demo_chessroom.tscn` 封闭暖色房间（24×18m）——4 张棋桌 × 2 椅，走近按 F 落座打开棋盘面板，F/Esc 起身，Esc 回大厅；一期曾**纯离线**（已由上条对齐为在线 presence）。
- **玩法**：五子棋——`gomoku.gd`（15×15）；对局权威现迁 Gateway（见上条）。
- **Hub**：东墙新门 `DoorChess`（22.5, -14，紫色自发光，标签「P 棋牌室」），`hub.gd` 接线 armed/near/context/过场标签；提示行加 `P Chess`。
- **顺手修复**：RMB 转头灵敏度（衰减 30→8/s、增益 0.4→0.6——慢速拖动不再死于 cmd tick 间隔）。
- **验证**：lint 0 findings；boot 检查扩至 5 场景全 BOOT OK。
- **热修**（同日验收反馈）：① CameraRig 子节点缺 `Camera3D`（`camera==null` → 全黑；headless 崩在渲染前，boot 检查未能发现）；② 场景换 `BG_COLOR` 纯色背景去 ProceduralSky；③ 补 `MW_SET_SHELL_UI(true,false,true)` 切换 DOM 壳层；④ 门 P transform 旋转 90° 贴合东墙。**教训**：新建 3D 场景必须查 boot log 的 `Node not found`，而非只看 SCRIPT ERROR 计数。
- **重构 MWWebInput**（同日）：MWWebInput autoload 单例——DOM 监听器一次安装跨场景持久化；is_pressed/web_key_event 供三场景同源引用。hub.gd 全切 MWWebInput.is_pressed()，on_dom_key_event/sync_mw_keys/web_key 全删除；chessroom 不再自建键桥副本。
- **main.gd 完成**（07-27）：最后一处 DOM 键桥替换——T/R/Space/Escape 走 _on_main_key_event；五子棋/跳棋/军棋 UI 修正（横置/山界/瓦片/居中）。
- **根因热修 · 棋牌室 WASD 无效**（同日）：多次改键桥无效——真因是 `avatar_puppet._process` 在 `_has_state==false` 时直接 return，而棋牌室纯离线**从不** `push_state`，故 `local_predict`/`set_local_cmd` 永不积分。修复：离线 `local_predict` 自举 pose 锚点、设 `_authority_live`，无权威流时跳过 soft-pull（否则会每帧拽回出生点把位移抵消）。**随后已对齐在线 presence**，默认路径走 `push_state`。

## 2026-07-26 · 棋牌室多桌 + 跳棋 + 壳层说明

- **壳层**：进棋牌室用 `MW_SET_HUD` 覆盖母港 tips →「棋牌室」操作说明（折叠标题同步）。
- **四桌**：契约 `chess_tables` 对象——甲/乙五子棋、丙跳棋（8×8 Halma）、丁军棋 stub；桌面 Label3D 分色命名。
- **跳棋**：`gateway/checkers.py` + `chess_move`；选子再落点（邻步/跳）；人机 AI；军棋仅预览文案。
- **胜负 UX**：Noto 字体 + 高亮 + 自动起身（既有）。

## 2026-07-24 · Hub WoW 式右键转头（turn-drive）

- **操控**：大厅右键按住 = 身体随鼠标水平转动（WoW 同款）；左键窥视松手回中不变。按右键瞬间身体对齐当前视线、相机回正肩后。
- **实现**：`camera_rig` 新增 `turn_drive_enabled`（默认关，竞速/关卡保持旧 RMB sticky 语义）+ `turn_drag_started`/`turn_dragged(dx)` 信号 + `get_look_yaw_offset()/snap_look_behind()`；RMB 拖动走**既有** `_on_mouse_look` 事件路径（desktop/Web 同一路），水平 delta 直接 emit → hub 换算 `yaw_rate = clamp(-dx·0.4, ±TURN_SPEED)` 每帧衰减、20Hz cmd tick 注入 → 权威 FakeMech 转向，远端互见；RMB 拖动只控俯仰，不再攒 `_chase_yaw`（松手无跳变）。**教训**：首版另起 DOM `mousemove` 桥属过度设计——RMB 事件本就到达 engine，绕行引入新故障点致 Web 失效，已重构为信号直挂（净 -30 行）。
- **边界**：PAN（中键/左右同按）优先于转头；QE 键盘转向与右键并存时鼠标优先；orbit 模式 RMB 维持旧 sticky。`avatar_puppet` 增 `get_yaw()`。
- **验证**：`gdscript_lint` 0 findings；`check_scenes_boot.sh` 四场景 BOOT OK。
- **工具**：`check_scenes_boot.sh` 改 `kill -9` 收尾（SIGTERM 走优雅退出会额外触发一次 Metal 析构崩溃）。已知：本机 macOS 26 + Godot 4.7.1 无头进程运行数秒后自行 Abort trap 6（dummy/opengl3 驱动均复现，与项目代码无关），启动日志在崩溃前已落盘，BOOT 判定不受影响；崩溃弹窗属系统级 CrashReporter，需 `defaults write com.apple.CrashReporter DialogType none` 才可关闭。

## 2026-07-23 · Hub L2 空气墙 + 空格跳跃互见（playground）

- **L2 clamp**：`demo_hub` `bounds.floor2_walkable`；`hub_floor==2` 时 FakeMech 钳在观景廊甲板。
- **空格跳跃**：Hub 专用（同 F）；本机抛物线；velocity `extensions.mw.hop_y` → state → 远端抬高。
- 冒烟：`scripts/h_bounds_e3b_smoke.py`（floor2 投影）、`scripts/hub_floor_smoke.py`（floor+hop）。
- 样例：`examples/ws/cmd_set_hub_floor.json`、`examples/ws/cmd_hub_hop_y.json`。
- 现网：`MW_BUILD=20260723-181418`（强刷）。

## 2026-07-23 · Hub 电梯楼层多人同步（hub_floor）

- 根因：L2 乘梯只改本机 `height_offset`，FakeMech 权威仍是平面 → 自己悬空、远端仍见一楼。
- 协议：`cmd action=set_hub_floor`（`floor` 1|2）；state `extensions.mw.hub_floor`；
  delta quantize 含 floor（+ occupied），换层立即进包。
- 客户端：乘梯到达发 floor；远端 puppet 读 floor → `HUB_FLOOR2_Y` 抬高。

## 2026-07-23 · 修复 demo_race 幽灵车 return 跳过网关连接（油门无反应）

- 根因：`main.gd` `_ready` 在 `MWGhost.fetch_best()` 后误 `return`，未执行
  `ws.connect_to_gateway()` → 无 session / control，车停在本地出生点，按 W 无效；
  HUD 仍残留母港 tip。
- 修复：幽灵车异步拉取后继续连网关（viewer-only，不阻断进房）。

## 2026-07-23 · 修复进赛车场秒收 FAIL（time_limit 用房间年龄）

- 症状：刚进 R 赛车场、车未动即弹 `FAIL · obj_race_finish`。
- 根因：`evaluate_time_limit`（A1）用 `room.tick × DT`（房间年龄）对比 400s 限时；
  B2.5 bot 常驻后房间已运行十余分钟，新加入者瞬间「超龄」被判失败。
  积分时长同源问题一并修。
- 修复：Session 新增 `join_tick`，限时与积分时长均按「本人加入后经过的 sim 时间」计；
  join_tick=-1 的旧会话保持房间年龄语义。
- 单测：老房间新加入不判负 / 本人超 400s 判负 / 旧语义兼容，三断言过；duel_smoke 回归 OK。

## 2026-07-23 · 修复 B2.5 后访客出生在 600m 外停车场

- 症状：进 R 赛车场出生在 `(434,-420)` 黑虚空，无赛道无地面。
- 根因：空闲车位离房时统一「停放」到 `(420,420)` 场外点（既有设计，防空车挡道）；
  而加入复位仅当「房间空」才执行——B2.5 AI bot 常驻后房间永远不空，之后每个加入者
  都跳过复位、领到停放车。
- 修复：free_spawn_id 返回的车位必然无人认领，加入复位改为无条件回 contract 起跑位。
- E2E：bot 先占房 → 第二加入者精确落位 contract 网格 spawn（-4.3,-68.2），
  bot 继续在赛（9→43m 推进）；duel_smoke 回归 OK。

## 2026-07-23 · 修复进关过场双锁死（遮罩卡住后所有门进不去）

- 根因：`MWTransition._busy` 依赖新场景 `notify_arrived()` 清锁；若切场景失败/未到达，
  `_busy` 永久 true → 后续 `go()` 静默 no-op；Hub 侧 `_entering_door` 先置位再 `go()`，
  失败后门锁死，`#mw-transition.show` 黑遮罩不撤。
- 修复：卡住的 `_busy` 进门前强制清遮罩；`change_scene` 失败 / 2.5s 看门狗兜底；
  Hub 仅在 `go()` 成功后再锁门并关 WS。

## 2026-07-23 · 事故：main.gd 编译错（触发源，已修复+门禁）

- 事故：B2 duel 提交（`20c40aa`）漏提 `var _race_fx` 声明（顶掉）与 MWHud 5 参签名，
  main.gd 编译失败 → 所有玩法场景 `_ready` 不执行 → `notify_arrived()` 缺失 →
  触发上条双锁死（线上 ~3h，12:33–15:48）。检查盲区：Web 导出 + lint 均不抓
  跨文件编译错。
- 修复（`b8930ad`）：补回两处；四场景 dummy 驱动真启动验证零 SCRIPT ERROR。
- 门禁：`scripts/check_scenes_boot.sh`（四场景启动编译检查）接入发版步骤 1.6，
  失败即中止发版——此类事故不可再上线。

## 2026-07-23 · B2.5 AI 常驻陪练（resident bot）

- 痛点：1v1 对决需双人同时在线，低流量下访客永远体验不到。解法：ai_driver 常驻公共
  赛车房 `race`，任何单人访客进门即有活对手——duel 自动武装、WIN/LOSE 横幅、
  进度差 HUD 全部立即可用，人机对决数据继续喂飞轮（T4.5 人机同协议）。
- `ai_driver.py`：`--room`（共享房）/`--name`/`--bot`/`--forever`（圈内复位 + 掉线
  3s 重连驻留循环）；`--bot` 经 join extensions.mw.profile 标记，网关据此跳过其录制
  （`profile.bot` → 不建 SessionRecorder，防 AI 圈淹没会话索引与 best_lap 幽灵车源）。
- 运维：`scripts/mineworld-bot.service`（Restart=always，连内网 gateway）；
  安装步骤见 docs/ops.local.md（私有）。
- 验证：fake 网关共享房加入（room=race max_members=6）+ 录制零新增；mujoco 网关
  15s 试驾 PASS（11–12 m/s）。

## 2026-07-23 · B2 薄 1v1 竞速对决（duel_result）

- 网关：demo_race 房间 ≥2 名受控玩家时自动武装对决；首位过线（`obj_race_finish`）者
  触发 `duel_result` 事件（winner/圈时/参赛者/轮次），胜者当帧、其余成员下一帧入流，
  经既有 `recorder.write_frame(events=…)` 落盘双方录制；全员完赛后自动重新武装下一轮。
  单人刷圈不触发；非 race 关卡免疫。事件样例 `examples/ws/event-duel-result.json`。
- 客户端：事件 → 大字横幅 YOU WIN / YOU LOSE（`MWHud.show_mission_result` 新增
  title_override）+ 状态行；HUD 新增「对决 领先/落后 Nm」——纯客户端中线投影
  （race_layout.json 累计里程 + 每实体回绕提示的最短符号差），零 schema 变更。
- 验证：`scripts/duel_smoke.py` 进程内 5 断言（settle/pending/re-arm/单人守卫/异关卡），
  顺手抓到并修复 `logger`→`LOG` 引用错误；`ws_smoke_test`（mujoco 标准路径）OK；
  lint 0；Web 导出零错误。

## 2026-07-23 · 修复 Hub 角色「滑行不动四肢」

- 症状：玩家行走时角色常原地平滑滑行、四肢不动。
- 根因（双因）：① `SPEED_SPRINT=2.4` 低于大厅走速 2.8 m/s → 常态行走被判为 sprint，
  walk 循环实际不可达；② 运动剪辑循环依赖导入 loop 标志，若未循环则 0.5–0.67s 后
  定格末帧（静态目标覆盖 + cross-fade 0.15s），视觉上即永久滑行。
- 修复：`SPEED_SPRINT` 提至 3.2（走→walk、仅预测过冲瞬时触发 sprint）；
  `_ensure_skin` 对 idle/walk/sprint 强制 `LOOP_LINEAR`；`_play_anim` 守卫加
  `is_playing()`——剪辑播完自动重播，对任何循环失效自愈。

## 2026-07-23 · 修复 delta 压缩下 Hub 小地图丢静止玩家

- 症状：state delta 压缩（`6a4753f`）后，静止玩家只随 1.25s 关键帧出现；Hub `_on_state`
  每帧用当前 payload 重建小地图 actors → 静止者圆点消失、自己坐标显示退回「独自」。
- 修复：`_on_state` 改为维护 `_map_actors` 缓存（可见即更新、槽位不可见即剔除），
  minimap/坐标/DOM 地图一律从缓存重建。评审代理发现，约 +14/-3 行。

## 2026-07-23 · 修复大厅傀儡「停止后原地钟摆」

- 症状：键盘停止输入后，自己的 avatar 以 ~1.25s 周期前后/左右往复摆动（横移停→横摆，转身停→斜摆）。
- 根因（双因叠加）：
  1. `avatar_puppet._process` 的 `alpha>1` 外推分支无「流静止」保护——delta 压缩（`6a4753f`）
     把静止实体剔出 20Hz 流后，自己只剩 1.25s 关键帧；外推所用 `(next-prev)/span` 实为软修正
     残差（垃圾速度），目标点被推到权威位姿另一侧 → 8/s 拉扯 → 永久钟摆（探针实证网关权威
     位姿静止零抖动，振幅模拟 0.64m 与观感一致）。
  2. Hub 进出门 1.5s `door_grace` 冻结 cmd 发送但不清 `set_local_cmd` 缓存——预测引擎吃陈旧
     非零 cmd 继续积分（次级因，顺修）。
- 修复：外推限定最后状态后 0.45s 窗口（`EXTRAP_HOLD_S`），超时或 local_predict 一律锚定最后
  权威位姿；grace 期同步清零预测缓存。零 cmd 行为不变，remote 短外推平滑保留。
- 验证：限幅循环模拟摆幅 0.635m→0.028m（-96%）；WS 探针复现权威流形态；lint + Web 导出零错误。

## 2026-07-23 · main.gd 结构还债第一刀（mw/ 模块目录）

- 新增 `godot/spike/scripts/mw/` 模块目录，从 1500 行 god-object 抽出自包含逻辑：
  - `race_fx.gd`（`MWRaceFX`）：胎痕 + 刹车烟尘，viewer-only，main.gd 1549→1482。
  - `drive_input.gd`（`MWDriveInput`）：油门/刹车/转向模拟通道纯逻辑（含手柄轴优先、
    倒车保护、自动回正），main.gd 1482→1437；行为与原实现逐行等价。
  - `ghost_car.gd`（`MWGhost`）：幽灵车取榜/拉帧/傀儡/循环回放全链路，
    经 `loaded` 信号回传状态，main.gd 1437→1319。
- 每刀均过 `gdscript_lint` + Web 导出零错误后入库；已发版 playground 验证。
- 续刀已完成：`MWGhost`（幽灵车）、`MWHud`（横幅/提示音/ASCII 条/Web 推送）、
  `MWReplay`（离线回放，Callable 回 level）——main.gd 1549→1029 行（-34%）。
- 剩余：net 消息处理层（最纠缠，边界待文档化）；hub.gd 按自身域拆门系统/NPC/提示。

## 2026-07-23 · AI 车手 v0（pure pursuit，无学习）

- `scripts/ai_driver.py`：以普通 WS 客户端身份接入（与人同一协议，T4.5 人机可互换的实证），
  从 state 读自身位姿，沿 `race_layout.json` 中线做纯追踪转向，按前方曲率调速。
- 完赛判定为「缠绕感知累计进度 ≥95%」，杜绝假完赛；实测整圈 63.3s，全程录制入库。
- 用途：回放/幽灵车数据的机器来源、BC 数据飞轮的第二供给方、后续 AI 教练/对手的基座。

## 2026-07-22 · 修复 Web 赛车场黑场（race_layout.json 未打包）

- 根因：Web 导出默认只收「已导入资源」，`data/*.json` 非导入文件未进 pck；
  `race_dress` 布局缺失直接 return → 地面/围栏/树全部未建，画面只剩车和天空。
- 修复：导出预设 `include_filter="data/*.json"`；`race_dress` 增加无布局兜底
  （大草坪地垫，不再黑场）。需重新导出部署 playground 生效。
- 注：本地 Godot 4.7.1 无头启动在 Metal shader 转换阶段崩溃（exit 134），
  `--rendering-driver opengl3` 同样崩溃——属引擎本地问题，与 GDScript 无关；
  脚本语法以日志中无 SCRIPT ERROR / Parse Error 判读。


## 2026-07-22 · demo_race 驾驶模型重构 R1–R5

- R1 协议：`control_mode: "drive"`（throttle/brake/steer/handbrake 模拟量），网关 Ackermann 映射按契约 `extensions.mw.drive` 参数执行；`velocity` 模式零影响。
- R2 输入：键盘按住渐进给油（2.5/s）、松开衰减、转向按住渐进打死（3/s）松手自动回正（5/s）；X 倒车低速保护；手柄 axis 原生接入。
- R3 HUD：车速 km/h、油门/刹车条、转向指示、cp 分段计时；相机 FOV 随速度扩张（55→67°）+ 弹性跟随滞后。
- R4 特效：重刹/高速急转胎痕（FIFO 220 条）+ 刹车烟尘粒子；race 插值延迟 50→30ms。全部 viewer-only。
- R5 赛道：弯心红白路缘带 + 弯前 50/100/150m 刹车牌（按 centerline 曲率自动布点）。
- 验收：无头 drive 冒烟 PASS（半油门+半转向 3s 位移 8.1m、转向 0.44rad）。
- Playground： · web/gateway active。

## 2026-07-22 · 赛车场环境丰富化（viewer-only）

- 草坪：路缘外侧绿地毯条带沿全圈铺设；绿化带：每 3 个采样点一排修剪绿篱。
- 安全区：弯心出口侧砾石缓冲区（浅色 pad）+ 远端红白糖罐轮胎墙。
- 看台：起终点双侧三层阶梯看台（灰阶台阶 + 彩色观众点）+ billboardLow 背景板。
- 全部由 centerline/curvature 自动布点；不碰 MuJoCo 物理与契约。
- Playground：`MW_BUILD=20260723-001146` · web/gateway active。
- Playground：`MW_BUILD=20260722-223128` · 含 R1–R5 驾驶模型 + 赛道布景 · web/gateway active。

## 2026-07-22 · Hub 门 E/R 分离：竞技场 WIP，赛车场独立

- 门 E「竞技场」改为建设中占位：不再可进入，文案改为机甲格斗（1v1 / 团队对战）规划；F 四态 stub 保留。
- 南翼东侧新立门 R「赛车场」（22.5, 14）→ `demo_race`；门光晕/接近提示/lore 文案同步。
- 背景：竞技场愿景为机甲格斗而非赛车，此前门 E 名不符实。
- Playground： · web/gateway active。

## 2026-07-22 · Hub 假活跃 / 电梯 / 名牌

- 中环 NPC：软会话气泡淡入淡出轮换；巡逻停靠 dwell + 气泡；F 可推进下一句。
- 电梯：候梯琥珀灯 → 到达绿灯 + tip；L2 DOM「本周训练」简报（只读榜），L1 仍用排行榜。
- 名牌：自机常显（含 FP）；远端 8 m 内才显；短码 `昵称 · #ABCD`（大写末 4）。
- Hub 英雄静物：门 A 湾侧 **Gothic Statue**（CC0 · ~1.7 m 石像雕刻 · 2K PBR）；篷布车/小工具箱已撤展。
- Playground： · web/gateway active。

## 2026-07-22 · Hub 门 A/B/E 走近反馈

- 走近约 5.5 m：门标放大、霓虹门光增亮、门上方「▶ 走进进入」；E 门标/霓虹与 A/B 同级。
- 左栏 lore 统一写「走近进入」；进门仍自动（无需按键）。
- Playground：`MW_BUILD=20260722-172033` · web/gateway active。

## 2026-07-22 · demo_race v3：Ackermann（前轮转角 + 后驱）

- 新 MJCF `diffbot_race_v3`：`steer_fl/fr` position + `wheel_rl/rr` motor；不再用差速坦克。
- Gateway：`yaw_rate`→前轮转角（高速略收），`vx`→后轮扭矩；仅 `demo_race` 契约切 v3。
- 手感：静止打方向不原地转；倒车转向有效；轻打是弯不是 180°甩尾。
- 键位：`W` 油门 · `S` 刹车 · `X` 倒车 · `Q/E` 转向。
- 私有/smoke 房只挂 1 台车；共享 `race` 仍 max 6。缓坡暂关（先稳转向）。
- 验收：`ws_smoke_test --level-id demo_race --expect-objective` → smoke OK。
- Playground：`MW_BUILD=20260722-155436` · 双服务 active。

## 2026-07-22 · demo_race v2：freejoint + 4 轮接触

- `diffbot_race_v2`：取消 slide 底盘；`freejoint` + 软悬挂 + 4 球轮 hinge；油门→轮扭矩（差速转向）。
- Gateway：`MujocoMech` 双路径（planar / free）；空闲赛车 paddock 停放，避免堵起跑格。
- 转向：满油门时削减 throttle 以便内侧轮反转（否则 W+Q 几乎不转）。
- 赛道：缓坡台阶（车道内侧）· 护栏低摩擦 · 时限 400 s；Godot Car Kit 仍 viewer-only。
- 验收：`ws_smoke_test --level-id demo_race --expect-objective` → smoke OK。

## 2026-07-22 · demo_race 力驱动加速 + 宽道长回环

- `diffbot_race`：velocity 伺服 → **motor 力/扭矩**；质量+阻尼给出 ~1.5 s 爬到 ~15 m/s。
- 输入：W 油门 / S 刹车倒车 / QE 转向（高速转向衰减）；指令为 [-1,1] throttle。
- 赛道：3 瓣回环 · ~755 m · 车道半宽 8.5 m · 时限 240 s。
- Playground：`MW_BUILD=20260722-142708`。

## 2026-07-22 · demo_race 加大 + 去假起伏

- 圈长 ~430 m · 车道半宽 6 m；去掉 `viewer_heights` 起伏带（平面车不再埋沟）。
- 路面改平坦 asphalt strip；镜头略拉远。
- Playground：`MW_BUILD=20260722-141310`。

## 2026-07-22 · demo_race Kenney Car Kit 车皮

- 子集入库 `godot/spike/assets/kenney_car/`（race / race-future / sedan-sports / hatchback-sports / police / taxi）。
- `mech_puppet.use_kenney_car`：viewer-only 换皮；权威仍 `diffbot_race`；A–F 各一款 + 队标。
- Playground：`MW_BUILD=20260722-140617`。
- 下一刀仍是 **B2 薄 1v1**。

## 2026-07-22 · demo_race Kenney Racing Kit 护栏

- 子集入库 `godot/spike/assets/kenney_racing/`（fenceStraight + jersey curb + 终旗 + 树）。
- `race_dress`：盒状橙墙 → 沿 MuJoCo 墙段铺护栏；权威碰撞仍为契约 box。
- Playground：`MW_BUILD=20260722-134505`。

## 2026-07-22 · demo_race 可视修复 + 提速中圈

- 根因：~530 m 远看像小环；空槽幽灵车叠堆；工坊臂误画。
- 修复：只广播已入座；2×3 发车格；无臂底盘；橙护墙。
- 手感：~292 m 圈 · ctrl ±18（≈15 m/s）· 可视起伏 ribbon（物理仍平面）。
- Playground：`MW_BUILD=20260722-132021` · 双服务 active。
- 下一刀素材：Kenney [Racing Kit](https://kenney.nl/assets/racing-kit) / [Car Kit](https://kenney.nl/assets/car-kit)（CC0 glTF）做护栏/路牌/车皮。

## 2026-07-22 · E9 + B1 落库 / playground 发版

- 入库：E9（Hub 插值/`presence_throttle`/参观壳）+ B1 `demo_race`（高速长弯 · max 6 · MuJoCo）。
- Playground 发版：`MW_BUILD=20260722-130156` · `wss://playground.dev.databall.tech/ws` · 双服务 active。
- **Next = B2 薄 1v1**；E6–E7 可穿插。

## 2026-07-22 · demo_race 高速加长曲率赛道

- 中心线波浪椭圆 + 内外墙；CP1→CP2→终点（`params.requires`）；`diffbot_race` ctrl ±12（≈10 m/s）。
- 生成器 `scripts/gen_demo_race_track.py`（后续已缩圈，见上条）。

## 2026-07-22 · B1 demo_race 赛车场（max 6 · MuJoCo）

- 契约 `demo_race`：空气墙 + 计时冲线；共享房 `race` max 6；计分同 city 时长公式。
- Godot `demo_race.tscn` + `race_dress.gd`；Hub 门 E 走近进入；lobby / 排行榜 tab。
- Gateway：`RACE_ROOM_*`；smoke：`--level-id demo_race --expect-objective`（建议 `--physics mujoco`）。

## 2026-07-22 · E9 Hub 公网插值/降频

- 远端：`avatar_puppet` 限速插值 + 短外推 + 大跳 snap；自机 `local_predict`。
- Gateway：`cmd.action=presence_throttle`（`full|low|paused`）；Hub 房 state 降频/keepalive。
- Web：薄参观壳 `#mw-visitor-shell`（iframe + 关闭）；开壳暂停 Hub WS；`scripts/e9_presence_throttle_smoke.py`。

## 2026-07-22 · E5d 北翼按 role 挂 curated 展柜

- Hub：`classroom` 东·北墙、`gallery` 西·北墙、`lab`/`foresight` 西墙；缩略屏 + Label3D；翼站 lore 显示张数。
- 仍 TYPE B（F → stub/enter URL）；不迁 PMS 物理。
- Playground 发版：`MW_BUILD=20260722-113437` · `wss://playground.dev.databall.tech/ws` · 品牌注入后双服务 active。

## 2026-07-22 · A3 单人 IL 模板变体

- 模板 id：`extensions.mw.il.template=solo_il_place_v0`（`demo_workshop` 同源）。
- 变体：`tutorial_place_near`（近距/240s）· `tutorial_place_tight`（远距+紧 AABB/120s）；`scripts/a3_catalog_smoke.py`。
- join：`level_id=tutorial_place_*`（Admin/URL 与既有契约目录）。

## 2026-07-22 · A1 收口 + A2 分关天梯

- A1：工坊进关提示 + 剩余时限 HUD；放置橙垫/路径指向工作台；Recordings `task_id` + IL 预设；Portal「导出工坊 IL CSV」。
- A2：`GET /api/platform/leaderboard?level_id=`；Hub/Portal 总榜·工坊·训练场切换。
- **Next = A3** 训练关模板变体。

## 2026-07-22 · A1 起步：超时 fail + place 唯一终局

- Gateway：`extensions.mw.il.task_id` 外的 `reach_region` 为 milestone（推箱不弹 SUCCESS）；`time_limit_s` → `objective_failed` + `outcome=fail`。
- 工坊契约 `time_limit_s=180`；Godot 里程碑提示；`scripts/a1_fail_smoke.py`。
- 公网纠偏见上条：playground 已通，不阻塞 A1。

## 2026-07-22 · 公网纠偏：playground 已通，W2 非阻塞

- 现网：`playground.dev.databall.tech`（ALB→WGateway→WG→CVM）；HTTPS + wss 已覆盖 Demo 验收。
- [09](09-todo.md) / [AGENTS](../AGENTS.md) / [23](23-public-deploy.md)：`databall.cloud` W2.0–2.4 标为后置；**Next = A1→A2→A3**，不因 DNS 卡住。

## 2026-07-22 · PMS demos → 学院课程/展柜目录

- 自数聚球 `demos/README.md`（23 卡）筛选：classroom / gallery / lab / foresight；空模板与 Go2/DISCOVERSE 后置。
- `examples/hub/exhibits.v0.json`（及 Godot 副本）换成真实 `space_id`；[21](21-ecosystem-federation.md) §PMS catalog；[09](09-todo.md) E5c Done · E5d 待挂载。
- **Next 仍为 A1**；E5d 穿插依赖 E6–E8，不替代工坊 IL。

## 2026-07-22 · 愿景：学院 + 竞技场 / 三阶段排期

- README 英/中写入 Space Robot Academy + Arena 与数据飞轮叙事。
- [00](00-vision.md) 补学院定位与远景任务谱（≠本期全做）；[09](09-todo.md) Now = Phase A（A1 工坊 IL **Next**）。

---

## 2026-07-22 · Hub 首印象：学院暖港 / 引导 / 假活跃

- 中央「今日去处」碑 + spawn→A/B 地面灯带；灯光暖一档；chase 略抬高俯视。
- NPC 挪中环；本地巡逻假人 + 程序化机库环境音（无第三方采样）。

---

## 2026-07-22 · 开源落地页默认 / 驾驶员 / 默认身后跟随

- 落地页默认「机甲学院母港」+ `© 2026 Bug Copyright 云端机甲学院`（无 ICP）；公网品牌注入见私有 `scripts/*.local.py`。
- 中文「飞行员」→「驾驶员」；相机默认 **chase-behind**（身后跟随），不是 orbit / first-person。
- README 英/中分册 + `screenshots/`。

---

## 2026-07-22 · Hub 人偶：Kenney Blocky + 走跑动画

- `avatar_puppet`：轮式程序化模型 → Kenney `character-a..d`；idle/walk/sprint 由插值速度驱动；H9 accent 换皮。Gateway 不变。
- 大厅 `MOVE_SPEED` 5.5 → 2.8（人形手感）。

---

## 2026-07-21 · 文档：City 三连坑教训入库

- [25-qa-local-export.md](25-qa-local-export.md)：臂 UI 竞态 / A–E 队标 / multi-lot 吞街空气墙；导出缓存假象；playground 发版核对。

---

## 2026-07-21 · 操控：WASD 平移 + 鼠标 peek/粘性

- 键盘：W/S 进退，A/D 平移，Q/E 转向（对齐全向底盘；修正原先 QE/AD 对调）。
- 鼠标：左键 peek（松手回中）、右键粘性环视、中键或左右同按平移、滚轮缩放、C 强制回中。
- City：KayKit 按 footprint 非均匀拉伸，避免「白地不可进」；默认不画玻璃盒；City 隐藏臂爪 UI。

---

## 2026-07-21 · City 多地块空气墙 / 五车队标 / 臂 UI

- 多地块楼：MuJoCo 改为**每 lot 一盒**，楼间街道可通行（不再吞路画沥青却撞墙）。
- 机甲队标 A–E；City 进房强制 `mw-no-joints` 隐藏臂/爪 DOM。

---

## 2026-07-21 · Hub L2 缩小

- L2 观景廊收至约大厅 1/4（东南电梯侧）；中央广场进门仰视不再被半层楼板压住。

---

## 2026-07-21 · 计划入库：PMS 参观者壳 / Hub 手感

- [21](21-ecosystem-federation.md) P1b：E6 换票 → E7 列表 → E8 同页 iframe 壳+侧栏 → E9 插值/降频。
- [09](09-todo.md) Next 指向该切片；北翼 TYPE B 落点不变。

---

## 2026-07-21 · 训练场共享房 / 空气墙对齐 / 蜿蜒地图

- 训练场（`demo_city`）默认进共享房 `city`，最多 5 人；满员 `ROOM_FULL` 回母港。
- MuJoCo 模型缓存按 `seed`；空房重建，避免 seed 热更后墙体与视觉脱节。
- 楼宇 footprint = KayKit×scale（≈LOT）+ 薄边，对齐视觉；地图 8×7；终点东北角（需转弯绕行）。

---

## 2026-07-21 · Hub 同账号区分 / 空气墙 / 减噪

- Hub 显示名：`昵称 · session短码`（账号仍共用；单 session 限制后置）。
- FakeMech：可行走收束到厅内+门湾；支柱 `blocked`；玩家间软推开。
- 视觉：去掉满屏 F/翼区/壳 Label3D；A/B 门标更大，C–E 更淡；名牌近距才显示。

---

## 2026-07-21 · Esc 回母港 / SUCCESS 浮层

- Esc→Hub：清粘键、门触发冷却/需先离开门区再武装；断开 WS；忽略残留 `?room=demo`。
- Web：通关 `#mw-success` 在回母港 / 离开 play 时清除（不再永远飘着）。

---

## 2026-07-21 · Portal 登录/Admin 与落地页

- 登录页去掉 demo/demo 提示；Admin 去掉默认密钥文案；未登录不可用 Admin 页（仍无角色组，运维靠 `X-Admin-Key`）。
- 落地页：SVG 动态星空 + 公司版权 / ICP 页脚。
- 私有运维：`docs/ops.local.md`（gitignore）。

---

## 2026-07-21 · H-bounds / E3b / IL-place′ / QA

- Hub：`bounds.walkable` 多段 FakeMech 空气墙（南坞缝不可走）。
- E3b：门 A / 进关保留 `space_id`；工坊 HUD 显示归因；去「占位」文案。
- IL-place′：`grasp_lift` 里程碑不再弹终局 SUCCESS。
- QA：[25-qa-local-export.md](25-qa-local-export.md) + `scripts/h_bounds_e3b_smoke.py`。

---

## 2026-07-21 · H12g′ 去悬空细环

- 去掉甲板/拱门纯 Torus 光环；改为舱顶圆顶、落地储罐球、颈+球仓模块。

---

## 2026-07-21 · CJK 字体（Label3D）

- 根因：Godot 默认字体无中文 glyph；DOM 壳正常、3D 门标/NPC 空白。
- 入库 Noto Sans SC（OFL）+ `MWFonts` 应用到 Hub Label3D / 桌面 HUD。

---

## 2026-07-21 · H12g 外场曲线装饰

- 纯视觉：雷达球罩、储罐球、甲板环带、对接胶囊、南北拱环；舱顶碟改球体。
- 不进权威 / 无碰撞；仍 FakeMech bounds。

---

## 2026-07-21 · H12f 环形港湾外轮廓

- 甲板改为环段拼合（不再整块大方板）；南缘三坞口凹槽 + 加长接驳臂。
- 外围叠舱加密、层数拉高；岛缘下翻裙边 + 阶梯龙骨侧面可见。

---

## 2026-07-21 · H12e 外场迷你太空城

- 外场放大为浮岛迷你城：阶梯 terraces、四角指挥塔、南北东西叠舱群、天桥、南向舰队接驳臂、龙骨 understructure + underglow。
- Hab / Berth / Control 三舱；契约 bounds → 40×36；相机可视距离放宽。

---

## 2026-07-21 · H12d 太空港视觉语言薄做

- 吸收参考：哑光灰巨型结构 + 青蓝能量面板（非宿舍舱、非仓库灰盒）。
- Hub dress：暗甲板/墙肋、青蓝导引带与窗带、外场角塔+环段面板、舱底 underglow、轻微 glow。

---

## 2026-07-21 · H7c + Portal 双语 + H12c 外场舱

- **H7c**：门 C 设计室 / 门 D 边缘坞立面壳 + 地垫；F 循环状态（sealed/catalog/exhibits · offline/pending/camera_stub）；不进 MuJoCo、不接真机。
- **i18n**：`me.html` / `admin.html` 挂 `mw_i18n.js`；错误与空态中文优先。
- **H12c**：南甲板停机坪上 Hab / Berth 两个模块舱（视觉占位）。

---

## 2026-07-21 · H12 母港布局 + 中英双语

- 新增 [24-hub-mothership.md](24-hub-mothership.md)：三类出口翼区（本仓/卡片/边缘）+ 浮空岛母港叙事。
- Hub 尺度：厅 24×20、举架 22、L2=8.5；外延金属网格甲板；窗带；门 E 南移、D 西北边缘坞。
- 契约 bounds → 28×24；小地图/shell 同步。
- `mw_i18n.js`：`localStorage.mw_lang` 默认 `zh`；Landing / login / shell 可切换；3D 门标/lore 中文优先双语。

---

## 2026-07-21 · City 多格楼 + KayKit 恢复

- 生成器支持 1×1 / 2×1 / 1×2 / 3×1 / 1×3 / 2×2 占地（含格间街道），MuJoCo 盒与之一致。
- Godot：KayKit 默认开（按 footprint 缩放塞进盒内）；半透明占地盒仍可见碰撞；`?kaykit=0` 仅方盒。

---

## 2026-07-21 · City 视觉=MuJoCo 占地盒

- `city_block_dress`：默认画与 `static_obstacles` 同尺寸的不透明楼盒（看得见的墙=会撞的墙）。
- 旧 Authority 灰盒一律隐藏；KayKit 皮可选 `?kaykit=1`（装饰，不改权威）。

---

## 2026-07-21 · City 空气墙调试叠层

- `city_block_dress`：半透明青盒 = MuJoCo `static_obstacles`（默认开；`?walls=0` / 取消「空气墙」关掉）。
- `block_layout.json` 含 `obstacles`；与契约同 seed 双写。

---

## 2026-07-21 · W2 公网实施建议书

- 新增 [23-public-deploy.md](23-public-deploy.md)：腾讯云 2C8G + `databall.cloud` 单机拓扑、资源判断、Caddy/env、分阶段清单与验收。
- 非仿真负载确认轻量；MuJoCo 公网需限房。实施仍待 CVM 上执行（W2.1/2/4 未勾 Done）。

---

## 2026-07-21 · H11 竞技场门占位

- 门 E：Arena Gate 立面/地垫/橙红霓虹；小地图 E 点高亮。
- F：四态循环 `1v1/party × Looking-for-match`；**不** join、**不**开 PMS URL。
- Classroom 交互台略东移，避免与 Arena pad 抢 F。

---

## 2026-07-21 · PL2 Admin 运维 + E4 真 URL + IL-place 飞轮

- **PL2**：Gateway admin HTTP `:8770`（`GET /admin/rooms|contracts|status`，`POST /admin/levels/disable|enable`）；Portal Admin 在线房表 + level 开关；`serve_web` 代理 `/api/gateway/*`；`admin_ops_smoke`。
- **E4/E3**：展柜 `enter_url` → `spaces.databall.tech/enter/...`；stub 可开 live Space / 带 `space_id` 回 Hangar。
- **IL**：`scripts/il_place_smoke.py` — 录 grasp→place → export `obj_place_block` → `bc_offline_check`。

```bash
.venv/bin/python scripts/admin_ops_smoke.py
.venv/bin/python scripts/il_place_smoke.py
.venv/bin/python scripts/ws_smoke_test.py
```

---

## 2026-07-21 · E3 会话归因 + H9/H10 Hub 慢扩

- **E3**：`space_id` / `route_kind` 写入 join → recording header → scores；`?space_id=`；样例 `examples/platform/session_attribution.v0.json`。
- **H9**：Party board 切换 Looking-for-crew + stub LFG；Vendor F 循环 accent 并写 profile。
- **H10**：北墙 Gallery / Classroom 走廊壳 + 交互台 lore。

```bash
.venv/bin/python scripts/platform_smoke.py
.venv/bin/python scripts/ws_smoke_test.py
```

---

## 2026-07-21 · E2 身份映射草案 + federated stub

- SSOT：[22-identity-mapping.md](22-identity-mapping.md)；样例 `examples/platform/identity_link.v0.json`。
- `identity_links` 表；`POST /login/federated`（stub）；Admin `identity-links`；`/me` 返回 links。
- `platform_smoke` 覆盖 link + federated 幂等。

---

## 2026-07-21 · E4 展柜 → 外部 Space stub

- Hub 两侧展柜：走近 F → 新标签打开配置 URL（不进 MuJoCo）。
- E5 薄做：`examples/hub/exhibits.v0.json`（与 `godot/spike/data/exhibits.v0.json` 同步）；`/portal/space_stub.html` 可 **Back to hangar**。

---

## 2026-07-20 · R3 / IL place / H8

- **R3**：Hub `main_scene` 下 `/?replay=` 按 recording `level_id` 路由到 workshop/city；Recordings / My record 恢复 3D 入口；Esc 清 `replay` 防回环。
- **IL**：`obj_place_block`（工作台 AABB + 张开夹爪）；`grasp_lift` 仅里程碑不写 outcome；`grasp_place_smoke.py`；默认 `mw.il.task_id=obj_place_block`；录制终局写回 `task_id`。
- **H8**：电梯 F 薄乘 L1↔L2（avatar `height_offset`）；L2 呼叫台；门在 L2 不触发。

```bash
.venv/bin/python scripts/grasp_place_smoke.py
.venv/bin/python scripts/grasp_lift_smoke.py
.venv/bin/python scripts/stow_crate_smoke.py
```

---

## 2026-07-20 · W1 工坊双 prop（推箱 + 抓取）

- `prop_crate` 恢复 0.5 m 供 `obj_stow_crate`；新增 `prop_block` 6 cm 供 `obj_lift_block`。
- `stow_crate_smoke` / `grasp_lift_smoke` 分目标验收。

---

## 2026-07-20 · E1 Portal Landing → Profile/榜 → 进大厅

- `/portal/` 品牌 Landing（未登录 Sign in；已登录 Enter hangar）。
- `/portal/me.html`：主 CTA **Enter hangar** + 积分 + Leaderboard + 近期会话。
- 登录默认 `next=/portal/me.html`；游戏壳未登录 → `/portal/?next=…`（不再直跳 login）。

---

## 2026-07-20 · 生态对接叙事冻结（21）

- 新增 **[21-ecosystem-federation.md](21-ecosystem-federation.md)**：MineWorld = 3D 传送门前台；本仓 MuJoCo 玩法/采数；展厅/教室等 → PMS Space（对接不搬迁）。
- [00-vision.md](00-vision.md) / [AGENTS.md](../AGENTS.md) / [docs/README.md](README.md) / [09](09-todo.md) Now：**E4 / E2**（E1·W1 Done）。

---

## 2026-07-20 · C 线产品闭环收口

### 方向

- **C1–C4 Done**；H8 / R3 / 公网仍顺延。
- 验收主路径：登录 → Hub → 通关 → +N pts → 排行 / 我的 → 2D 回放。

### 实现摘要

- **C1**：`main.gd` 玩法关 `join` 传入 `extensions.mw.profile`（对齐 Hub）。
- **C2**：`objective_complete.detail.points` + 通关即时幂等记账；SUCCESS UI 显示 +N pts / My record 链。
- **C3**：`scripts/journey_smoke.py`（platform API + MuJoCo；`demo_city` 开环到点验收积分链）。
- **C4**：UX2b 薄做（门色过场 · 桌面 Tween · 可跳过）。

```bash
.venv/bin/python scripts/journey_smoke.py
```

---

## 2026-07-20 · 3D Hub（地下城入口）落地

### 产品

- 默认主场景改为 `demo_hub.tscn`；文本试验场降级为 `/?menu=1`。
- Hub 世界观与门 A–E 映射冻结于 [18](18-hub-dungeon.md)；本期可进 **A 工坊 / B 训练场**。
- 本地 Profile（昵称）无登录；Web `localStorage` / 桌面 `user://`。

### Gateway

- `demo_hub` 契约：`extensions.mw.mode = "hub"`；Hub 房强制 FakeMech（即使 `--physics mujoco`）。
- 公共房 `room_id=hub`，互见纸片人；**不录** IL。
- `join.player_name` / profile → `state.extensions.mw.display_name`。

### 客户端观感

- 实心机库大厅 + 太空星空天空盒；轮式机器人纸片人。
- 靠墙家具 / 交互台 / Kenney Blocky NPC（静站、缩小、贴地）。
- 相机：环绕 → 第一人称 → 追尾；追尾 RMB/MMB 环视 + 滚轮缩放。
- Web DOM 角标（提示 / 名片 / 小地图），按 `#canvas` 矩形定位，缓解裁切。
- **展示壳**：南侧半层二楼 + 东南角静态电梯（不可乘；F 提示 offline）。

### 资产

- KayKit Dungeon Remastered 子集、Kenney Blocky Characters 子集（见根 `ASSETS.md`）。

### 验证

```bash
.venv/bin/python gateway/echo_server.py --physics fake --no-record
bash scripts/export_godot.sh web && bash scripts/serve_web.sh restart
.venv/bin/python scripts/hub_presence_smoke.py   # 若脚本在仓
# 浏览器 Cmd+Shift+R → http://127.0.0.1:8080/
```

---

## 2026-07-20 · V 线冻结项收口（摘要）

- 车间 `demo_workshop` + 臂/爪 + sticky grasp → IL 标签/导出（详见 [16](16-value-sprint.md)）。
- 试验场 H0–H2、录制过滤 R1/R2 等已勾选（见 [09](09-todo.md) Done）。

---

## 后续方向（已记入 Todo）

| 线 | 摘要 | Todo ID |
|----|------|---------|
| **C 闭环** | profile join · 通关积分 · journey smoke · UX2b 薄 | C1–C4（见上） |
| UX | 过场增强 | UX2b / C4 |
| Hub | 可乘电梯 / 可上 L2（顺延） | H8 |
| 回放 | 修复 `/?replay=` 3D | R3（Next） |

完整条目与验收见 [09 § Now / Next](09-todo.md)。

---

## 2026-07-20 · H7 Hub UI + UX3 重连

- H7：左栏门语境 lore；名片 Pilot card；小地图标 C–E；北墙 D/E stub + 走近文案（不进关）。
- UX3：`WsClient` 自动重连 + `link_phase_changed`；Hub/关卡明确 Connecting / Reconnecting / Offline 文案。

## 2026-07-20 · 相机 SSOT + P1b BC 离线检查

- `camera_rig.gd`：V/C/鼠标为共享 SSOT；chase 松手视线弹簧回正（焦距保留）；关卡与 Hub 共用。
- Hub/关卡 Web 桥只调 `handle_code`；关卡补 V + FP 隐藏车体。
- `scripts/bc_offline_check.py` + `examples/il/bc_sample.csv`：断言 success CSV 有可解析 `joints`。

## 2026-07-20 · AD2 / EXP1 + P1a 摩擦抓取

### Admin 钻取与导出
- 录制 header 写 `player_id`；`/api/recordings?player_id=` 与 `export.csv?player_id=`；CLI `--player-id`。
- Admin 点玩家 → 会话列表（2D 回放链）+ Export CSV（success / all）。

### P1a 真摩擦抓取 v0
- 去掉 sticky weld / 每 tick 粘贴；`grasp_lift` 只认闭合 + 真实接触 + `min_z`。
- 工坊 `prop_crate` 改为可夹 6 cm 料块；`grasp_lift_smoke.py` PASS（不查 weld）。

## 2026-07-20 · 暂禁 3D offline replay（R3）

- Recordings「▶ 3D Replay」改为 disabled；My record 只保留 2D 链。
- 任务 **R3**：修好 `/?replay=` 后再开入口。

## 2026-07-20 · Phase C · ME2 自助回放

- My record 每行探测 `/api/recordings/<id>`：有帧则链 **2D**（`recordings.html?session=`）；3D 暂禁见上。
- Admin 本地默认 key `dev-admin`（可用 env 覆盖）。

---

## 2026-07-20 · Phase C · ME1 / AD1

- Portal `/portal/me.html`：积分汇总 + 近期会话（`/api/platform/me` 扩展）。
- Admin `/portal/admin.html`：admin key 列玩家 / 创建账号。
- Hub 名片链到 My record。

---

## 2026-07-20 · Phase B · SC1/SC2/LB1 + PL3

- 积分公式 `mw_platform/scoring.py`；`scores` 表幂等记账；Gateway `score_client` 在 success close 时 POST。
- Hub DOM `#mw-hub-lb` 轮询 `/api/platform/leaderboard`。
- PL3：`docs/20` §4.1 WS vs HTTP 边界表。

---

## 2026-07-20 · Phase A v0（Portal + SQLite API）

- `mw_platform/`：可换 URL 的 SQLite 玩家库 + Bearer token。
- Portal `/portal/login.html`；未登录访问 `/` 跳转登录（demo/demo）。
- 独立 API：`python mw_platform/api_server.py`（8090）；Web 同域也挂载 `/api/platform/*`。

---

## 2026-07-20 · 平台门户产品线写入计划

- 新增 [20-platform-portal.md](20-platform-portal.md)：Portal 登录 → Hub → 计分关 → 排行/我的/Admin。
- Todo 拆 Phase A/B/C（PL/ID/SC/LB/ME/AD/EXP）；与 P1 并行、Gateway 不塞用户库。

---

## 2026-07-20 · UX1 + UX2-v0

- Web 首屏：`shell.html` 品牌字标（MineWorld / Dungeon Gate）+ 进度条；隐藏 Godot 默认 splash 图。
- 过场：`MW_TRANSITION` DOM 淡入淡出（~280ms）；Autoload `MWTransition.go` / `notify_arrived` 覆盖 Hub 门、Esc 回 Hub、文本菜单。
## 2026-07-23 · state delta 压缩（P1 带宽）

- 网关在 20Hz state 广播做会话级增量：首帧/每 25 帧关键帧发 full，中间只发量化后
  位姿/速度有变化的实体（kind=delta，schema 已预留枚举）。
- 录制仍写 full 帧，回放/幽灵车/IL 导出完整性不受影响。
- 实测 demo_race 同房：avg delta 308B vs full 1266B（-76%）；`ws_smoke_test` 回归 PASS。
