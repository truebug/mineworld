# 35 · 会话交接 · splat 棋牌室皮肤（接手前读完）

| 字段 | 值 |
|------|-----|
| **状态** | P1b/P1c Done · **Next = Splat-P1d 自适应 pose 同步** |
| **日期** | 2026-08-17 |
| **分支** | `main`（已 push；工作树应干净） |
| **关联** | [33-splat-bg-poc.md](33-splat-bg-poc.md) · [19-changelog.md](19-changelog.md) · [09-todo.md](09-todo.md) |
| **对照实现** | `mine-world-arm/web/src/splat_bg.js`（`fitArmWorkcell` + occupancy） |

## 0. 给下一任 Agent 的一句话

棋牌室 **3DGS 垫底已通**（`igs0047` + occupancy 挂载 + 透明合成）。用户体感问题是 **双 Canvas 相机不同步**（Godot ~60Hz / splat ~5Hz）→ 转视角空间错乱。用户已同意下一刀：**看/走时提高 pose+splat 帧率，静止再降频**。

## 1. 现状（已验收）

| 项 | 状态 |
|----|------|
| `?splat=igs0047&splatOn=1&room=chess` | 可见大室内皮肤；`alpha=true`；`shell hidden (composite OK)` |
| 挂载 | 同域 `igs0047.spz` + `igs0047.occupancy.json`（InteriorGS entry/ground，非纯 bbox） |
| lab3 | 仍可用，偏小 |
| 键鼠 | 正常（禁深链抢跑 Spark；Hub 默认不启 splat） |
| WS `Buffer payload full` | 已节流缓解（chessroom 移动节流 + pose 5Hz + 1MB 出站） |
| AmbientHum 警告 | WAV 循环，已消 |

**验收 URL**

```
https://playground.dev.databall.tech/?splat=igs0047&splatOn=1&room=chess
```

硬刷新后控制台期望：`igs-occupancy` fit · `godot canvas alpha= true` · `shell hidden (composite OK)` · **无**成片 `Buffer payload full` / AmbientHum cannot be sampled。

**调参（可选）**

- `splatOx` / `splatOz` / `splatY` — 水平/竖直微调（米）
- `splatShift` — 默认 `0`（棋桌原点）；`2.2` ≈ arm 工位前移
- `splatScale` — igs 默认 metric `1`
- `splatPeek=1` — 半透叠层调试

## 2. 未做 / 用户已确认的下一刀 = Splat-P1d

### 问题（用户原话语义）

转视角时 PLY「世界」与桌/人偶 **不完全同步**：像房间绕自己转，桌子跟着走又差一点 → **空间错乱**。

### 根因（工程）

不是 occupancy 挂错 alone，而是 **架构**：

- Godot `#canvas`：网格每帧更新
- `#mw-splat` Spark：为躲双 WebGL，渲染与 `MW_CAM_POSE` 被压到约 **5Hz**
- 两路相机不同步 → 视差/滞后

用户问过：自适应提频能否抵消？答复：**能消大半「转头不同步」，不能做到单世界级完美**；快甩仍可能 1 帧差；终极解是单 WebGL。

### 实现建议（KISS）

1. **Godot** `MWSplatBridge.POSE_HZ`：静止保持 ~5；检测相机位姿变化（或有速度命令 / 鼠标 look）时升到 **30–60**（或每帧写 `MW_CAM_POSE`）。
2. **JS** `splat_bg.js`：`minFrameMs` 静止 200ms（5fps）；若 `MW_CAM_POSE` 相对上一帧变化超过阈值，临时 `minFrameMs≈16–33`；停止变化 N×100ms 后再降回。
3. **务必**继续 `renderer.resetState()`；提频时盯控制台：`glDrawElementsInstanced` / `Buffer payload full` / 键鼠假死 → 立刻 fail-soft 或降回。
4. **FOV**：每次 pose 同步 `camera.fov`（已有则确认每帧生效）。
5. 验收：慢走/慢看应基本同世界；对比改前错乱感；静止后再降频确认 WS/GL 不炸。

### 明确不要做

- 勿恢复 DOM pad / 勿锁 `#canvas` `pointer-events`（docs/29）
- 勿在 Hub 默认双开 Spark（需 `splatHub=1`）
- 勿对 InteriorGS 乱加 yaw（docs E5）
- 勿用 `cp -R` 合并旧 `dist/web/media`（已改为整目录替换，见 `export_godot.sh`）

## 3. 关键文件（改 P1d 优先碰这些）

| 路径 | 角色 |
|------|------|
| `godot/spike/web/splat_bg.js` | 垫底 Spark；fit；≤5fps；fail-soft；**P1d 改 minFrameMs** |
| `godot/spike/scripts/mw/splat_bridge.gd` | `POSE_HZ`、透明、`push_pose`；**P1d 自适应 Hz** |
| `godot/spike/scripts/chessroom.gd` | 懒启动 Spark、藏壳、速度节流 |
| `godot/spike/scripts/ws_client.gd` | 出站 1MB + 水位闸 |
| `godot/spike/web/media/splats/igs0047.spz` | ~5.1MB 皮肤 |
| `godot/spike/web/media/splats/igs0047.occupancy.json` | entry/ground |
| `godot/spike/web/media/splats/README.md` | 资产说明 |
| `scripts/export_godot.sh` | `rm -rf dist/web/media` 再拷 |
| `mine-world-arm/web/src/splat_bg.js` | occupancy fit 参考（只读） |

## 4. 部署

```bash
bash scripts/deploy_playground.sh   # 正式；会 export + rsync 整仓
```

仅改 JS 时也可 rsync `splat_bg.js` + `dist/web/` 对应文件，但 **新 spz/occupancy 必须进 `dist/web/media`**（替换拷贝）。

## 5. 历史坑（短表）

| 坑 | 教训 |
|----|------|
| `fitNum` `Number(null)===0` | scale=0 → NaN 深度 → active=0 |
| Hub+Spark 双开 | GL 刷屏、键鼠死；Hub 禁自动 boot |
| `call_deferred("字符串")` | Web 上 Method not found → 用 `fn.call_deferred()` |
| 撤 project transparent | 藏壳后黑底；需 per_pixel + viewport transparent |
| `splatYLift=2.5` | 房间抬出视野 → 假黑 |
| igs 用 bbox floor-snap | 房间悬空；改 occupancy |
| BSD `cp -R` 进已有 media/ | 新 spz 不上公网 404 |
| chessroom 20Hz 无节流 + splat | `Buffer payload full` |

## 6. Next 候选（P1d 之后）

1. **Splat-P1d**（Now）自适应 pose/splat 帧率  
2. 程序星空垫层（虚空补边，可选）  
3. 棋牌室默认带 `splat=igs0047`（产品化）  
4. **HW-2.5** 真机联调（docs/28）/ E6–E7（blocked PMS）  
5. 长期：单 WebGL 合成（大改，非本切片）
