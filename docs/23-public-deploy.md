# 23 · 公网部署实施建议书（W2 · databall.cloud）

| 字段 | 值 |
|------|-----|
| **状态** | Proposal · **后置**（现网 Demo 已另通 playground） |
| **日期** | 2026-07-21 · 续记 2026-07-22 |
| **目标机** | 腾讯云 CVM **2C8G** · 域名 **databall.cloud**（ICP 已备） |
| **范围** | W2.1 静态 HTTPS · W2.2 `wss` 反代 · W2.4 最小运维说明 |
| **关联** | [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) · [20-platform-portal.md](20-platform-portal.md) · [09-todo.md](09-todo.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) |
| **非目标** | K8s / Worker 池（T4.1）/ 真机公网透传 / 多机 MuJoCo 农场 |

> **现网公网（已验收，不走本文拓扑）**：`playground.dev.databall.tech`  
> `浏览器 → AWS ALB → WGateway → WireGuard → 腾讯 CVM`（`mineworld-web` / `mineworld-gateway`；`wss://…/ws`）。  
> 本文是 **`databall.cloud` ICP 品牌域名** 的单机 Caddy 方案；**不阻塞** Phase A（A1–A3）。  
> 铁律：页面 HTTPS ⇒ Gateway 必须 **wss**；Gateway/Admin **只绑 127.0.0.1**，TLS 终结在反代。

---

## 1. 结论（可行性）

| 判断 | 说明 |
|------|------|
| **可行** | 本机 Web + Portal + Gateway + Platform 链路已通；公网差 TLS、同域反代、注入 `MINEWORLD_GATEWAY` |
| **2C8G 够用** | **非仿真**（静态 / Portal / Hub FakeMech / SQLite）资源需求低 |
| **真正吃 CPU 的** | Workshop / City **MuJoCo** 多房并行；公网初期应限房或默认 fake |
| **扩张顺序** | 先通链路 → 再限流/清盘 → 再 COS+CDN → 再考虑第二台仿真机 |

---

## 2. 目标拓扑（单机 · KISS）

```text
浏览器
  │  https://databall.cloud
  ▼
Caddy（或 Nginx）:443  ← Let's Encrypt
  ├─ / , /portal/ , Godot Web     → 127.0.0.1:8080  (serve_web_demo.py，COOP/COEP)
  ├─ /api/platform/*              → 同 :8080（已挂载）或 mw_platform:8090
  ├─ /api/recordings/*            → 同 :8080
  ├─ /api/gateway/*               → 127.0.0.1:8770  (可选；建议仅内网/SSH)
  └─ /ws                          → 127.0.0.1:8765  (Gateway WebSocket)

本机进程（均 bind 127.0.0.1，除反代外）：
  · serve_web_demo.py --host 127.0.0.1 --port 8080
  · echo_server.py --host 127.0.0.1 --port 8765 [--admin-port 0 或 8770]
```

浏览器侧：

```js
window.MINEWORLD_GATEWAY = "wss://databall.cloud/ws";
```

（导出默认仍是 `ws://127.0.0.1:8765`；公网必须在 **shell / index 注入** 或由托管页覆盖。）

---

## 3. 资源预期（2C8G）

| 负载 | CPU | 内存 | 备注 |
|------|-----|------|------|
| 静态 Godot Web + Portal | 低 | 低 | 瓶颈常在 **出网带宽 / 首包** |
| Platform SQLite | 可忽略 | 可忽略 | Demo 够用；日后 `MW_PLATFORM_DB_URL` |
| Hub（FakeMech，≤8 人） | 低 | 低 | 状态广播轻 |
| Admin / recordings 只读 | 偶发 | 低 | 磁盘随 sessions 涨 |
| MuJoCo × N 私房 | **高** | 中 | **先限 N=1～2** 或公网默认 `--physics fake` |

**建议首发配置：**

- Gateway：`--physics fake` **或** mujoco 但文档写明「工坊限流」  
- Hub 对外为主；workshop/city 可开但设 `max_members` / 少开房  
- 磁盘：定期清理 `recordings/sessions/`（勿提交 git）

---

## 4. 安全基线（W2.4 最小）

1. **安全组**：仅放行 `22`（管理 IP）、`80`、`443`；**不**放行 8080/8765/8770/8090。  
2. Gateway / Admin：**`--host 127.0.0.1`**（或等价只监听 loopback）。  
3. `MW_PLATFORM_AUTH=1`；改掉默认 `demo/demo` 与 `dev-admin`（或仅内网 Admin）。  
4. Admin HTTP（`:8770`）：公网阶段优先 **SSH 隧道**，不要裸反代；若反代必须 `X-Admin-Key` + IP allow。  
5. 禁止公网裸 `ws://`（混合内容会被浏览器拦截）。  
6. 录制与 SQLite 路径放在数据盘；备份策略另定（首发可手工 `scp`）。

---

## 5. 推荐软件栈

| 组件 | 建议 | 备选 |
|------|------|------|
| 反代 + TLS | **Caddy 2**（自动 HTTPS） | Nginx + certbot |
| 运行时 | Python 3.11+ venv（与仓库一致） | — |
| 进程守护 | systemd 两个 unit（web / gateway） | `tmux` 仅调试 |
| Godot 导出 | 本机或 CI 出 Web 包后 `rsync` 到 CVM | 勿在 2C 上日常编大型场景 |

依赖安装与本地一致：

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt
# platform / mujoco 按需
```

---

## 6. Caddy 草稿（实施时粘贴后改路径）

假设仓库在 `/opt/mineworld`，静态仍由 `serve_web_demo.py` 提供（保留 COOP/COEP，少改 Nginx header）。

```caddyfile
databall.cloud {
	encode gzip

	# WebSocket → Gateway
	@ws path /ws /ws/*
	handle @ws {
		uri strip_prefix /ws
		reverse_proxy 127.0.0.1:8765
	}

	# 可选：Admin（默认注释掉）
	# handle /api/gateway/* {
	# 	uri strip_prefix /api/gateway
	# 	reverse_proxy 127.0.0.1:8770
	# }

	# 静态 + Portal + /api/platform + /api/recordings
	handle {
		reverse_proxy 127.0.0.1:8080
	}
}
```

> **注意**：Caddy 的 WebSocket 反代路径需与 Gateway 实际 path 对齐。若 Gateway 根路径即 WS，常用写法是 `wss://databall.cloud/ws` 反代到 `127.0.0.1:8765` 且 **不要错误 strip** 导致握手失败。实施 session 应先用 `websockets`/`wscat` 打通再开浏览器。  
> 若 strip 有坑：改为子域 `wss://ws.databall.cloud` → `:8765`（仍只内网监听，Caddy 对外）。

COOP/COEP：继续由 `serve_web_demo.py` 设置即可；若改为 Nginx 直接根目录静态，必须显式加：

- `Cross-Origin-Opener-Policy: same-origin`  
- `Cross-Origin-Embedder-Policy: require-corp`  
- （及现有 CORP 行为，见 `scripts/serve_web_demo.py`）

---

## 7. 环境变量清单（草案）

| 变量 | 公网建议 | 说明 |
|------|----------|------|
| `MW_PLATFORM_AUTH` | `1` | Portal 登录门 |
| `MW_PLATFORM_ADMIN_KEY` | 强随机 | Admin / Gateway score 共用勿用 `dev-admin` |
| `MW_PLATFORM_DB_URL` | `sqlite:////var/lib/mineworld/platform.sqlite` | 持久路径 |
| `MW_GATEWAY_ADMIN_KEY` | 同或分密钥 | PL2 admin HTTP |
| `MW_PLATFORM_SCORE_URL` | `http://127.0.0.1:8080/api/platform/scores` | Gateway→本机计分 |
| `MINEWORLD_GATEWAY`（页内） | `wss://databall.cloud/ws` | 注入 shell/html |

Gateway 启动示例：

```bash
.venv/bin/python gateway/echo_server.py \
  --host 127.0.0.1 --port 8765 \
  --physics fake \
  --admin-port 0 \
  --record-dir /var/lib/mineworld/recordings/sessions
```

Web：

```bash
bash scripts/serve_web.sh restart --host 127.0.0.1 --port 8080
# 需已 export Godot Web 到约定目录
```

---

## 8. 注入 `MINEWORLD_GATEWAY`（实施注意）

当前导出在 `export_presets.cfg` 默认：

```text
window.MINEWORLD_GATEWAY = window.MINEWORLD_GATEWAY || "ws://127.0.0.1:8765"
```

公网任选其一（KISS 优先上者）：

1. **托管页 / `shell.html` 先赋值** `wss://databall.cloud/ws`（推荐，免改导出）  
2. 构建时改 preset 再 `export_godot.sh web`  
3. 反代下发的小脚本 `mw_config.js` 被 index 引用  

验收：浏览器控制台 `window.MINEWORLD_GATEWAY` 为 `wss://…`，且无混合内容报错。

---

## 9. systemd 草稿（示意）

`mineworld-web.service` / `mineworld-gateway.service`：`User=` 非 root、`WorkingDirectory=/opt/mineworld`、`Restart=on-failure`。  
具体 unit 文件可在实施 PR 中添加；本建议书不强制入库 unit，避免未验证路径写死。

---

## 10. 分阶段实施清单（给下一 agent）

### Phase 0 · 准备（不改产品代码亦可）

- [ ] CVM：安全组 22/80/443；安装 Git、Python 3.11+、Caddy  
- [ ] 域名 `databall.cloud` A 记录 → CVM 公网 IP；等待解析  
- [ ] 克隆仓库到 `/opt/mineworld`（或约定路径）；venv + `pip install -r gateway/requirements.txt`  
- [ ] 本机或 CI 导出 Web 包并同步到服务器（`bash scripts/export_godot.sh web`）

### Phase 1 · 本机环回冒烟（CVM 上）

- [ ] `serve_web` + Gateway fake 仅 127.0.0.1  
- [ ] `scripts/ws_smoke_test.py`（必要时先起 gateway）  
- [ ] `scripts/platform_smoke.py` / `admin_ops_smoke.py`（admin-port 按需）

### Phase 2 · TLS + 反代（W2.1 / W2.2）

- [ ] Caddy 配置生效；`https://databall.cloud/portal/` 可开  
- [ ] 注入 `wss://databall.cloud/ws`  
- [ ] 浏览器：登录 → Enter hangar → Hub 连接成功（双标签可选）  
- [ ] 确认 COOP/COEP 下 Godot 能跑（非线程版亦按现导出验证）

### Phase 3 · 加固（W2.4）

- [ ] 改 Admin/登录默认口令；文档化重启与日志路径  
- [ ] 决定 Admin 是否公网；默认否  
- [ ] 录制目录与磁盘告警（`df -h`）  
- [ ] （可选）MuJoCo：限房文档 + `--physics mujoco` 仅内测账号

### Phase 4 · 后续扩张（非本阶段）

- 静态 → 腾讯云 COS + CDN  
- 仿真 → 第二台或限流队列（T4.1）  
- 统一身份反代与 [22](22-identity-mapping.md) 联邦打通  

---

## 11. 验收标准（定义 Done）

| ID | 验收 | 对应 |
|----|------|------|
| W2.1 | `https://databall.cloud/`（或 `/portal/`）证书有效、可进站 | 静态 HTTPS |
| W2.2 | 浏览器以 `wss://databall.cloud/…` 完成 hello→join→state | Gateway 反代 |
| W2.4 | 仓库或服务器一页运维：安全组、进程、密钥、重启、排障 | 本文 §4–§10 |
| 回归 | 公网 Hub 可走；本地 `ws_smoke` / `platform_smoke` 仍 PASS | 不破坏本机开发 |

---

## 12. 明确不做（本阶段）

- 多楼宇走廊校园几何（发现用展柜元数据，见生态文档）  
- 公网开放无限制 MuJoCo 房  
- Gateway `--host 0.0.0.0` 直出  
- 在未备 TLS 时用 `ws://` 配 HTTPS 页  

---

## 13. 给下一 session 的提示词（可复制）

```text
按 docs/23-public-deploy.md 在腾讯云 CVM（2C8G，databall.cloud）实施 W2：
Caddy HTTPS + 反代 / → :8080、/ws → Gateway :8765；
Gateway/Web 仅 127.0.0.1；注入 wss://databall.cloud/ws；
先 fake physics；Admin 默认不公网。
完成后更新 docs/09-todo.md W2 勾选与 docs/19-changelog.md。
```

---

## 14. 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-21 | 初版：单机拓扑、资源判断、Caddy/env/清单；目标 databall.cloud + 2C8G |
