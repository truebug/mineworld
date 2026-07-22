# 19 · 变更记录（Changelog）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-20 |
| **关联** | [09-todo.md](09-todo.md) · [18-hub-dungeon.md](18-hub-dungeon.md) · [16-value-sprint.md](16-value-sprint.md) · [20-platform-portal.md](20-platform-portal.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) · [25-qa-local-export.md](25-qa-local-export.md) |

> 按时间倒序记「已入库」切片；待办与路线见 [09](09-todo.md)。不替代 git log，只记产品/架构向摘要。

---

## 2026-07-22 · demo_race 驾驶模型重构 R1–R5

- R1 协议：`control_mode: "drive"`（throttle/brake/steer/handbrake 模拟量），网关 Ackermann 映射按契约 `extensions.mw.drive` 参数执行；`velocity` 模式零影响。
- R2 输入：键盘按住渐进给油（2.5/s）、松开衰减、转向按住渐进打死（3/s）松手自动回正（5/s）；X 倒车低速保护；手柄 axis 原生接入。
- R3 HUD：车速 km/h、油门/刹车条、转向指示、cp 分段计时；相机 FOV 随速度扩张（55→67°）+ 弹性跟随滞后。
- R4 特效：重刹/高速急转胎痕（FIFO 220 条）+ 刹车烟尘粒子；race 插值延迟 50→30ms。全部 viewer-only。
- R5 赛道：弯心红白路缘带 + 弯前 50/100/150m 刹车牌（按 centerline 曲率自动布点）。
- 验收：无头 drive 冒烟 PASS（半油门+半转向 3s 位移 8.1m、转向 0.44rad）。

## 2026-07-22 · 赛车场环境丰富化（viewer-only）

- 草坪：路缘外侧绿地毯条带沿全圈铺设；绿化带：每 3 个采样点一排修剪绿篱。
- 安全区：弯心出口侧砾石缓冲区（浅色 pad）+ 远端红白糖罐轮胎墙。
- 看台：起终点双侧三层阶梯看台（灰阶台阶 + 彩色观众点）+ billboardLow 背景板。
- 全部由 centerline/curvature 自动布点；不碰 MuJoCo 物理与契约。

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
