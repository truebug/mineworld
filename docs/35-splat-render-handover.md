# 35 · 会话交接 · splat 渲染卡点（3DGS .spz 出不来 · 排障全记录）

| 字段 | 值 |
|------|-----|
| **状态** | 卡点未解 · 交接给下一任 Agent 续做 |
| **创建** | 2026-08-17 |
| **关联** | [33-splat-bg-poc.md](33-splat-bg-poc.md)（PoC SSOT）· [19-changelog.md](19-changelog.md) |
| **目的** | 在 MineWorld 棋牌室/大厅挂一个 3DGS 的 `.spz` 逼真场景（Spark 渲染视觉背景，不参与物理） |
| **现状一句话** | **数据层全通（210596 splats 解码/bbox 正常），渲染层卡死在 Spark 首次 `driveSort` 深度回读——`sorting:true` 挂住 → `activeSplats=0` → 页面只出红色探针立方体** |

## 0. 给下一任 Agent 的 TL;DR

- 不要从头排查「为什么黑屏」。数据已确认没问题：`n=210596 avgOp=0.44 avgCol=0.417 avgScale=0.0108`、bbox `center=-0.18,0.20,1.78 size=3.28,2.90,4.14` 全部正常。
- 卡点集中在 Spark 排序状态机：`sorting=true` 长时间不落、`activeSplats=0`、`instanceCount=0`、`displayNum=210596`。
- 排序 worker/WASM 正常（`sortSplats32` 2 元素测试 1ms 响应）；疑似卡在 **three r180 `readRenderTargetPixelsAsync` 的 fenceSync 回读**（`TIMEOUT_EXPIRED` 时 setTimeout 无限重试）。
- 偶发观察到 `sorting:false` 且 `readback32` 有 210944 个元素、head=`0x7FB00000` 非零 → **readback 曾完成过，但 `activeSplats` 仍是 0** → 需重点核查 `sortSplats32` 全量调用的 `activeSplats` 计算为何返回 0（见 §4 待办 1）。
- 环境干扰已排除：**WebXR Emulator 扩展**会把 UA 伪造成 Quest 3 并破坏渲染（用户已关闭）；关闭后 UA 正常（`Macintosh Intel Mac OS X 10_15_7 Chrome/151`）。
- `/arm/` 同机同 spark 字节（`@sparkjsdev/spark 2.1.0`）能正常 warm `lab3.spz` → 不是 GPU 不支持，是**配置/调用路径差异**。
- **arm 仓本次零修改**；arm 传送门偏移是 arm 08-13 提交 `e954914`（office lobby 左移 2m/下沉 1m）导致，与本会话无关。

## 1. 目的（为什么做）

MineWorld 棋牌室/大厅要挂 3DGS `.spz` 逼真场景（房间皮肤），复用 mine-world-arm 已验证的 Spark + three.js 方案（详见 [33](33-splat-bg-poc.md)）。当前卡在 P1→P2 之间的渲染可见性，红色立方体是 lab 页自加的**对照探针**（`MeshBasicMaterial` 0xff4488），不是场景本体。

## 2. 现状（2026-08-17）

### 2.1 已部署/已提交

- `99a856f`：splat 根因修复①——**`fileBytes` 一次性上传替代 `url` 流式 LOD**（止 `texSubImage2D` 刷屏）+ hub `apply_hub_skin` 钩子 + lab 页 xrRig/数据探针。已部署。
- 今日两次部署（`20260817-112632` / `20260817-120932`），含新增 **`/splat-lab2.html`**（arm-parity A/B 诊断页：`enableLod:false` + `renderOrder:-20` + `depthWrite:false` + 显式 `spark.update()`）。已上线。
- 主站入口：`/?splat=lab3&splatOn=1`；lab 页：`/splat-lab.html?splat=lab3`；A/B 页：`/splat-lab2.html?splat=lab3`。

### 2.2 待入库（本次会话已提交）

- `godot/spike/web/splat-lab2.html`（新增，A/B 诊断页）
- `scripts/export_godot.sh`（白名单 + `splat-lab2.html` 一行）

### 2.3 健康检查（2026-08-17 本会话实测）

| 端点 | 结果 |
|------|------|
| `https://playground.dev.databall.tech/` | 200 |
| `/splat-lab2.html?splat=lab3` | 200 |
| `/arm/` | 200 |
| `/arm-ws`（WebSocket 握手） | **502**（浏览器日志同：`wss://playground.dev.databall.tech/arm-ws` handshake 502）——疑似既有网关问题，与 splat 无关，但需向用户确认是否已知 |

## 3. 关键证据链（用户浏览器 console 实测，MacBook Air M5 · Chrome 151 · WebXR Emulator 已关）

### 3.1 数据层 OK

```
[MW] splat-lab splats n=210596 avgOp=0.440 zeroOp%=0 avgCol=0.417 avgScale=0.0108 mesh.opacity=1 visible=true
[MW] splat-lab bbox center=-0.18,0.20,1.78 size=3.28,2.90,4.14
[MW] splat-lab ready media/splats/lab3.spz
```

### 3.2 渲染层卡死（lab2 页，加载 3s 后）

```
[lab2] state: activeSplats=0 instanceCount=0 sorting=true sortDirty=false displayNum=210596
```

Spark 内部探针：`{"sorting":false,"sortDirty":false,"worker":true,"activeSplats":0,"accumulators":2,"maxSplats":212992}`（lab 页，sorting 曾为 false 但 activeSplats 仍 0）

手动 `update()`：`BEFORE {"material":"ShaderMaterial","numSplats":null,"instanceCount":0,"displayNum":210596,"target":"2048x103",...}` → `AFTER-update` 完全不变（`lastFrame:4744` 未推进）

### 3.3 worker/WASM 正常

```
worker RESPONDED 1ms {"activeSplats":2,"readback":{"0":1,"1":2},"ordering":{"0":1,"1":0}}
```

### 3.4 readback 曾完成但 activeSplats 未落

```
sorting still: false | readback32 len: 210944 | head: [2143289344, 2143289344, ...]
```

（`210944 = ceil(210596/2048)*2048`，depth 桶数据非零 → 回读成功过；但后续探针 `sorting` 又回到 `true`、`activeSplats` 仍 0）

### 3.5 已排除项

- WebGL2 / `EXT_color_buffer_float` / `OES_texture_float_linear` 全部 true（Quest 态 UA 下测过，Mac 态未复测但 arm warm OK 可佐证）
- 排序 worker 通信：正常
- 资产/解码/bbox：正常
- arm 同资产同机：正常 → **配置差异**是唯一方向

## 4. 当前判断 + 下一步（给更聪明的 Agent）

### 4.1 根因假设（按概率排序）

1. **three r180 `readRenderTargetPixelsAsync` 在 macOS Chrome（ANGLE/Metal）fenceSync 回读挂起/极慢**：Spark `driveSort` → `readbackDepth` 用 `renderer.readRenderTargetPixelsAsync` 读 2048×103 深度 target；r180 内部 `fenceSync`+`clientWaitSync`，`TIMEOUT_EXPIRED` 时 `setTimeout` **无限重试** → `sorting` 恒 true。验证：在 lab2 页直接打点 `performance.now()` 包一层 `renderer.readRenderTargetPixelsAsync`，看是否 >5s 不 resolve。
2. **`sortSplats32` 全量调用返回 `activeSplats=0`**：readback 数据（`0x7FB00000` 桶）与全量排序的 `sA/hA`（按深度桶+索引去重统计）计算逻辑冲突；若桶值异常（如全同桶/负值）可能统计出 0。验证：worker `call("sortSplats32", {numSplats:210596, readback: sp.readback32, ordering: new Uint32Array(sp.maxSplats)})`，看返回 `activeSplats`。
3. **lab2 相机每帧轨道运动 → 每帧 `viewChanged` → `sortDirty` 恒 true → 排序永远追不上**：`driveSort` 末尾 `sorting=false` 后递归 `driveSort()`；慢回读 × 每帧新排序 = 表面「永远 sorting」。验证：把动画相机改成静态一眼，或 `sp.sortDirty=false` 冻结后手动 sort 一次。

### 4.2 建议修复方向

- 对照 arm 差异逐项收敛：`splat_bg.js`（arm）用 `preUpdate:false`、`maxStdDev:√5`、无显式 `update`；lab2 加了 `enableLod:false`/`renderOrder:-20`/`depthWrite:false`/显式 `spark.update()`。**逐项回退对比**，找出让 arm 能跑、lab2 不能的那一项。
- 若确为 readback 挂起：候选（a）Spark 内部/外部把深度回读降级为同步 `readRenderTargetPixels`（一次 2048×103 可接受）；（b）调 `readPause`/`sortDelay`/`minSortIntervalMs`；（c）`preUpdate:true`；（d）检查 depth target 格式（RGBA32F?）与 `renderer` pixelRatio/`alpha` 组合。
- 主站侧无论如何都要加**排序完成前不显示 / 加载 HUD**（E9 相机锁定加载反馈），避免「黑屏+红盒」观感。
- 验证手段：lab2 页 3s 后的 `[lab2] state:` 日志（`activeSplats/instanceCount/sorting`）；或给 HUD 加排序状态行。

### 4.3 关键文件

- `godot/spike/web/splat_bg.js`（主站 splat 引导）
- `godot/spike/web/splat-lab.html` / `splat-lab2.html`（诊断页）
- `godot/spike/web/vendor/spark/spark.module.min.js`（vendored spark，与 arm `@sparkjsdev/spark 2.1.0` 字节一致）
- 对照：`~/Downloads/projects/mine-world-arm/web/src/splat_bg.js`、`web/node_modules/@sparkjsdev/spark/dist/spark.module.js`（**可读未压缩源码**，`driveSort` 在 ~L10243，`readbackDepth` 在 ~L10737）

### 4.4 环境/权限要点

- 沙箱 `.git` 只读，git 写操作需 `require_escalated`。
- 部署：`bash scripts/deploy_playground.sh`（大输出先 `> /tmp/mw_deploy_*.log` 再 tail，见 AGENTS.md 输出预算规范）。
- 本机无可靠无头浏览器复现路径（本会话已按用户指示放弃 headless 尝试）；后续可让用户开浏览器跑探针。
- 用户环境：MacBook Air M5 · Chrome 151 · 需提醒**关闭 WebXR Emulator 扩展**再测，否则 UA 被伪装成 Quest 3 且渲染必挂。
