# 34 · PaperMC Minecraft 快速部署方案（playground 同机）

| 字段 | 值 |
|------|-----|
| **状态** | Proposal · 方案记录（用户提供） |
| **创建** | 2026-08-15 |
| **目标机** | 现网腾讯 CVM 2C8G（playground 链路后端，`mineworld-web`/`mineworld-gateway` 同机） |
| **范围** | PaperMC Java 服务端 Docker 化快速拉起；Hub「传送门对面世界」的 PoC |
| **关联** | [23-public-deploy.md](23-public-deploy.md) · [30-playground-neighbour-routes.md](30-playground-neighbour-routes.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) |
| **非目标** | MineWorld 内嵌 Minecraft 客户端；MC 数据进 MuJoCo；公网大流量生产服 |

> 本文记录「快速拉起一台 PaperMC」的最短路径 + 接入 MineWorld 的可行性评估。  
> 实施在 CVM 上执行；本仓只存方案与入口元数据。

---

## 0. 基础准备：Docker 镜像加速器

编辑 `/etc/docker/daemon.json`：

```json
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://docker.xuanyuan.me"
  ]
}
```

```bash
sudo systemctl daemon-reload && sudo systemctl restart docker
```

阿里云机器建议用控制台专属加速地址（更稳）。

## 1. 方案一：轩辕镜像直拉 PaperMC（最短）

```bash
# 一行命令
docker run -it -d -p 25565:25565 --name papermc \
  -e MINECRAFT_EULA=true docker.xuanyuan.run/endkind/papermc:latest

# 推荐：数据卷持久化 + 3GB 内存上限 + 自动重启
docker volume create papermc-data
docker run -it -d -p 25565:25565 --name papermc \
  -v papermc-data:/data -e MAX_RAM=3G -e MINECRAFT_EULA=true \
  --restart=always docker.xuanyuan.run/endkind/papermc:latest

# 指定版本
docker run -it -d -p 25565:25565 --name papermc \
  -e MINECRAFT_EULA=true docker.xuanyuan.run/endkind/papermc:1.20.1
```

## 2. 方案二：itzg/minecraft-server 通用镜像（可扩展）

`docker-compose.yml`：

```yaml
services:
  papermc:
    image: docker.xuanyuan.run/itzg/minecraft-server:java21
    container_name: papermc
    restart: unless-stopped
    ports:
      - "25565:25565/tcp"
    environment:
      TZ: Asia/Shanghai
      TYPE: PAPER
      EULA: "TRUE"
      MEMORY: "3G"
      MAX_PLAYERS: 20
      VIEW_DISTANCE: 10
    volumes:
      - ./data:/data
```

```bash
docker-compose up -d
# 或 docker run 版：
docker run -d -p 25565:25565 --name mc -v mc-data:/data \
  -e TYPE=PAPER -e EULA=TRUE -e MEMORY=3G \
  docker.xuanyuan.run/itzg/minecraft-server:latest
```

**关键环境变量**：`EULA=TRUE`（必填）、`TYPE=PAPER`（itzg 镜像选型）、`MEMORY/MAX_RAM=3G`。

## 3. 拉起后的收尾

1. **安全组 + ufw 放行 25565/tcp**（playground 链路 ALB→WireGuard 只转 HTTPS/WS，MC Java 协议需在 CVM 直接暴露 25565，或另配端口映射）。
2. 配置在挂载的 `./data` 或 `papermc-data` 卷（`server.properties` 按需改）。
3. 客户端：Minecraft Java 版输入 `CVM_IP:25565` 连接。

## 4. 接入 MineWorld 的可行性评估

### 4.1 部署可行性（同机 2C8G）

| 项 | 判断 | 说明 |
|----|------|------|
| 内存 | **要算账** | MC Paper 常驻 ~2.5–3.5G；CVM 8G 上还有 web/gateway/MuJoCo（工坊 MuJoCo 按需）。Demo 期可行；`MAX_RAM=3G` 必须设死 |
| CPU | 中 | 区块生成/实体 tick 吃单核；与 MuJoCo 工坊并发时会互抢，建议 `VIEW_DISTANCE≤10`、`MAX_PLAYERS≤20` |
| 网络 | **需开口** | playground 公网链路只转 443/wss；25565 要在腾讯安全组单独放行（CVM 公网 IP 直连），不经过 AWS ALB |
| 磁盘 | 低 | 世界存档几 GB 起步；注意 `recordings/` 与 MC data 都要清盘纪律 |
| 部署方式 | **用方案一** | 最小依赖；compose 版留作后续插件化 |

结论：**同机可起，限参数跑 Demo 无压力**；玩家数上去或要开 mod 时，应迁独立小机。

### 4.2 产品接入可行性（Hub 传送门对面世界）

| 设想 | 判定 | 理由 |
|------|------|------|
| Hub 里「进 MC 世界」= 浏览器内玩 | ❌ | MC Java 协议无法在浏览器跑；需 Java 客户端 |
| Hub 传送门/展柜 → 打开连接指引（IP/版本/二维码） | ✅ | TYPE B 外部卡片，同 PMS Space 逻辑：Hub 只做入口与叙事 |
| Portal 卡片挂 MC 状态（在线人数/ping） | ✅ 小改 | MC 有标准 status ping 协议；Platform 可探活 |
| 身份打通（MW 账号 ↔ MC 白名单） | ✅ 后期 | Paper 插件接 `mw_platform` API（`player_id` → whitelist），不阻塞 PoC |
| MC 世界数据进 MuJoCo/IL | ❌ | 纯外部世界，物理/采数不参与 |

**推荐接法**：Hub 新增一扇「MC 星门」或北翼展柜，F 打开 `/portal/mc_card.html`（服务器地址 + 一键复制 + 在线状态 + 客户端要求说明）。与 E4 展柜同一元数据契约，一条 `kind: "minecraft"` 即可。

### 4.3 分期建议

| 期 | 内容 | 验收 |
|----|------|------|
| **M0 PoC** | CVM 上方案一拉起 25565；本机客户端能连 | 朋友可从外网进服 |
| **M1 入口** | Hub 门/展柜 + Portal MC 卡片（地址/在线状态） | 从 Hub 能找到并复制地址 |
| **M2 身份** | Paper 插件按 MineWorld 登录做白名单/昵称同步 | 仅注册用户可进 |
| **M3 联动**（可选） | MC 服事件回传 Platform 积分（成就→points） | 明确定义后再做 |

**红线**：MC 不进 MuJoCo / 不进 Gateway WS；浏览器侧只做「入口卡片」，不做网页 MC 客户端。

---

## 5. 给下一任 Agent 的提示词（实施用）

```text
在腾讯 CVM（playground 后端机，2C8G）部署 PaperMC：
1) 配置 /etc/docker/daemon.json registry-mirrors（docs/34 §0），重启 docker。
2) 用 docs/34 §1「推荐部署」命令起 papermc（卷 papermc-data、MAX_RAM=3G、EULA、--restart=always）。
3) 安全组放行 25565/tcp（仅 MC；不要动 443/8765 现有规则）。
4) 本机客户端验证连接；docker logs papermc 确认 Done。
5) 回 MineWorld 仓库：docs/09-todo.md 勾 M0；后续 M1 做 Hub/Portal 入口卡片。
```
