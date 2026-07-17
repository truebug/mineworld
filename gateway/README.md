# Gateway（POC-A）

假物理 WebSocket 网关：协议形状与真仿真相同，积分在进程内完成（无 MuJoCo）。

## 要求

- Python 3.11+（已在 3.12 验证）
- 依赖：`websockets`

## 启动

```bash
cd /path/to/mineworld
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r gateway/requirements.txt

python gateway/echo_server.py
# 默认: ws://127.0.0.1:8765
# 契约: examples/contracts/tutorial_01.json
```

可选参数：

```bash
python gateway/echo_server.py --host 127.0.0.1 --port 8765 --contract examples/contracts/tutorial_01.json -v
```

## 冒烟测试

另开终端（同一 venv）：

```bash
python scripts/ws_smoke_test.py
```

期望：打印 `hello ok` → `scene ok` → `event player_take_control` → 若干 `state` 且 `x` 增大 → `smoke OK`。

## 协议摘要

1. 连接后服务端推 `hello`
2. 客户端发 `join`（`level_id: tutorial_01`）→ 收 `scene`
3. 发 `cmd`：`take_control`，再发 `velocity`（`vx/vy/yaw_rate`）
4. 服务端按 50Hz 积分、约 20Hz 广播 `state`

详见 `docs/03-websocket-protocol.md`、`schemas/ws-messages.v0.json`。

## GDevelop

预览里 WebSocket Client 连接到：`ws://127.0.0.1:8765`  
（预览与本机 Gateway 同机时用 `127.0.0.1`；勿用 `localhost` 若扩展解析异常。）
