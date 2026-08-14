# 33 · 3DGS 场景背景（ply/spz 非 mesh 化）— PoC SSOT

| 字段 | 值 |
|------|-----|
| **状态** | 方案冻结 · 待 PoC（`?splat=` 灰度） |
| **创建** | 2026-08-14 |
| **参考** | mine-world-arm `web/src/splat_bg.js` / `docs/27-office-lobby-ply-plan.md` / `docs/07-changelog.md`（成熟经验全文继承） |
| **范围** | splat 仅作**视觉背景**；不参与物理 / MuJoCo / 碰撞 / 寻路 / FakeMech；不做 stencil 透视门 |
| **红线** | 未达标资产不进默认路径；Hub 默认不挂大 splat（opt-in `?splat=1`）；勿动 canvas 输入锁（见 [29](29-web-pico-input-postmortem.md)） |

## 0. 一句话

**Godot 不画 splat。Web shell 在 Godot `<canvas>` 底下垫一层 Spark（three.js）canvas 直渲 .spz，两相机每帧同步姿态；资产管线（转码/同域托管/fit 标定/缓存）全套复用 mine-world-arm 已验证做法。**

## 1. 为什么是「双层 canvas」而不是 Godot 插件

| 路线 | 判定 | 理由 |
|------|------|------|
| Godot 原生插件（compute 排序+tile 光栅化） | ❌ | Web 导出单线程 WebGL2，无 compute shader；排序都过不去 |
| Godot MultiMesh billboard + CPU 排序 | ❌ | 百万级 splat 每帧排序打满主线程，与 20Hz 状态流抢帧 |
| **Web 层 Spark canvas 垫底 + 相机同步** | ✅ | arm 仓已量产验证；Godot 侧零侵入，splat 纯 DOM 层 |

## 2. 自 arm 仓继承的成熟经验（勿重踩）

| # | 经验 | 出处 |
|---|------|------|
| E1 | 渲染器用 **@sparkjsdev/spark ^2.1**（three.js 系），ply/spz 通吃 | arm `package.json` |
| E2 | **必须转 .spz**：raw 90MB PLY 在 Pico 解码 ~60s；`transcodeSpz({maxSh:0, fractionalBits:12})` → ~21MB | `ply_to_spz.mjs` |
| E3 | **体积红线 ≤25MB**（超 40MB Pico 白屏/卡死）；备 lite 版（opacity cull ~26MB） | docs/27 §3.2 |
| E4 | **同域托管**（`media/splats/`），避免 CORS + 双重 gzip；S3 仅作转码源/调试镜像 | splat_bg.js |
| E5 | **fit 只调 ox/oz/yLift/scale**，禁在 preset 里加 yawDeg——Z-up→Y-up 后再 rotateY 会「拧到天花板」（已出事故） | changelog 213 |
| E6 | **park/warm 不卸载**：切场景 park 而非 dispose；Cache API 字节缓存（`mw-ply-v1`），换资产 bump version；Pico 上**绝不 await cache.put**（可挂 60s+） | ply_cache.js / main.js |
| E7 | **串行 decode**：Pico 跑不动两个重 PLY 任务 | main.js:644 |
| E8 | Spark 要求 **antialias:false**（MSAA 与 splat+mesh 混合冲突） | main.js:523 |
| E9 | 加载反馈用相机锁定 HUD（真实 I/O 驱动，不做固定时长假等待） | splat_loading.js |
| E10 | 场景黑名单制（出生点/缩放坏的资产直接 skip） | INTERIOR_GS_SKIP |

## 3. 本仓特有问题：两相机合成

arm 仓 splat 与玩法同在一个 three.js scene，无合成问题；本仓 Godot 自管画面，需：

| 项 | 约定 |
|----|------|
| 分层 | splat canvas `z-index` 垫底；Godot canvas `background:transparent`，Environment 背景改 transparent |
| 姿态协议 | Godot 每帧写 `window.MW_CAM_POSE = {x,y,z,yaw,pitch,fov}`（20Hz 足够，splat 侧插值）；Spark 相机只读 |
| 对齐 | FOV/near/far 硬编码一致；先锁 **race chase-cam**（视角最单一）做 PoC |
| 坐标 | 复用 Godot↔MuJoCo 映射 `godot_pos=(mw.x, mw.z, -mw.y)`；splat fit 用 ox/oz/yLift（E5） |
| 冲突 | splat 不进 worldStage/不响应输入；输入仍走 Godot canvas（不触碰 29 号红线） |

## 4. 资产管线（全部照抄 arm）

```
扫描/下载 .ply
  → node scripts/ply_to_spz.mjs in.ply out.spz   # maxSh:0 + fractionalBits:12
  → 体积检查 ≤25MB（超出 → opacity cull 出 lite 版）
  → dist/web/media/splats/<name>.spz             # 同域，不进 pck
  → ASSETS.md 登记（来源/体积/许可/sha256）
```

- 资产来源：自扫（Polycam/Luma 导出需确认许可）或 InteriorGS S3 镜像（arm 已用）
- 许可：仅 CC0/MIT/自扫；Spark 本体 MIT ✅

## 5. PoC 阶段勾选

| 阶段 | 内容 | 验收 |
|------|------|------|
| ~~P0~~ ✅ | 工具链：`scripts/ply_to_spz.mjs`（抄自 arm）+ `lab3.spz`（3.0MB）落 `godot/spike/web/media/splats/`，`export_godot.sh` 自动拷至 dist | 3MB ≤25MB · ASSETS.md 已入账 · 2026-08-14 |
| ~~P1~~ ✅ | shell 注入 + Hub 皮肤定位（2026-08-14 修正）：`?splat=lab3`（无 level = 大厅）→ 隐藏程序化机库壳（`HangarDress`），Spark splat 当**大厅房间皮肤**（对齐 arm 仓语义，非赛车场背景板）；`demo_race` 仍可选但会被自身天空壳遮挡（P2 再解）；vendored three/Spark import map；`mw/splat_bridge.gd` 透明合成 + `MW_CAM_POSE` 20Hz | 硬刷大厅即见 lab3 皮肤 · 2026-08-14 |
| P2 | 相机同步：`MW_CAM_POSE` 协议 + race chase-cam 对齐，无「滑移」 | 转头/加减速远景锁定 |
| P3 | 性能验收：M 系 Mac 60fps；弱机自动切 lite（`?splatLite=1` 或 heuristics） | 帧率不掉 10% |
| P4 | Hub 星空壳替换评估（opt-in）：`hub_space_sky` shader ↔ splat 舷窗外景 | 灰度默认关 |

每阶段完成记 [19-changelog.md](19-changelog.md)；P1 之前不碰默认路径。

## 6. 显式不做

- splat mesh 化 / 参与碰撞、物理、FakeMech、MuJoCo 采集
- stencil/二次相机透视门；多 splat 同时常驻 GPU
- Hub 默认挂大 splat（首屏保护）
- Pico/XR 适配（本仓主站键鼠 only，见 [29](29-web-pico-input-postmortem.md)）
