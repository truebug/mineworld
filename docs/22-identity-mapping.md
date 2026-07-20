# 22 · 身份映射（E2 · player_id ↔ 平台 user）

| 字段 | 值 |
|------|-----|
| **状态** | Living · 契约草案 + stub |
| **日期** | 2026-07-21 |
| **关联** | [20-platform-portal.md](20-platform-portal.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) · [09-todo.md](09-todo.md) |

> 本仓 `player_id` 仍是积分 / 录制 / Hub profile 的 **本地 SSOT**。  
> 外部平台（RoboWeb / RoboHub / Spaces）账号通过 **issuer + external_sub** 挂到同一个 `player_id`，不把 Gateway 变成用户库。

---

## 1. 字段映射表

| 概念 | MineWorld（本仓） | 外部平台 | 备注 |
|------|-------------------|----------|------|
| 本地主键 | `player_id` | — | 全局唯一；录制 header / scores 用它 |
| 显示名 | `display_name` | profile nickname / name | 登录后可覆盖 `mw_profile` |
| 外观 | `accent` | （可选）皮肤色 | Hub 纸片人 |
| IdP 名 | `issuer` | `robohub` / `databall` / `stub` | 小写；stub 仅本地联调 |
| 外部主体 | `external_sub` | 平台 user id / UUID | 在同一 issuer 下唯一 |
| 会话 | Bearer `token`（`auth_tokens`） | 平台 session / JWT | **不**把外部 JWT 原样当 Gateway 凭证 |
| 访客 | `localStorage.mw_profile.id` | — | 未登录 guest；登录后 **覆盖** 为 `player_id` |

唯一约束：`(issuer, external_sub)` → 至多一个 `player_id`。  
一个 `player_id` 可挂多条外部链接（多平台）。

样例 JSON：[`examples/platform/identity_link.v0.json`](../examples/platform/identity_link.v0.json)。

---

## 2. 迁移策略（guest → 登录）

1. 未登录：Godot / Portal 可用 guest `mw_profile.id`（本地随机）。  
2. Portal 登录成功（口令或 federated stub）→ 以 API 返回的 `player_id` **覆盖** `mw_profile.id` / `nickname`。  
3. 通关计分 / 录制 header 只认登录态 `player_id`；guest 分不进排行（现网已如此）。  
4. 不自动合并 guest 历史录制到新账号（v0）；需要时 Admin 手工迁。

---

## 3. API stub（本仓已实现）

| 方法 | 路径 | 鉴权 | 作用 |
|------|------|------|------|
| POST | `/api/platform/login/federated` | `stub_secret` 或 `X-Gateway-Key` | stub 换本仓 Bearer；无链接则建 `fed_*` 玩家并挂链 |
| POST | `/api/platform/admin/identity-links` | `X-Admin-Key` | 把已有 `player_id` 挂到 `(issuer, external_sub)` |
| GET | `/api/platform/me` | Bearer | `player` + `identity_links[]` |

环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `MW_PLATFORM_FEDERATION_STUB_KEY` | `dev-federation` | federated stub 共享密钥 |

**不做（远期）**：真 OAuth / OIDC、校验 RoboWeb JWT、跨域 SSO cookie。  
外部真登录落地时：只换「验 JWT → 查/建 link → 发本仓 Bearer」这一层，表结构可沿用。

---

## 5. E3 · 会话归因（`space_id`）

通关 / 录制可带可选外部 Space 指针，便于跨系统战绩对齐（不改变本仓 `level_id`）：

| 字段 | 写入点 | 说明 |
|------|--------|------|
| `level_id` | 既有 | 本仓关卡 SSOT |
| `space_id` | join `extensions.mw.space_id` 或 `?space_id=` | 可空；PMS Space id |
| `route_kind` | `mineworld_level` \| `pms_space` | 默认 `mineworld_level` |

落盘：recording `header.json` · `scores.space_id` / `route_kind`。样例：[`examples/platform/session_attribution.v0.json`](../examples/platform/session_attribution.v0.json)。

---

## 6. 验收

```bash
.venv/bin/python scripts/platform_smoke.py   # 含 federated + link + space_id
```
