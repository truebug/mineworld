# Godot Spike（POC 客户端基线）

| 字段 | 值 |
|------|-----|
| **状态** | Accepted 基线（选型见 [`docs/adr/003`](../../docs/adr/003-client-engine-godot.md)）；主场景 `demo_workshop`（L3） |
| **日期** | 2026-07-17 · 续记 2026-07-19 |
| **对应验收** | M1 + Web Demo + 录制回放；战略见 [`docs/15-course-correction.md`](../../docs/15-course-correction.md) |

---

## 1. 这是什么

用 Godot 4 做 Viewer + 输入（权威在 Gateway/MuJoCo）：

- 内置 `WebSocketPeer` 连 `ws://127.0.0.1:8765`
- 协议形状与 `schemas/ws-messages.v0.json` 一致：hello → join → cmd → state
- 机甲是**视觉傀儡**：位置/朝向来自 gateway `state`，本地插值（ADR-002）
- 本地**无物理权威**；当前 POC 控制为平面 `velocity`（**数据价值纠偏见 docs/15**，后续可能升 `joint_targets`）
- Web：`?replay=<session_id>` 可离线回放录制帧（不连网关）

坐标映射（D1：米 · 右手 · Z-up → Godot Y-up）：`godot = (x, z, -y)`，`rotation.y = yaw`。
`base_pose` 同时提供 `yaw` 与四元数，spike 用 `yaw`；后续姿态更丰富时切 `qw/qx/qy/qz`。

## 2. 目录

```
godot/spike/
├── project.godot            # 工程（输入映射 WASD/QE + T/R）；主场景 demo_workshop.tscn
├── export_presets.cfg       # macOS 桌面导出（T3.4）
├── demo_workshop.tscn       # **默认主演示关**（封闭车间；L1/L3）
├── demo_city.tscn           # 次要：随机街区 + 楼宇占地空气墙（见 gen_demo_city_block.py）
├── assets/
│   ├── kaykit_city/         # KayKit City Builder Bits（CC0，viewer_only）
│   ├── city/                # Kenney City Kit（tutorial_02 等仍可用）
│   └── platformer/          # Kenney Platformer Kit
├── main.tscn                # tutorial_01（地面/墙/终点区/胶囊/相机/HUD）
├── scripts/
│   ├── ws_client.gd         # MWWsClient：WebSocket + 消息分发（无渲染逻辑）
│   ├── mech_puppet.gd       # MWMechPuppet：双缓冲 state 插值傀儡
│   ├── camera_rig.gd        # 跟随环绕相机
│   └── main.gd              # 会话流程 + 输入采集 + HUD / 结算
└── headless/
    └── smoke_client.gd      # 无头自测（等价 scripts/ws_smoke_test.py）
```

## 3. 跑起来（5 分钟）

前提：Python Gateway 已启动——

```bash
cd mineworld
.venv/bin/python gateway/echo_server.py   # ws://127.0.0.1:8765
```

然后：

```bash
# A. 无头自测（CI 友好，等价 ws_smoke_test.py）
godot --headless --path godot/spike --script res://headless/smoke_client.gd
# 期望：hello ok → scene ok → event → state x 增大 → smoke OK

# B. 可视化验收（M1 同款）
godot --path godot/spike          # 或直接运行主场景
# 期望：胶囊出现在原点，HUD 显示 hello 信息；
#       按 W 前进，位置由 gateway state 驱动回显，移动平滑（20Hz 插值）
```

编辑器方式：打开 Godot 4 → Import → 选 `godot/spike/project.godot` → F5 运行。

## 4. 输入映射

| 键 | 动作 | 映射到 cmd（机体系，Z-up，前向 +X） |
|----|------|-----------|
| W / S | move_forward / move_back | `vx = ±1.0` |
| Q / E | strafe_left / strafe_right | `vy = ±1.0`（+vy = 左平移） |
| A / D | turn_ccw / turn_cw | `yaw_rate = ±1.0`（+ = 逆时针） |
| T | take_control | 接管机甲 |
| R | release_control | 释放控制 |

cmd 上行频率 20Hz（与 state 下行对齐）；松手发零速。到达终点（Gateway `objective_complete`）后弹出 **SUCCESS** 大字 + 短蜂鸣，并自动 release。
Web HUD 走自定义 `web/shell.html` 的 DOM `#mw-hud`（不在 Godot CanvasLayer，避免裁切）。
点击左上角 `#mw-hud` 可收起/展开（状态记在 `localStorage`）；Godot 经 `MW_SET_HUD` 更新正文。
绑定用 `physical_keycode`，macOS 中文输入法切换布局不影响 WASD/QE。

### 相机（跟随环绕，CameraRig）

| 操作 | 效果 |
|------|------|
| 右键 / 中键拖动 | 环绕（orbit） |
| 方向键 ↑↓←→ | 地面平移视角 |
| 鼠标滚轮 | 缩放焦距（3–30m） |
| C | 视角中心回到机甲 |

相机每帧跟随机甲位置 + `look_offset`；仅表现层，不上行任何协议数据。
机甲移动仍用 WASD / QE（方向键已留给相机）。

**焦点提示**：从编辑器 F6/▶ 启动后，需先**点击一次游戏画面**让窗口获得键盘焦点，
按键才会进入 Input 系统（编辑器内联运行的正常行为，导出独立包无此问题）。

## 5. 桌面 / Web 导出

```bash
# Web（当前主线）— 需已安装 Web 导出模板
bash scripts/export_godot.sh web
.venv/bin/python scripts/serve_web_demo.py   # http://127.0.0.1:8080/ + COOP/COEP
# 或：bash scripts/serve_web.sh restart     # 自动杀掉占用 8080 的旧进程
# 录制历史：http://127.0.0.1:8080/recordings.html（或游戏内右上角 Recordings）

# macOS 备选
bash scripts/export_godot.sh macos
open dist/macos/MineWorldSpike.app
```

Gateway 地址：默认 `ws://127.0.0.1:8765`；Web 页可设 `window.MINEWORLD_GATEWAY`。  
路线与多人分期：[docs/13-web-multiplayer-demo.md](../../docs/13-web-multiplayer-demo.md)。

## 6. M1 验收对照

| `docs/11` §7.1 条目 | 本 spike 对应 |
|------|------|
| gateway 可启动 | 仓库既有 `gateway/echo_server.py` |
| 独立脚本完成 hello→join→state | `headless/smoke_client.gd`（含 x 增大断言） |
| 客户端连接成功、键盘发 cmd、3D 对象随 state 移动 | `main.tscn` 运行场景 |
| 协议字段与 `03` 草案一致 | 全部消息走 `MWWsClient`，无私货字段 |

## 7. 已知边界（spike 阶段）

- 默认主场景 `demo_workshop.tscn`（L3）；`demo_city` 可选手动打开 + `--contract demo_city.json`
- `demo_city`：双机同框；KayKit 楼=`viewer_only`；街道=深色沥青带；占地盒=MuJoCo 空气墙
- 重新生成街区：`.venv/bin/python scripts/gen_demo_city_block.py --seed 42`（可改 seed）
- Web（city）：右下角 **seed / Regen / Random** → `POST /api/city-block` 后自动刷新（私房）；无需重导出即可拉新 layout
- Gateway 默认 `demo_workshop.json`；契约 mtime 变了会重建 MuJoCo 世界（占用中的房间仍用旧图直到空）
- `main.tscn`（tutorial_01）仍可用；墙/终点按对应契约手工摆位
- 插值用「延迟一拍」策略（50ms）；未做丢包外推与回滚
- 未接 GDevelop 侧既有的摇杆/键盘双输入 UI
- `WebSocketPeer` 为文本 JSON；与 GDevelop 相同的限制（无二进制）——对协议无影响
