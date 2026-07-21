# 18 · 地下城入口 Hub（世界观与产品壳）

| 字段 | 值 |
|------|-----|
| **状态** | Active · H4–H6 / H6b 已落地；生态通道见 [21](21-ecosystem-federation.md)；H7–H11 · E/UX/PL 见 [09](09-todo.md) |
| **日期** | 2026-07-20 |
| **关联** | [00](00-vision.md) · [15](15-course-correction.md) · [17](17-lobby-testfield.md) · [09](09-todo.md) · [19](19-changelog.md) · **[21](21-ecosystem-federation.md)** |
| **主场景** | `godot/spike/demo_hub.tscn`（工程 `main_scene`） |
| **调试菜单** | `/?menu=1` → `demo_lobby.tscn`（文本选关，保留） |

> **Hub** = 默认起始关：地下城入口大厅。Godot 负责走动与叙事 UI；Gateway **Hub 房不接 MuJoCo**，只做多人在场同步（假物理位姿）。  
> **真数据价值**仍在进门之后的本仓 MuJoCo 遥操关（车间 / 街区等）。  
> **展厅/教室等**不在本仓仿真：经展柜通道进入 PMS Space（对接，见 [21](21-ecosystem-federation.md)）。

---

## 1. 背景故事（冻结切片）

你们从地表裂隙坠入 **「机甲契约地下城」入口厅** —— 一座有限封闭的石厅。  
厅里能看见通向不同分支的门；每扇门通向一条玩法路线。大厅本身不是竞技场，只是集合与分流。

| UI 区 | 作用 |
|-------|------|
| 左侧文本 | Lore / 操作提示 / 当前门说明 |
| 右侧导引图 | 顶视小地图（厅轮廓 + 自己/他人点） |
| 右上人物卡 | 本地昵称 / 简卡（无登录） |

---

## 2. 门 → 路线映射（产品树）

| 门 | 路线 | 本期 | 备注 |
|----|------|------|------|
| **A · 仿真工坊** | 单人精细操作 / 自定义关节 · IL | ✅ 可进 | → `demo_workshop` + MuJoCo（本仓） |
| **B · 机甲训练场** | 多人联网巡航 / 推箱 | ✅ 可进 | → `demo_city`；`?room=demo`（本仓） |
| **C · 设计室** | 自定义空间 / 契约导出 | 后置 | 编辑器 + T4.2 |
| **D · 雇佣兵任务中心** | 任务闯关包 | 后置 | 任务卡 + outcome |
| **E · 竞技场** | 组队排名 | **H11 壳** | 门 E + F 四态 stub；匹配/结算权威另案 |
| **展柜 / 房间通道** | PMS Space 卡片 | **E4 stub** | F → 新标签 URL；元数据 `examples/hub/exhibits.v0.json` |

铁律：换门 = 换场景 +（若本仓玩法关）换 `join.level_id` 权威世界；Hub 不录 IL 轨迹。外部卡片通道不进入 Hub MjData。

---

## 3. 技术切片（H4–H6）

| ID | 内容 | 验收 |
|----|------|------|
| **H4** | 3D Hub 外壳 + 门 A/B + `?menu=1` 文本菜单 | Web/F5 默认进厅；`?menu=1` 见旧菜单 |
| **H5** | Hub 互见：`level_id=demo_hub` + `room_id=hub`，无 MuJoCo | 两浏览器可见对方纸片人 |
| **H6** | 本地 Profile：昵称 + accent，localStorage，无登录 | 头顶显示昵称；刷新仍在 |
| **H7** | 左栏/右栏/人物菜单打磨 + 门 C–E 占位 | ✅ v0 |
| **H8** | 可乘电梯 + 可上 L2 | ✅ 薄乘（viewer Y） |
| **H9** | Party board / Vendor | ✅ 薄 UI（LFG 切换 / accent 循环） |
| **H10** | 展厅/教室走廊壳 | ✅ 北墙 alcove + lore |
| **H11** | 竞技场门占位 | ✅ 门 E 壳 + F 1v1/party×LFM stub |
| **H6b** | 观感：机库/星空/NPC/DOM HUD/展示电梯+半层二楼 | 已落地 |

### 3.1 Gateway

- 契约 `examples/contracts/demo_hub.json`，`extensions.mw.mode = "hub"`。
- 即使进程 `--physics mujoco`，Hub 房也 **强制 FakeMech**（不 compile MjModel）。
- 默认公共房 `room_id=hub`，`max_members=8`（契约可改）。
- **不写** `recordings/`（Hub 非遥操采集）。
- `join.player_name` + `extensions.mw.profile` 写入 session；`state` 实体带 `extensions.mw.display_name`。

### 3.2 客户端

- 本地走动仍走 Gateway `cmd` velocity（与玩法关同一协议），纸片人跟 `state`。
- 进门前 `bye` / 断链，再经 **`MWTransition`**（Web DOM 淡入淡出）`change_scene` 到玩法关并重新 `join`。
- Profile：Web `localStorage.mw_profile`；桌面 `user://mw_profile.json`。
- 首屏：Web `shell.html` 品牌 boot（UX1 v0）；过场见 [19](19-changelog.md)。

### 3.3 非目标（本期不做）

账号登录、真匹配、商城、换装 RPG、Hub 内 MuJoCo、门 C–D 完整玩法。  
**电梯 / 二楼** 已可薄乘（H8）；Gallery / Classroom 仅为走廊叙事壳（H10）；**Arena** 仅为门 E 叙事+F stub（H11，无权威）。

---

## 4. 与试验场文档关系

- [17](17-lobby-testfield.md) 描述的 **文本选关** 降级为调试入口（`?menu=1`）。
- 玩家默认路径以本文 **3D Hub** 为准。
- H0–H2（多契约 join / Esc 回入口）仍然有效；Esc 回 **Hub** 而非纯文本菜单。

---

## 5. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-20 | 初版：地下城入口世界观；H4–H6 切片；门 A–E 映射 |
| 2026-07-20 | Hub 展示：南侧半层二楼 + 东南角静态电梯井（不可乘） |
| 2026-07-20 | UX1/UX2-v0：品牌首屏 + `MWTransition` 切景淡入淡出 |
| 2026-07-21 | H11：门 E Arena Gate 壳 + F 1v1/party×LFM stub |
