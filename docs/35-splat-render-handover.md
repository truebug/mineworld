# 35 · 会话交接 · splat 渲染卡点（3DGS .spz）

| 字段 | 值 |
|------|-----|
| **状态** | P 门棋牌室合成验收通过（alpha + floor-snap + shell hidden） |
| **日期** | 2026-08-17 |
| **关联** | [33-splat-bg-poc.md](33-splat-bg-poc.md) · [19-changelog.md](19-changelog.md) |
| **目的** | 棋牌室挂 3DGS `.spz` 视觉皮肤（Spark，不参与物理） |
| **现状一句话** | `godot canvas alpha=true` + `shell hidden (composite OK)` + 可见 lab3；桌椅与扫描家具不必一一对齐 |

## 0. 请用户验收

1. https://playground.dev.databall.tech/?splat=lab3&splatOn=1 → 母港 armed，勿立刻 loading  
2. P 门或 `?room=chess` → 控制台 `alpha=true` / `shell hidden (composite OK)`，见 lab3 垫底、桌/人在上  
3. 纯母港无参数：未回归  

## 0.1 根因（坐实）

```js
// 坏：缺 query 时 Number(null) === 0
const v = Number(params.get("splatScale")); // null → 0
mesh.scale.setScalar(0); // if (s !== 1)

// 好：缺省走 default
if (raw == null || raw === "") return d;
```

- `mesh.scale = (0,0,0)` → 生成深度时中心变换出 **NaN**（`0x7fc00000`）→ `sortSplats32` → `activeSplats=0`
- `/arm/` 正常：arm 的 `fitArmWorkcell` 会 `mesh.scale.setScalar(s)` 覆盖为 >0
- 本地 puppeteer：旧 lab2 复现 NaN；只改 `fitNum` 即 `activeSplats=210596`

## 0.2 已改文件

- `splat-lab2.html` / `splat-lab.html` / `splat_bg.js`：修正 `fitNum`
- lab2 另：lab3 默认 −90° X（`?orient=0` 关）；HUD 显示 `meshScale`

## 1. 目的

复用 mine-world-arm 的 Spark + three 方案挂 `.spz` 房间皮肤。红盒是 lab 对照探针。

## 2. 上午误判（保留作教训）

曾怀疑 async fence / LOD / holdCam；那些是红鲱鱼。NaN 深度真实，但来自 **scale=0**，不是 readback API。

## 3. 关键文件

- `godot/spike/web/splat_bg.js`
- `godot/spike/web/splat-lab.html` / `splat-lab2.html`
- 对照：`mine-world-arm/web/src/splat_bg.js`

## 4. 部署

- 本轮可只 rsync 上述 web 文件（无 Godot 导出依赖）
- 全量：`bash scripts/deploy_playground.sh`
