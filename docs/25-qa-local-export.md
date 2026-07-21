# Local Web / Hub 验收清单（QA-export）

公网 W2 另轨。本清单验证 H-bounds / E3b / IL-place′ / 中文与外观。

## 0. 启动

```bash
# 终端 A
.venv/bin/python gateway/echo_server.py --physics mujoco

# 终端 B（可选 API）
.venv/bin/python mw_platform/api_server.py

# 导出 + 静态
bash scripts/export_godot.sh web
bash scripts/serve_web.sh restart
```

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

## 3. 勾选

- [ ] smoke 全绿
- [ ] 手测表通过
- [ ] 无需公网 DNS
