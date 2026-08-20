# 36 · Luanti 自托管（coolje00 · 不动 papermc）

| 字段 | 值 |
|------|-----|
| **状态** | **已上机 coolje00**（2026-08-18） |
| **日期** | 2026-08-18 |
| **目标机** | 阿里云轻量 `coolje00`（`120.27.200.203`）。**不要**再往 tencentsh / papermc 同机塞。 |
| **compose** | `/opt/luanti` 现网；仓库草稿 [ops/luanti/](../ops/luanti/) |
| **游戏包** | VoxeLibre **0.91.2**（勿用 master，会与 linuxserver 5.17-dev 崩） |
| **对照** | [34-papermc-minecraft.md](34-papermc-minecraft.md) |
| **非目标** | 改 papermc 容器/卷/安全组 25565；Luanti 进 MuJoCo / Gateway WS |

> 2026-08-18 已在 coolje00 `docker compose up`。外网还差阿里云轻量 **防火墙放行 UDP 30000**。

## 0. 现网习惯（对齐，不复用 papermc）

| 现网 | 做法 | Luanti 对齐 |
|------|------|-------------|
| papermc | `docker run` + 命名卷 `papermc-data` + 默认 `bridge` + `restart=unless-stopped` + 镜像走 `docker.m.daocloud.io` | **独立** compose 项目 `luanti`、命名卷 `luanti-data`、同 bridge、同 restart、同 daocloud 前缀 |
| rustdesk | bind `/opt/rustdesk-server/data`、`network_mode: host` | 目录放 `/opt/luanti`；**不用 host 网络**（与 papermc 一致，只映射 30000/udp） |
| papermc 环境 | `TZ=Asia/Shanghai`、`UID/GID=1000` | `TZ` + linuxserver `PUID/PGID=1000` |
| 防火墙 | ufw inactive；开口靠腾讯安全组（25565/tcp 已放） | **另开 30000/udp**；不改 25565 规则 |

镜像用 `linuxserver/luanti`（Docker Hub，走现有 daemon.json 加速）。游戏包 **VoxeLibre** 需另行放进卷内 `games/voxelibre/`（镜像不再自带 minetest_game）。

## 1. 上机步骤（尚未执行）

在 **tencentsh**，与 papermc 无关的新目录：

```bash
sudo mkdir -p /opt/luanti/config
# 把本仓 ops/luanti/compose.yml 与 config/minetest.conf 拷到 /opt/luanti/
cd /opt/luanti

# 1) 只拉镜像，确认不碰 papermc
sudo docker pull docker.m.daocloud.io/linuxserver/luanti:latest

# 2) 先起一次以创建命名卷，再装游戏包，再正式 up
sudo docker compose up -d
sudo docker compose down

vol=/var/lib/docker/volumes/luanti-data/_data
sudo mkdir -p "$vol/games"
sudo git clone --depth 1 https://git.minetest.land/VoxeLibre/VoxeLibre "$vol/games/voxelibre"
sudo chown -R 1000:1000 "$vol"

sudo docker compose up -d
sudo docker logs -f luanti   # 等到 listening / world 就绪
```

腾讯安全组：**新增** `UDP:30000`（建议源 IP 收紧到好友网段）。**不要**改 `TCP:25565`。

客户端：安装 [Luanti](https://www.luanti.org/downloads/)（版本尽量与镜像 tag 一致）→ 加入服务器 `106.54.168.31:30000`（UDP）。首次进入会注册账号；`disallow_empty_password=true`。

回滚（仍不动 papermc）：

```bash
cd /opt/luanti && sudo docker compose down
# 可选：sudo docker volume rm luanti-data
# 安全组删 30000/udp
```

## 2. 变更影响范围（上机前必读）

### 2.1 明确不改（红线）

| 对象 | 动作 |
|------|------|
| 容器 `papermc` | 不 stop / 不 recreate / 不改 env |
| 卷 `papermc-data` | 不挂到 Luanti、不备份覆盖 |
| 端口 `25565/tcp` | 不占用、不改安全组该项 |
| rustdesk `hbbs`/`hbbr` | 不改 host 网络与 21115–21117 |
| `/opt/mineworld`、g1-sim-gateway、WireGuard/ALB | 不改 |
| MineWorld 代码/Gateway WS | 不接入 |

compose 项目名 `luanti`、容器名 `luanti`、卷名 `luanti-data`，与 `papermc` 无 `depends_on`、无共用 network。

### 2.2 会动的（仅在执行 §1 之后）

| 层 | 变化 | 风险 |
|----|------|------|
| Docker | 新镜像 ~100–200MB；新容器 `luanti`；新卷 `luanti-data` | 拉镜像占磁盘；`docker restart` 全局不影响已运行容器，但 **勿** `systemctl restart docker`（会短暂打断 papermc / rustdesk） |
| 端口 | 宿主机 `0.0.0.0:30000/udp` → 容器 | 与现网监听无冲突（现仅 25565/tcp + rustdesk 21115–21117） |
| 安全组 | 需新增 30000/udp | 暴露面 +1；公开列表已关（`server_announce=false`），仍可能被扫 UDP |
| 内存 | compose `mem_limit: 512m` | 现网 available ≈ **2.5Gi**；Paper 已 RSS ~3.1G，g1-sim ~1.0G。512M 上限可塞，但 **峰值生成区块时** 与 Paper/MuJoCo 抢 CPU |
| CPU | `cpus: 0.50`（2 核里半核） | 降低对 papermc tick / mineworld gateway 的抢核；人多仍会卡 |
| 磁盘 | 盘 **50G / 已用 84% / 剩余 ~7.6G** | VoxeLibre clone + 世界图会再吃几百 MB～数 GB。**这是最大硬约束**。上机前先 `docker image prune` 或确认 ≥3G 余量 |
| 运维 | 多一个 compose 项目 | `docker ps` 会多一行；日志 json-file 10m×3 |

### 2.3 同机资源账（2026-08-18 采样）

| 进程 | RSS 量级 |
|------|----------|
| papermc Java `-Xmx3G` | ~3.1G |
| g1-sim-gateway uvicorn | ~1.0G |
| mineworld `echo_server` + ai_driver + web | ~0.1G |
| 系统/云镜等 | ~0.5G+ |
| **可用** | **~2.5G** |
| Luanti 预算 | **硬顶 512M** |

结论：Demo 级 2–6 人可同机；**不要**去掉 `mem_limit`。若 Paper 与 Luanti 同时高峰，优先停 Luanti，保 playground。

### 2.4 产品/玩家面

- Paper 玩家：无感（协议、白名单、版本均不变）。
- Luanti 玩家：新客户端、新端口、新账号（与 MC 离线名 **不** 自动打通）。
- Hub/Portal：本稿不做星门卡片（对照 34 的 M1，Luanti 若要入口另开切片）。

### 2.5 失败模式

| 现象 | 处理 |
|------|------|
| 镜像拉不下来 | 只影响新项目；papermc 继续跑。可改 tag 或换 `ghcr.io/luanti-org/luanti`（官方，UID 30000，卷布局不同，需改 compose） |
| `gameid voxelibre` 起不来 | 多半没 clone 到 `games/voxelibre`；`compose down` 后补目录，勿重建 papermc |
| 外网连不上 | 查安全组是否 **UDP**（不是 TCP）30000 |
| 机器开始 swap/OOM | 无 swap。先 `docker compose -f /opt/luanti/compose.yml down`，不要去重启 papermc |
| 磁盘爆 | 删 Luanti 卷/镜像；**禁止** 清理 `papermc-data` |

## 3. 给实施 Agent 的提示词

```text
在 tencentsh 按 docs/36 部署 Luanti：拷 ops/luanti 到 /opt/luanti；
只 docker compose up 项目 luanti；clone VoxeLibre 进卷 luanti-data；
安全组只加 30000/udp。禁止 stop/recreate papermc，禁止动 papermc-data 与 25565。
若内存/磁盘不够则 abort 并 down luanti。
```
