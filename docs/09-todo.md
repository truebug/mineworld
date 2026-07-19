# 09 · 待办清单（Todo）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-19 |
| **仓库** | https://github.com/truebug/mineworld |
| **目标** | MVP 可玩闭环已通；**下一主线：Web 导出 → 线上可部署 → 多人 Demo** |
| **架构讨论** | [11-poc-mvp-architecture.md](11-poc-mvp-architecture.md) |
| **Web/多人路线** | [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) |
| **阶段评审** | [12-status-review.md](12-status-review.md) |

勾选约定：`[ ]` 未做 · `[x]` 完成 · `[-]` 取消 · `[~]` 暂缓

---

## Now（W1 · 本地 Web 单人 Demo）

> POC M1–M4 与 macOS 导出管线已入库。T2.7 手感 **暂缓**。  
> **当前唯一主线**：Web 导出 + 本机带 COOP/COEP 托管跑通单人闭环。详见 [13](13-web-multiplayer-demo.md)。

| ID | 任务 | 验收 | 状态 |
|----|------|------|------|
| W1.1 | 安装与编辑器同版本的 **Web** 导出模板 | 管理器已安装 Web | [ ]（本机操作） |
| W1.2 | `bash scripts/export_godot.sh web` | `dist/web/index.html` | [ ] |
| W1.3 | `python scripts/serve_web_demo.py` | http://127.0.0.1:8080/ 可开 | [ ] |
| W1.4 | Gateway + 浏览器遥操到终点 | HUD SUCCESS / objective 事件 | [ ] |

```bash
bash scripts/export_godot.sh web
.venv/bin/python gateway/echo_server.py
.venv/bin/python scripts/serve_web_demo.py
```

---

## Next（W2–W3 · 线上与多人）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| W2.1 | HTTPS 静态托管 Web 包 | CDN / Nginx | [ ] |
| W2.2 | `wss://` 反代 Gateway | 禁止公网裸 ws | [ ] |
| W2.3 | **一会话一 MjData**（或多进程） | 多标签互不踩仿真；多人前置 | [ ] |
| W2.4 | 一页运维/安全说明 | 限流、绑定、演示密钥 | [ ] |
| W3.1 | 同关多实体 / 观战最小 | 控制权仲裁 | [ ] |
| W3.2 | 客户端多傀儡 | 按 entity_id | [ ] |
| W3.3 | 房间码 / room_id | 可先固定 demo 房 | [ ] |

---

## 暂缓

| ID | 任务 | 状态 |
|----|------|------|
| T2.7 | 输入延迟补偿 v0 | [~] 手感暂缓；W1 通后再排 |
| T2.6 | 传感器 joints 出口 | [~] 非 Web/多人阻塞 |

---

## Done（POC 基线，摘要）

| 里程碑 | 状态 |
|--------|------|
| M1 连通 · M2 真物理 · M3 录制 · M4 可玩闭环 | [x] |
| T3.4 macOS 导出管线 | [x] |
| Web preset + `export_godot.sh web` + `serve_web_demo.py` + Gateway URL 注入 | [x] 管线就绪；W1.1–W1.4 待本机验收 |

详细历史勾选见 git 历史与 [12](12-status-review.md)；完整旧表已收敛，避免双源。

---

## Later（原 Phase 4 余项）

| ID | 任务 | 备注 | 状态 |
|----|------|------|------|
| T3.2 | 开环重放增强 | `replay_xy` 已覆盖轨迹 | [ ] |
| T3.3\* | tutorial_02 资产/场景 | 已完成大半；终点随 T3.1 | 见历史 |
| T4.1 | Worker 池 | 与 W2.3 对齐 | [ ] |
| T4.2 | 契约从 `.tscn` 导出插件 | [ ] |
| T4.4 / T4.5 | 评测 API / AI 同通道 | [ ] |
| T4.6 | 动态可交互物 L1 | [ ] |

---

## 明确不做（近期）

- 在未完成 W2.3 前宣称「线上多人已可用」
- 账号 / 计费 / 编辑器 SaaS
- 用引擎 Multiplayer 同步 MuJoCo 位姿
- 恢复优先排期 T2.7（除非 Web Demo 已对外）
