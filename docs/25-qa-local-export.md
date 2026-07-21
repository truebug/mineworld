# Local Web / Hub 验收清单（QA-export）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **日期** | 2026-07-21 |
| **关联** | [19-changelog](19-changelog.md) · [23-public-deploy](23-public-deploy.md) · [14-godot-mujoco-fusion](14-godot-mujoco-fusion.md) |

公网另轨见 [23](23-public-deploy.md)。本清单：本地手测 + **2026-07-21 City 三连坑教训** + 发版核对。

## 0. 启动

```bash
# 终端 A
.venv/bin/python gateway/echo_server.py --physics mujoco

# 终端 B（可选 API）
.venv/bin/python mw_platform/api_server.py

# 干净导出 + 静态（改 GDScript / 契约后务必重导）
rm -rf dist/web   # 怀疑旧包时再清 godot/spike/.godot
bash scripts/export_godot.sh web
bash scripts/serve_web.sh restart
```

浏览器：**Cmd+Shift+R** 硬刷新（`index.pck` 易被缓存）。

## 1. 自动化 smoke

```bash
.venv/bin/python scripts/ws_smoke_test.py
.venv/bin/python scripts/platform_smoke.py
.venv/bin/python scripts/h_bounds_e3b_smoke.py   # H-bounds + E3b join
.venv/bin/python scripts/grasp_place_smoke.py    # IL place（需 MuJoCo）
.venv/bin/python scripts/il_place_smoke.py       # 可选：录制→导出→BC
```

期望：各脚本打印 OK / PASS。

## 2. 浏览器手测

| 项 | 步骤 | 期望 |
|----|------|------|
| 中文 Label3D | `mw_lang=zh`，进母港 | 门牌/NPC/展柜为中文（非空白） |
| 圆顶/球仓 | 外场俯视 | 舱顶圆顶、落地储罐；无悬空细环 |
| H-bounds | 走向南坞缝 / 岛缘外 | 被弹回甲板，不掉进虚空 |
| E3b | 展柜 F → stub → 回母港 URL 含 `space_id` → 门 A | 门文案显示归因；工坊 HUD 有 `space_id` |
| IL-place′ | 工坊夹起料块 | **不**弹终局 SUCCESS；提示放到工作台；放下张开后才通关 |
| City 五车 | 进训练场，俯视 | **A–E** 五台可见且队标齐全（非仅 A/B） |
| City 臂 UI | 进训练场 | **无**左下臂/爪 DOM 滑条 |
| City 路=可走 | 沿沥青穿楼间 | 看起来是路就能开过（不撞隐形墙） |

## 3. 教训 · City 三连坑（2026-07-21）

本地「好像坏了」时，先区分：**旧进程 / 旧 `dist/web` / 真逻辑 bug**。本次三件事同时成立，且**公网未重发也会复现**。

### 3.1 臂爪 UI 仍出现在 City

| | |
|--|--|
| **表象** | 训练场左下仍有臂/爪滑条；文案还提「左下角臂爪」 |
| **根因** | `MW_SET_SHELL_UI(true)` 与 `mw-no-joints` **时序竞态**：后写的 shell 状态把 City 的「隐藏关节 UI」冲掉 |
| **修法** | `MW_SET_SHELL_UI(play, hub, noJoints)`；City / 非 workshop 强制 `noJoints`；`shell.html` 以第三参为准 |
| **防再发** | 改 shell UI 后：进 Hub → 门 B City → 确认无臂条；再进 Workshop 确认臂条仍在 |

### 3.2 只看见两台机甲（A/B）

| | |
|--|--|
| **表象** | 房内应有 5 人/5 机甲，俯视只明显看到 A、B |
| **根因** | `mech_puppet.gd` 的 `TEAM_COLORS` / `TEAM_TAGS` **只覆盖 A/B**；C–E 灰/`?`，远看像「没车」 |
| **修法** | 队标与配色扩到 **A–E**（与 `city` 房 `max_members=5` 对齐） |
| **防再发** | 改人数上限时同步改队标表；手测俯视五色标签 |

### 3.3 「看着是路，却撞墙」

| | |
|--|--|
| **表象** | Godot 沥青路畅通，MuJoCo 却在楼间走廊撞空气墙 |
| **根因** | 多 lot 楼块：生成器把 **lot 之间的街道也并进一块大 collision box**，视觉仍画马路 → **皮≠权威** |
| **修法** | `gen_demo_city_block.py`：**每 lot 一盒**；重生契约 + `block_layout.json`；空房按 seed 重建 MjModel |
| **防再发** | 改 footprint / multi-lot 后必：① 重生契约 ② 开空气墙调试叠层（或对一下 `static_obstacles` 与沥青）③ Gateway 重启或空房重建 |
| **铁律** | **看得见的可行走区 = 契约里没有墙**；禁止「视觉马路 + 大盒吞街」 |

### 3.4 导出 / 缓存假象

- 只改 `.gd` / 契约 **不**自动进浏览器：必须 `export_godot.sh web`。
- 怀疑脏包：`rm -rf dist/web`（必要时清 `.godot`）再导。
- Web `script_export_mode=0`（文本）便于核对 pck 内脚本；发版可用压缩，但本地排障优先可验。
- **本地修好 ≠ 线上修好**：playground 须 rsync 新 `dist/web` + 契约/gateway + 重启 `mineworld-web` / `mineworld-gateway`，客户端硬刷新。

## 4. Playground 发版核对（摘要）

```bash
# 本机
bash scripts/export_godot.sh web
# 注入 wss://playground.dev.databall.tech/ws 到 dist/web/index.html
rsync … → binjietk:/opt/mineworld/
ssh binjietk 'sudo systemctl restart mineworld-web mineworld-gateway'
```

核对：HTTPS 200；`index.html` 含 playground WSS；`examples/contracts/demo_city.json` seed/障碍与本地一致；硬刷新后再手测 §2 City 三行。

私有细节见 `docs/ops.local.md`（gitignore）。

## 5. 勾选

- [ ] smoke 全绿
- [ ] 手测表通过（含 City 三行）
- [ ] 若动过 City/shell：已重导 + 硬刷新
- [ ] 若发公网：rsync + 双服务重启 + 硬刷新
- [ ] 无需公网 DNS（仅本地时）
