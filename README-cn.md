# MineWorld

**太空机器人学院 + 竞技场** —— 以游戏为壳，采集人类遥操仿真机器人执行任务的数据。学员来训练、竞赛、上榜；产品侧沉淀可训的本体轨迹、「小脑」级控制示范与仿真视觉。

[English README](README.md)

| | |
|--|--|
| **本仓是什么** | 可克隆、可本机跑通的母港 + 工坊/训练场 Demo |
| **本仓不是什么** | 托管 SaaS；商业品牌仅在私有部署时注入 |
| **技术栈** | Godot 4 表现 · MuJoCo 权威 · Python 网关 · 可选 Portal 登录 |
| **文档 SSOT** | [docs/00-vision.md](docs/00-vision.md) · [docs/09-todo.md](docs/09-todo.md) · [docs/19-changelog.md](docs/19-changelog.md) |

---

## 愿景

MineWorld 是 **机甲学院母港 / 太空竞技场** 的开源底座：

- **娱乐壳** —— 母港社交、门进训练场与工坊；计时、对决，以及后续团队模式。
- **真物理权威** —— 玩法关由无头 **MuJoCo** 驱动，不用 Godot 物理硬扛机体。
- **数据飞轮** —— 计分局可落成带标签的遥操档案（`cmd` ↔ `state` / `joints`），服务模仿学习、本体模型与仿真视觉。

**远景任务谱**（路线图，非本期全做）：搬箱、拼积木、找路、竞速、越障、探图、近战/能量对抗、无人船竞速、无人机侦察、团队球类、生存挑战等；房间类型含 **单人训练 / 多人混战 / 组队对抗 / 双人对决 / 计时成绩**。积分天梯在大厅可见。

**近端工程优先级**（见 [docs/09-todo.md](docs/09-todo.md)）：先做深 **工坊 IL 闭环** 与大厅榜，再扩机体与格斗等。远景清单是北极星，不是下个冲刺全部交付的承诺。

---

## 本地模式一览

<p align="center">
  <img src="screenshots/frontpage.jpg" alt="落地页 · 机甲学院母港" width="720" />
</p>

<p align="center">
  <img src="screenshots/entry.jpg" alt="母港大厅 · Blocky 人偶" width="720" />
</p>

<p align="center">
  <img src="screenshots/playground.jpg" alt="训练场街区" width="720" />
</p>

| 画面 | 文件 |
|------|------|
| 落地页（开源默认文案） | `screenshots/frontpage.jpg` |
| 母港大厅 | `screenshots/entry.jpg` |
| 母港外景 | `screenshots/overall.jpg` |
| 训练场 | `screenshots/playground.jpg` · `playground2.jpg` |
| 工坊 | `screenshots/workshop.jpg` |
| 街区细节 | `screenshots/hell.jpg` |

**开源落地页默认**：角标 **机甲学院母港**，页脚 `© 2026 Bug Copyright 云端机甲学院`，**无** ICP。公网「数聚球」品牌与备案号仅在部署机用私有脚本注入，**不进本仓库**。

---

## 五分钟本地 Web

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt

# 终端 A
.venv/bin/python gateway/echo_server.py --physics mujoco

bash scripts/export_godot.sh web   # 需 Godot 4.7 + Web 导出模板

# 终端 B
bash scripts/serve_web.sh restart
# → http://127.0.0.1:8080/portal/   （demo / demo）
# → 母港 http://127.0.0.1:8080/
```

母港操作：**WASD** 移动 · **QE** 转向 · **V** 切相机（默认**身后跟随** chase）· **F** 交互 · 门进工坊/训练场。

```bash
.venv/bin/python scripts/ws_smoke_test.py
.venv/bin/python scripts/platform_smoke.py
```

编辑器：`godot --path godot/spike`。

---

## 架构（极简）

```text
浏览器 / Godot  ──cmd──►  Gateway（Hub=FakeMech；关卡=MuJoCo）
                ◄─state──
```

细节：[docs/01-architecture.md](docs/01-architecture.md) · [docs/14-godot-mujoco-fusion.md](docs/14-godot-mujoco-fusion.md)

纠偏与 V 线：[docs/15-course-correction.md](docs/15-course-correction.md) · [docs/16-value-sprint.md](docs/16-value-sprint.md)

---

## 路线摘要

| 阶段 | 焦点 |
|------|------|
| **A · 学院训练飞轮** | 工坊抓放 IL 稳定；按关卡天梯；1～2 个单人训练变体 |
| **B · 成绩说话的竞技壳** | 计时竞速；薄双人对决；房间类型 `solo \| duel \| shared_ffa` |
| **C · 品类扩张** | 新机体 / 视觉 / 船机 / 格斗 —— 仅在 A–B 数据管道稳后再开 |

勾选见 [docs/09-todo.md](docs/09-todo.md)。

---

## 许可与素材

第三方资源须 **CC0/MIT**，并在对应 `ASSETS.md` 记账。私有运维与品牌注入（`*.local.md` / `*.local.py`）已 gitignore，勿强制加入提交。
