# Gateway（POC）

WebSocket 网关：假物理（进程内积分）或 MuJoCo 真物理；协议形状与录制旁路一致。

战略背景：管道已通；控制深度纠偏见 [`docs/15-course-correction.md`](../docs/15-course-correction.md)。

## 要求

- Python 3.11+（已在 3.12 验证）
- 依赖：`websockets`；`--physics mujoco` 另需 `mujoco`

## 启动

```bash
cd /path/to/mineworld
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r gateway/requirements.txt

python gateway/echo_server.py
# 默认: ws://127.0.0.1:8765
# 契约: examples/contracts/demo_workshop.json（L3；city 用 --contract demo_city.json）
```

真物理模式（MuJoCo，含契约静态障碍碰撞）：

```bash
python gateway/echo_server.py --physics mujoco
# 默认 workshop；city: --contract examples/contracts/demo_city.json
# hello.features 将包含 "mujoco"；契约 static_obstacles(box) 会作为静态 geom 加入仿真
# 契约文件 mtime 变化时，新房间会热重建 MuJoCo 世界（D9）
```

默认在 `recordings/sessions/<session_id>/` 落盘 `header.json` + `frames.jsonl`（join 后开始；断开时收尾）。可用 `--no-record` 关闭，或 `--record-dir` 改路径。

可选参数：

```bash
python gateway/echo_server.py --host 127.0.0.1 --port 8765 --contract examples/contracts/demo_workshop.json -v
```

## 冒烟测试

另开终端（同一 venv）：

```bash
python scripts/ws_smoke_test.py
# 录制验收（墙钟略长于 10s，确保 sim ≥10s）：
python scripts/ws_smoke_test.py --seconds 11.5
python scripts/replay_xy.py recordings/sessions/<session_id> --ascii
```

期望：打印 `hello ok` → `scene ok` → `event player_take_control` → 若干 `state` 且 `x` 增大 → `smoke OK`。
录制目录应有 `header.json`（`stats.duration_sim_s` ≥ 10）与 `frames.jsonl`。

任务闭环（T3.1，fake 物理直线开到终点区）：

```bash
python scripts/ws_smoke_test.py --expect-objective
# 期望 event objective_complete → smoke OK (objective)
```

## 协议摘要

1. 连接后服务端推 `hello`
2. 客户端发 `join`（`level_id: demo_city`）→ 收 `scene`
3. 发 `cmd`：`take_control`，再发 `velocity`（`vx/vy/yaw_rate`）
4. 服务端按 50Hz 积分、约 20Hz 广播 `state`

详见 `docs/03-websocket-protocol.md`、`schemas/ws-messages.v0.json`。

## 客户端

现行客户端为 Godot（`godot/spike/`），连接 `ws://127.0.0.1:8765`；无头验收：

```bash
godot --headless --path godot/spike --script res://headless/smoke_client.gd   # 期望 smoke OK
```

Legacy：GDevelop `gdevelop/demo0`（存档，见 `docs/adr/003-client-engine-godot.md`）。  
（客户端与本机 Gateway 同机时用 `127.0.0.1`；勿用 `localhost` 若解析异常。）

## 录制索引与导出

会话默认写在 `recordings/sessions/<id>/`（`header.json` + `frames.jsonl`）。辅助模块：

- `gateway/recording_store.py` — FS 扫描、`rebuild_sqlite` → `recordings/index.sqlite`
- `scripts/export_trajectories.py` — IL 导出（默认 `outcome=success`；`--level-id` / `--task-id` / `--outcome`；含 `cmd_joint_targets`+`joints`）
- `scripts/stow_crate_smoke.py` — V3a 箱子推入料箱 → `objective_complete`
- `scripts/il_smoke.py` — V-IL：录制版 stow + export 过滤断言 ≥1 行
- Web：`POST /api/recordings/reindex` · `GET /api/recordings/export.csv?level_id=&task_id=&outcome=`（经 `serve_web_demo.py`）
