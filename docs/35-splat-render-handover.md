# 35 · 会话交接 · splat 渲染卡点（3DGS .spz）

| 字段 | 值 |
|------|-----|
| **状态** | 续做中 · 2026-08-17 下午已推 lab2 修复候选 |
| **日期** | 2026-08-17 |
| **关联** | [33-splat-bg-poc.md](33-splat-bg-poc.md) · [19-changelog.md](19-changelog.md) |
| **目的** | 棋牌室/大厅挂 3DGS `.spz` 视觉皮肤（Spark，不参与物理） |
| **现状一句话** | 数据层全通；原卡点含深度回读头为 float NaN（`0x7FC00000`）→ `activeSplats=0`；lab2 已改回 arm/`splat-lab` 配置 + 默认同步 readback + 首次排序前冻相机 |

## 0. 请用户验收（本次续做）

Chrome（**关闭 WebXR Emulator**）强刷：

1. https://playground.dev.databall.tech/splat-lab2.html?splat=lab3
2. HUD 应出现 `activeSplats>0`，房间扫描可见（不只红盒）
3. 控制台有 `[lab2] FIRST activeSplats=…`；`sampleNan%` 应下降
4. A/B：`?syncRead=0` 若又挂 → H1；`?holdCam=0` 若更难出图 → H3

### 本次代码

- `splat-lab2.html`：去掉 `enableLod:false` 回归；默认同步 readback；holdCam；HUD
- `splat_bg.js`：默认同步 readback（`?syncRead=0` 关）

### 判断更新

| 假设 | 更新 |
|------|------|
| H1 async fence | 仍可能；默认同步 readback 绕过 |
| H2 sort→0 | **机制坐实**：`2143289344`=`0x7FC00000`=**NaN 深度** |
| H3 相机 thrash | 保留；默认 holdCam |
| lab2 关 LOD | **高嫌疑回归**；已撤回 |

## 1. 目的

复用 mine-world-arm 的 Spark + three 方案挂 `.spz` 房间皮肤。红盒是 lab 对照探针，不是场景本体。

## 2. 上午证据链（仍有效）

- 数据：`n=210596`、bbox 正常
- 渲染：`sorting=true` / `activeSplats=0` / `instanceCount=0`
- worker 2 元素 `sortSplats32` OK
- readback 曾完成但 head 实为 NaN 位型
- WebXR Emulator 伪 UA 已排除；`/arm/` 同机同 spark 正常
- spark 字节与 arm `@sparkjsdev/spark 2.1.0` 一致

## 3. 关键文件

- `godot/spike/web/splat_bg.js`
- `godot/spike/web/splat-lab.html` / `splat-lab2.html`
- `godot/spike/web/vendor/spark/spark.module.min.js`
- 对照：`mine-world-arm/web/src/splat_bg.js` + 未压缩 `spark.module.js`（`driveSort` / `readbackDepth`）

## 4. 部署 / 环境

- `bash scripts/deploy_playground.sh`
- 无可靠无头浏览器；以用户实机 console/HUD 为准
- MacBook Air M5 · Chrome 151 · 关 WebXR Emulator
