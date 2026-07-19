# 05 · Godot 环境与工程

| 字段 | 值 |
|------|-----|
| **状态** | Active |
| **日期** | 2026-07-17 |
| **选型依据** | [adr/003-client-engine-godot.md](adr/003-client-engine-godot.md)（替换本文档前身 `05-gdevelop.md`） |
| **官方** | [godotengine.org](https://godotengine.org/) · [文档](https://docs.godotengine.org/zh-cn/stable/) |

---

## 1. 使用方式结论

| 方式 | 是否推荐 | 说明 |
|------|----------|------|
| **官方桌面编辑器（4.x）+ 本地工程** | ✅ 首选 | 编辑、运行、导出；工程存本机 |
| 无头 `--headless --script` | ✅ 验收/CI | 协议冒烟、回归自动化（已用于 M1） |
| 源码编译改引擎 | 进阶 | 暂不需要 |
| Web 导出 | 后置 | 包体大、需 COOP/COEP；MVP 先用原生预览/导出 |

## 2. 本地安装（macOS）

1. 下载：[https://godotengine.org/download/macos/](https://godotengine.org/download/macos/) → **Godot Engine（标准版，非 .NET）**
2. 解压得到 `Godot.app`，拖入「应用程序」
3. 版本：spike 验证于 **4.6.2-stable**；团队统一用同一稳定版
4. 语言：编辑器内置简体中文（Editor Settings → Interface → Language）

命令行调用（无头/CI 用）：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --version
# 建议 alias：alias godot=/Applications/Godot.app/Contents/MacOS/Godot
```

## 3. 与本项目相关的能力

| 能力 | 用途 |
|------|------|
| **内置 `WebSocketPeer`** | 连接仿真网关，收发 JSON 文本（见 `godot/spike/scripts/ws_client.gd`） |
| **3D 场景 / 相机 / 光照** | 机甲与场景表现（一等公民，非叠加层） |
| **`Input` 动作映射** | WASD/QE → `velocity` cmd（见 `project.godot [input]`） |
| **glTF/GLB 导入** | 现网资产（`StartingCapsule.glb` 等）直接可用 |
| **编辑器插件（P1）** | 从 `.tscn` 直读场景生成场景契约（替代手写 JSON） |

### 3.1 不推荐误用

- **客户端本地物理驱动机甲**：违反 ADR-002，机甲权威在 MuJoCo；客户端只做插值/外推展示。
- **高层 Multiplayer 同步位姿**：同 GDevelop 时代结论，不作为 MuJoCo 桥接通道。

## 4. 坐标系映射（D1 已冻结）

契约/协议为 **米 · 右手系 · Z-up**；Godot 为 **右手系 · Y-up**。映射集中在傀儡脚本一处（`godot/spike/scripts/mech_puppet.gd`）：
相机由 `scripts/camera_rig.gd` 提供：每帧跟随机甲位置、世界系 yaw/pitch（机甲自转不甩镜头）。纯表现层，不上行任何协议数据。

| 操作 | 效果 |
|------|------|
| 右键 / 中键拖动 | 环绕（orbit） |
| 方向键 ↑↓←→ | 地面平移视角（`look_offset`） |
| 滚轮 | 缩放（场景可配 3–48m） |
| C | 视角中心回到机甲 |

机甲遥操仍为 **WASD 移动 / QE 转向 / T 接管 / R 释放**（方向键已留给相机，不再开车）。

```gdscript
godot_pos = Vector3(mw.x, mw.z, -mw.y)
rotation.y = yaw          # Z-up yaw（弧度）→ Godot 绕 Y 轴
```

`base_pose` 同时提供 `yaw` 与四元数（`qw/qx/qy/qz`）；当前用 `yaw`，姿态更丰富时切四元数并注意轴序换算。

## 5. 工程组织与导出

### 5.1 工程文件

- `project.godot`（INI 文本）+ `*.tscn` / `*.gd`（文本）——天然 Git 友好，可做 diff/review
- 编辑器首次打开会生成 `.godot/` 缓存目录，**已 gitignore**，勿提交

### 5.2 运行时交付物

- **当前主线（W1）**：Web 导出（`export_presets.cfg` preset `Web` + `scripts/export_godot.sh web`）+ `scripts/serve_web_demo.py`（COOP/COEP）+ 本机 Gateway
- **备选**：macOS 原生导出（`export_godot.sh macos`）
- **前置**：与编辑器同版本的 Export Templates（**含 Web**）。产物 `dist/` gitignore。
- **线上多人**：分期见 [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md)；未完成会话隔离前勿称多人已可用
- **P1+**：PWA / 应用商店分发非 Demo 必需

```bash
bash scripts/export_godot.sh web
bash scripts/serve_web.sh restart    # 推荐：自动杀掉旧 :8080
# 或：.venv/bin/python scripts/serve_web_demo.py
bash scripts/export_godot.sh macos
```

录制历史（D5）：同进程 HTTP `GET /api/recordings*`，页面 `/recordings.html`（游戏内右上角 Recordings）。

### 5.3 无头自动化（CI）

```bash
godot --headless --path godot/spike --script res://headless/smoke_client.gd
# 期望 smoke OK，exit 0（等价 scripts/ws_smoke_test.py）
```

## 6. 本仓工程目录

```
godot/
└── spike/               # POC-A M1 镜像（见 godot/spike/README.md）
    ├── project.godot
    ├── tutorial_02.tscn          # city-level (Kenney assets)
    ├── main.tscn
    ├── scripts/         # ws_client / mech_puppet / main / camera_rig
    └── headless/        # 无头验收脚本（smoke_client.gd）
```

后续正式工程建议独立子目录（如 `godot/client/`），spike 保留作回归基线。

## 6.1 搭关卡的标准工作流（第二关前必须走通）

1. 新建 3D 场景（`.tscn`），摆地面/障碍/终点区。
2. 物理相关对象：节点 `set_meta("mujoco_entity_id", "wall_02")` 绑定契约 ID（P1 由编辑器插件自动导出契约；现阶段手工对齐）。
3. 手写契约 JSON（`examples/contracts/<level>.json`），出生点写 `mech_spawns`。
4. 起 Gateway（`--contract` 指向新契约）+ F5 联调。
5. 纯装饰物随便加——不进契约即可（`game_logic_only`）。

**自检**：在编辑器里挪动一堵墙但**不改契约** → 运行后视觉墙在新位置、物理墙（MuJoCo 里）还在老位置——用此差异确认契约才是物理世界的 SSOT。

## 7. 检查清单

- [x] 桌面版已安装（4.6.2），能打开本地 3D 工程
- [x] `WebSocketPeer` 连接 Gateway 成功（`hello` 解析、`session_id` 存储）
- [x] 无头 smoke 通过（M1）
- [x] 键盘 cmd 驱动 state 回显（WASD/QE）
- [x] 跟随环绕相机（CameraRig：RMB/MMB 环绕、滚轮缩放、方向键平移、C 回中）
- [x] tutorial_02 城市关人工验收（6 实体、Kenney 资产）
- [x] 原生导出管线（T3.4：`export_presets.cfg` + `scripts/export_godot.sh`；本机需导出模板）
- [ ] 契约导出编辑器插件（P1）
