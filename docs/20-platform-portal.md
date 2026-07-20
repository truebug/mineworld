# 20 · 平台门户 · 身份 · 积分 · 管理台（规划）

| 字段 | 值 |
|------|-----|
| **状态** | Planning · **Phase A v0 已落地**（SQLite + Portal 登录） |
| **日期** | 2026-07-20 |
| **关联** | [09](09-todo.md) · [18](18-hub-dungeon.md) · [19](19-changelog.md) · [04](04-data-collection.md) · [13](13-web-multiplayer-demo.md) |
| **原则** | Gateway WS 仍只管仿真权威位姿；身份 / 积分 / 排行 / 运营走独立 HTTP API + DB |

> **结论**：现在就把这条产品线写进计划是合适的——POC 管道与 3D Hub 已够用；再堆大厅观感收益递减。  
> **但**必须分期：先「身份 + API + 最小后台」，再「积分/排行」，再「玩家页与回放统一」，避免一次做完账号 SaaS。

---

## 1. 目标用户旅程（冻结方向）

```text
Portal 登录（唯一 player_id）
  → 进入 3D Hub（多人互见，不录 IL）
  → 大门分流
       ├─ A 工坊（单人 · 臂爪 · 准确率/任务 outcome → 积分）
       └─ B 训练场/竞速（多人 · 速度/名次 → 积分）
  → 回 Hub；大厅可见排行榜
  → Portal「我的」：战绩 / 积分明细 / 回放自己的会话
  → Admin：玩家、会话、回放与导出（IL 轨迹）
```

与现网对齐：Hub = `demo_hub`；A = `demo_workshop`；B = `demo_city`（竞速规则与积分公式后定）。

---

## 2. 能力地图（对应你的 5 点）

| # | 能力 | 说明 | 依赖 |
|---|------|------|------|
| 1 | 独立 Portal + Admin + API + DB/MQ | 与 Godot 导出、Gateway 进程分离；配置驱动存储 | PL1–PL4 |
| 2 | 登录 → Hub → 单人/多人关 → 计分 | 唯一 `player_id`；注册 / 后台导入 / 外部同步三选一先做最小集 | ID · SC |
| 3 | Hub 积分排行榜 | 大厅 UI（3D 板或 DOM）；维度待定（总分 / 周榜 / 分关） | SC · LB |
| 4 | 玩家详情页 | 积分、战绩、会话列表、回放入口（复用现有 recordings 能力） | ME · REC |
| 5 | 后台看玩家 + 回放/导出 | 运营只读为主；导出不改 `header.json`+`frames.jsonl` 语义 | AD · EXP |

---

## 3. 身份策略（建议）

| 阶段 | 做法 | 备注 |
|------|------|------|
| **v0** | Admin 手工创建 / CSV 导入 `player_id` + 显示名；Portal 用 id+口令或一次性 token 登录 | 最快打通「登录才进 Hub」 |
| **v1** | Portal 简单自助注册（邮箱或昵称+口令） | 仍无 OAuth |
| **v2** | 外部 IdP / 组织目录同步 | 教育/企业场景 |

铁律：`player_id` 全局唯一；与现有 `localStorage.mw_profile.id` 迁移策略写清（登录后覆盖本地 guest）。

---

## 4. 架构边界（不破坏现网）

| 层 | 职责 | 不做 |
|----|------|------|
| **Godot Web** | 关卡、Hub、遥操、本机回放壳 | 权威积分、用户库 |
| **Gateway WS** | join / cmd / state / 录制落盘 | 登录会话、排行查询 |
| **API 服务** | 鉴权、玩家、积分写入、排行、录制索引、导出任务 | 仿真步进、双写位姿 |
| **DB** | players / sessions / scores / recording_index | 存全量 frames（仍 FS/对象存储） |
| **MQ（可选）** | 异步导出、积分结算事件 | 实时控制通道 |

本地默认：**SQLite + 无 MQ（进程内队列）**；生产可切 Postgres + Redis/NATS（PL4）。  
v0 实现：`mw_platform/` + `/api/platform/*`（同端口 8080 或独立 `:8090`）；`MW_PLATFORM_DB_URL` 换库。

### Phase A v0（2026-07-20 已落地）

| 项 | 路径 |
|----|------|
| API 包 | `mw_platform/`（`PlayerStore` 抽象 + `SQLitePlayerStore`） |
| 独立进程 | `mw_platform/api_server.py` |
| 同域挂载 | `scripts/serve_web_demo.py` → `/api/platform/*` |
| Portal | `godot/spike/web/portal/login.html` → `dist/web/portal/` |
| 游戏门禁 | `shell.html` · `MW_ENSURE_AUTH`（`?menu=1` 与 `MW_PLATFORM_AUTH=0` 可 bypass） |
| Demo 账号 | `demo` / `demo`（首次启动自动 seed） |
| Smoke | `scripts/platform_smoke.py` |

Admin 创建玩家（需 `MW_PLATFORM_ADMIN_KEY`）：

```bash
curl -X POST http://127.0.0.1:8080/api/platform/admin/players \
  -H 'Content-Type: application/json' \
  -H "X-Admin-Key: $MW_PLATFORM_ADMIN_KEY" \
  -d '{"player_id":"alice","display_name":"Alice","password":"secret"}'
```

---

## 5. 分期切片（写入 Todo 的 ID）

### Phase A — 平台底座（先做）

| ID | 内容 | 验收 |
|----|------|------|
| **PL1** | 独立 API 进程 + 可配置 DB | 健康检查；players CRUD；与 Gateway 同机可跑 |
| **PL4** | 配置 SSOT | env 切 SQLite/Postgres；零依赖本地默认 |
| **PL3** | 边界文档 | WS vs HTTP 表；禁止双写位姿 |
| **ID1** | Portal 登录页 | 未登录不可进 `/` 游戏；登录后带 token 进 Hub |
| **ID2** | Admin 创建/导入玩家 | 表单或 CSV；生成 `player_id` |
| **AD1** | Admin 壳 | 登录、玩家列表、基础健康 |

### Phase B — 计分与大厅

| ID | 内容 | 验收 |
|----|------|------|
| **SC1** | 积分模型 v0 | 工坊 outcome + 城市通关时间 → 分数公式文档化 |
| **SC2** | Gateway/录制挂钩 | 通关/结束时 API 记账（session → score）；失败可重试幂等 |
| **LB1** | Hub 排行榜 | 大厅可见 Top N（DOM 或 Label3D 板） |
| **H9b** | 排行榜交互台 | 可与 H9 Party board 合并 |

### Phase C — 玩家与运营回放

| ID | 内容 | 验收 |
|----|------|------|
| **ME1** | Portal「我的」页 | 积分、战绩表、会话列表 |
| **ME2** | 自助回放 | 跳转现有 `/?replay=` 或 recordings 播放器 |
| **AD2** | Admin 会话/玩家钻取 | 按 player 筛录制 |
| **EXP1** | 导出 | 批量轨迹导出（复用 `export_trajectories` 语义） |
| **PL2** | Admin 增强 | 在线房只读、契约开关等运维项 |

### 明确后置

- 完整 OAuth / 计费 / 商城 / 换装  
- 排行榜反作弊与段位系统  
- 实时观战平台化（可先用人在同房）

---

## 6. 与 Now 的关系

| 线 | 建议 |
|----|------|
| **P1a/P1b**（真抓取 / BC） | **可并行**：数据价值不依赖 Portal；工坊计分可先用 outcome |
| **Hub 观感 H7/H8** | 降优先；排行榜比电梯更有产品意义 |
| **公网 W2** | 跟 Phase A 的 HTTPS/反向代理一起做 |

推荐节奏：**Phase A v0 已落地** → 下一步 **SC1→SC2→LB1**（计分模型 → 通关记账 → Hub 排行）；P1 可并行、不阻塞。

---

## 7. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-20 | 初版：门户/身份/积分/排行/玩家页/Admin 五块能力与分期 |
