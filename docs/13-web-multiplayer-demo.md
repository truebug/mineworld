# 13 · Web 导出与线上多人 Demo 路线（审核）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **目标态** | 浏览器可打开的线上 Demo：多人可进入、各自/共享会话遥操、Gateway + 真物理权威 |
| **关联** | [09-todo](09-todo.md) · [08-modes-roadmap](08-modes-roadmap.md) · [adr/003](adr/003-client-engine-godot.md) · [12-status-review](12-status-review.md) |

> 手感项（T2.7）**暂缓**。当前主线改为 **Web 交付 → 可部署 → 可多人**。

---

## 1. 目标澄清

| 说法 | 含义（本仓库约定） |
|------|-------------------|
| **Web 版** | Godot `--export-release Web` → 静态资源（`index.html` + wasm/pck） |
| **线上 Demo** | 静态站可公网访问 + Gateway 可被浏览器以 `wss://` 连上 |
| **可多人进入使用** | ≥2 名玩家同时在线；每人有独立会话或同关卡多机甲（见 §3 分期） |

**不是**：账号体系、匹配大厅、商业计费（仍属 Out of Scope，可后挂）。

---

## 2. 现状审核（相对目标态）

| 能力 | 现状 | 距目标缺口 |
|------|------|------------|
| 单机可玩闭环 M4 | ✅ Godot + Gateway + 录制 + 终点 | — |
| macOS 导出 | ✅ preset + `export_godot.sh macos` | 非主交付 |
| **Web 导出** | ✅ preset + 单线程导出 + `serve_web_demo.py`；浏览器键盘桥已通 | CI 出包可选；手感 T2.7 仍暂缓 |
| Gateway 绑定 | 默认 `127.0.0.1`（安全默认） | 公网需反代 `wss` + 显式 `--host` |
| 浏览器连 Gateway | 客户端可读 `window.MINEWORLD_GATEWAY` | 生产必须 `wss://` 同源/CORS 策略 |
| 多连接 | WS 可多连，但 **共用一个 `MjData`** | **不能**当真多人同仿真 |
| 多机甲同关 | 契约可写多 spawn；客户端只渲染一台 | 缺多傀儡 + 控制权仲裁 |
| TLS / 域名 / CDN | 无 | 线上硬前置 |
| 水平扩展 | 无 Worker 池 | T4.1 |

**结论**：W1 本地 Web 单人已通。**公网多人**必须先做 **一会话一仿真**（W2.3），再谈同世界多人（W3）。不可把「能开两个浏览器标签」误当成多人已完成。

---

## 3. 分期计划（建议执行序）

```text
W1  本地 Web 单人     →  浏览器 + 本机 Gateway
W2  可部署单人/多会话 →  静态站 + wss Gateway；会话隔离 MjData
W3  同关多人最小      →  多机甲或观战；控制权；简单大厅
W4  线上 Demo 加固    →  限流、录制分区、监控、短链分享
```

### W1 — 本地 Web 单人（Done · 2026-07-19）

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W1.1 | 安装 Godot **Web** 导出模板（与编辑器同版本） | 管理器「已安装模板」含 Web | [x] |
| W1.2 | `bash scripts/export_godot.sh web` | `dist/web/index.html` 存在 | [x] |
| W1.3 | `python scripts/serve_web_demo.py`（COOP/COEP） | 浏览器打开可进场景 | [x] |
| W1.4 | Gateway + 页面内遥操（含键盘桥 / entity_id） | 位姿跟 state；可到终点 | [x] |

**命令摘要**：

```bash
# 模板：Editor → 管理导出模板 → 勾选 Web → 安装
bash scripts/export_godot.sh web
.venv/bin/python gateway/echo_server.py          # 终端 1
.venv/bin/python scripts/serve_web_demo.py        # 终端 2 → http://127.0.0.1:8080/
```

可选覆盖 Gateway 地址（页面控制台或托管页注入）：

```html
<script>window.MINEWORLD_GATEWAY = "ws://127.0.0.1:8765";</script>
```

### W2 — 可部署（多会话隔离）

| ID | 任务 | 验收 |
|----|------|------|
| W2.1 | 静态资源上 CDN/对象存储或 Nginx | HTTPS 可打开 |
| W2.2 | Gateway 反代 `wss://demo.example/ws` | 浏览器跨机可连 |
| W2.3 | **一 `session` 一 `MjData`（或一进程）** | 两标签互不踩位姿 |
| W2.4 | 文档：防火墙、仅演示密钥/IP allow（最小） | 有一页运维说明 |

### W3 — 同关多人最小

| ID | 任务 | 验收 |
|----|------|------|
| W3.1 | 控制权：每会话一可控机甲；其余观战或第二 spawn | 两人互见对方傀儡 |
| W3.2 | `state` 广播含多实体 | 客户端按 `entity_id` 多傀儡 |
| W3.3 | 简单房间码 / `join` 带 `room_id`（可先写死 demo 房） | 两人进同一逻辑房间 |

### W4 — 加固

限连、idle 踢出、录制按房间目录、基础指标、短链落地页。

---

## 4. 架构约束（线上也不可破）

1. 浏览器 **不**做机甲权威物理；只发 `cmd`、收 `state`。  
2. 录制仍在 Gateway。  
3. 公网 **禁止**裸奔无 TLS 的 `ws://`（本地除外）。  
4. Godot Web 线程版托管必须带 **COOP/COEP**（`serve_web_demo.py` 已示范）。  
5. ADR-003：Web 包体与浏览器限制已知；Demo 可接受「稍重」，不先做 PWA 商店分发。

---

## 5. 风险与建议

| 风险 | 建议 |
|------|------|
| 误以为多标签 = 多人 | W2.3 完成前对外只称「Web 单人 Demo」 |
| 共享 `MjData` 数据竞争 | 排期最高优先于美术/新关 |
| 浏览器混合内容 | 页面 HTTPS 则 Gateway 必须 wss |
| 导出模板版本漂移 | 锁定 4.7.1（或团队统一版）写入 README |
| 手感/延迟（T2.7） | **暂缓**；先通链路再调 |

---

## 6. 文档与脚本清单（本迭代）

| 路径 | 作用 |
|------|------|
| `godot/spike/export_presets.cfg` | preset `macOS` + **`Web`** |
| `scripts/export_godot.sh [web\|macos]` | 默认 **web** |
| `scripts/serve_web_demo.py` | 本地静态 + COOP/COEP |
| `godot/spike/scripts/main.gd` | `gateway_url` + `window.MINEWORLD_GATEWAY` |
| `docs/09-todo.md` | Now = W1；T2.7 暂缓 |
| 本文 | 目标、分期、审核 |

---

## 7. 对外话术（建议）

- **现在**：「本地浏览器 Demo（单人），需本机 Gateway。」  
- **W2 后**：「线上单人/多会话 Demo，每人独立仿真。」  
- **W3 后**：「线上同关多人（最小）。」

未到阶段不提前承诺「开房间乱斗」。
