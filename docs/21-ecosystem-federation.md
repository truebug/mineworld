# 21 · 生态对接与统一前台（数聚球多平台）

| 字段 | 值 |
|------|-----|
| **状态** | Living · 产品叙事 SSOT |
| **日期** | 2026-07-20 |
| **关联** | [00-vision.md](00-vision.md) · [18-hub-dungeon.md](18-hub-dungeon.md) · [20-platform-portal.md](20-platform-portal.md) · [09-todo.md](09-todo.md) |
| **仓外依赖** | 数聚球 `projects/`：`pms-system` · `robohub_server` · `roboweb_frontend` · `spaces.databall.tech` |

> MineWorld **不是**要把厨房 / 无人船 / GZWeb / VLA 实验室全搬进本仓 Gateway。  
> 它是数聚球仿真宇宙的 **3D 传送门前台** + **本仓真动力学玩法/采数管道**；展厅级场景走既有 PMS Space/卡片能力。

---

## 1. 一句话定位

**Godot Hub + 本仓 MuJoCo = 传送门主体**（大厅导览、机甲关、遥操档案）。  
**PMS / Spaces / RoboWeb / RoboHub = 既有执行与社区能力**（Space 生命周期、WebIDE、mjviser/GZWeb、订阅与编排）。  
**统一身份**把两边的人、会话、战绩串成一个大一统平台前台。

---

## 2. 分层图

```text
┌─────────────────────────────────────────────────────────────┐
│  统一身份 / 前台壳                                           │
│  Landing · Profile · 榜单 · Portal（本仓 mw_platform v0）     │
│  → 远期对齐 roboweb / spaces / robohub 账号体系               │
└───────────────────────────┬─────────────────────────────────┘
                            │ 「进入大厅」
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  MineWorld Godot Hub（demo_hub）                             │
│  发现 · 社交皮 · 房间/走廊占位 · 门与展柜路由                   │
└───────┬─────────────────────────────┬───────────────────────┘
        │ 本仓传送门（主体玩法）         │ 外部卡片通道（对接）
        ▼                             ▼
┌───────────────────┐     ┌───────────────────────────────────┐
│ Gateway + MuJoCo  │     │ PMS Space / 官方卡片               │
│ workshop / city   │     │ enter → WebIDE / mjviser / GZWeb │
│ 竞技场（后续）     │     │ 教室课件 · 展厅 · 实验室 · 边缘    │
│ 录制 / IL / 积分  │     │ （pms-system 既有能力，不迁物理）   │
└───────────────────┘     └───────────────────────────────────┘
```

---

## 3. 仓外系统角色（只读索引）

路径相对于数聚球 monorepo：`../数聚球/projects/`（本机常见为 `Downloads/projects/数聚球/projects/`）。

| 仓库 / 站点 | 角色 |
|-------------|------|
| **pms-system** | Space/卡片编排、viser-gateway、gzweb、edge；执行层 SSOT |
| **robohub_server** | 用户空间 / 订阅 / 与 PMS 编排对接的 API |
| **roboweb_frontend** | WebPortal：登录、Space 管理主入口 |
| **spaces.databall.tech** | Mini Portal：发现、Try/Fork、社区互动 → WebIDE |
| **mujoco-base** 等 | 基础镜像；MineWorld 可引用，不复制编排逻辑 |

MineWorld `docs/00` 已点名 `pms-system/platform/viser-gateway`；本文件把「对接而非搬迁」钉死。

---

## 4. Hub 内容三类出口（冻结分类）

| 类型 | 例子 | 实现原则 |
|------|------|----------|
| **A · 本仓关卡** | 工坊、训练场、后续机甲竞技 | `join.level_id` → Gateway MuJoCo；录制进 IL |
| **B · PMS 卡片通道** | 展厅展柜、教室课件、实验室实例 | Hub 只存元数据（`space_id` / URL / 标签）；F/门 → 打开 enter URL 或 WebIDE；**不**把 MJCF 塞进 Hub MjData |
| **C · 边缘 / 真机** | 车间机械臂、摄像头直播 | 走 pms-system/edge；Hub 仅入口 + 鉴权提示 |

房间（展厅 / 教室 / 车间 / 实验室 / 训练场 / 竞技）可用走廊、楼梯、门慢慢扩充；**先占位叙事，再接真实 URL**。

---

## 5. 铁律（对接时勿破）

1. Godot **不**成为全平台仿真权威；PMS 容器内物理仍在容器内。  
2. Gateway WS **不**管平台用户库；身份经 Portal / 远期 SSO 注入 `profile.id`。  
3. 禁止为「演示好看」把高保真场景 MJCF 批量迁入本仓。  
4. 本仓飞轮优先：好玩 → 有任务约束的遥操数据 → IL / 评测；对接通道服务发现与导流。

---

## 6. 后续工作建议（按优先级）

> 勾选落地见 [09-todo.md](09-todo.md) `Now / Next（E · 生态）`。此处只给方向，不替代 Todo。

### P0 · 身份与前台（对接前提）

| 建议 ID | 内容 | 为何先做 |
|---------|------|----------|
| E1 | Portal Landing：未登录品牌页 → 登录 → Profile/榜单 →「进入大厅」（**Done** `/portal/` · `/portal/me.html`） | 统一前台第一印象 |
| E2 | `player_id` ↔ 平台 user 映射草案（文档 + 可选 stub token） | **Done** — [22](22-identity-mapping.md) + federated stub |
| E3 | 通关/会话归因字段预留（`space_id` 可空；本仓 `level_id` 已有） | **Done** — header/scores/`?space_id=` |

### P1 · 第一条外部卡片通道（验证「对接」）

| 建议 ID | 内容 | 验收 |
|---------|------|------|
| E4 | Hub 展柜 stub：走近 + F → 打开配置的 Space/卡片 URL（新标签或 iframe 壳） | **Done** — stub 页可回 Hub |
| E5 | 展柜元数据契约 v0（JSON：id、title、url、kind=pms_space） | **Done** 薄 — `examples/hub/exhibits.v0.json` |

### P2 · 本仓传送门主体加深（飞轮）

| 建议 ID | 内容 | 备注 |
|---------|------|------|
| W1 | 工坊推箱/抓取 smoke 恢复（双 prop：crate stow + block grasp） | 训练场数据价值 | **Done** |
| R3 | 3D 离线回放 | 运营与「我的」完整性 |
| — | 关节/接触任务继续加深 | 服从 [15](15-course-correction.md) / [16](16-value-sprint.md) |

### P3 · Hub 空间慢扩（可后置）

| 建议 ID | 内容 | 备注 |
|---------|------|------|
| H8 | 电梯/L2 瞬移薄版 | **Done** |
| H9 | Party board / Vendor 薄交互 | **Done** |
| H10 | 房间壳：展厅 / 教室走廊占位 + lore | **Done** |
| H11 | 竞技场门占位（1v1 / 多人） | 权威模型另案；勿与 PMS 卡片混用 |

### 明确暂缓

- 公网 HTTPS/wss 大张旗鼓（跟统一身份反代一起）  
- 在 Gateway 内嵌 Gazebo / 高斯 / VLA 训练编排  
- 真机透传公网演示（安全与运维未就绪前）

---

## 7. 与既有文档关系

| 文档 | 关系 |
|------|------|
| [00](00-vision.md) | 愿景补「生态前台」一句；双引擎诉求不变 |
| [18](18-hub-dungeon.md) | Hub 几何与门 A–E；外部通道挂在门/展柜上 |
| [20](20-platform-portal.md) | 本仓身份/积分；E2 升级为对接平台账号 |
| [15](15-course-correction.md) | 仍禁止演示超前于数据；对接展柜不算「堆 city 皮」 |
