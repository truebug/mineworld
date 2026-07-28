# 27 · Pico WebXR 遥操前台 · 计划建议书

| 字段 | 值 |
|------|-----|
| **状态** | Proposal（待拍板后升 Living） |
| **日期** | 2026-07-28 |
| **关联** | [00-vision.md](00-vision.md) · [01-architecture.md](01-architecture.md) · [03-websocket-protocol.md](03-websocket-protocol.md) · [13-web-multiplayer-demo.md](13-web-multiplayer-demo.md) · [21-ecosystem-federation.md](21-ecosystem-federation.md) · [23-public-deploy.md](23-public-deploy.md) · [09-todo.md](09-todo.md) |

> **拍板（产品）**：Pico Ultra 上的 VR 遥操前台以 **WebXR** 为主路径，与现有 MineWorld **同协议集成**（必要时薄改 Gateway）。  
> **非默认**：UE Android APK（仅当 WebXR 性能/3DGS/系统能力不够再开并行）。

---

## 1. 目标一句话

在 **Pico 浏览器 WebXR** 中，对 **同网本地** 或 **异网/云边真机** 的 **仿真机体**（MuJoCo 现成 · Gazebo 后挂）或 **真机**（G1 等）做遥操，并在 **3DGS 漫游皮肤** 或 **实景/立体视频环境** 中观察与操作——数据仍进 MineWorld 录制飞轮。

---

## 2. 原则（与本仓铁律对齐）

| # | 原则 |
|---|------|
| 1 | **头显不权威**：WebXR 只做视口 + 输入；位姿/接触/任务成败在 Gateway 之后。 |
| 2 | **协议优先复用**：`hello → join → cmd/state/event`（[03](03-websocket-protocol.md)）；新能力进 `extensions.mw.*`，不另起一套私有 WS。 |
| 3 | **视觉 ≠ 物理**：3DGS / 视频是 **皮肤或传感呈现**；物理仍是 MuJoCo / Gazebo / 真机固件。 |
| 4 | **双前台并存**：Godot Hub/Web = 数聚球娱乐传送门；Pico WebXR = **头显遥操前台**。不互相替换。 |
| 5 | **KISS 竖切**：先空场景进 VR → 再同网接现有 Gateway → 再视频/3DGS → 再 Gazebo/真机适配。 |

---

## 3. 目标架构

```text
┌──────────────────────────────────────────────────────────┐
│  Pico Browser · WebXR 客户端（仓：`mine-world-xr`）              │
│  · immersive VR session · 头/手/手柄 → cmd                 │
│  · 视觉：轻量 mesh | 视频层 | 3DGS 漫游（非物理）            │
└────────────────────────────┬─────────────────────────────┘
                             │ WSS（同网 ws:// 或公网/边缘）
                             ▼
┌──────────────────────────────────────────────────────────┐
│  MineWorld Gateway（复用 / 薄扩）                          │
│  join / cmd / state / event / recording                  │
└───────┬──────────────────┬──────────────────┬────────────┘
        │                  │                  │
        ▼                  ▼                  ▼
   MuJoCo（现成）     Gazebo 桥（后）     边缘真机 G1 等
        │                  │                  │
        └──────────────────┴──────────────────┘
                    同一会话可落盘 frames.jsonl
```

**代码落点**：`/Users/songyanzhang/Downloads/projects/mine-world-xr`（与本仓并列；XR-0/XR-1 已通）。

**公网 Demo**：`https://playground.dev.databall.tech/xr/`（静态；`wss://…/ws` 与 Godot Web 共用 Gateway）。部署：`mine-world-xr` 内 `npm run deploy:playground`。

**Godot 侧**：继续 Hub / Workshop / City / Race / Chess；可作为「从母港发现 XR 关」的入口文案，**不**要求 Godot Web 导出直接变 WebXR。

---

## 4. 能力矩阵（要什么 / 不先做什么）

| 能力 | 本阶段 | 说明 |
|------|--------|------|
| Pico 进 WebXR、头追 | ✅ 必做 | XR-0 验收设备与浏览器 |
| 同网连本仓 Gateway 遥操仿真 | ✅ 必做 | 复用 DiffBot/工坊 mech 即可开刀 |
| 异网（playground / 自建边缘） | ✅ 复用现网 WSS 模式 | 与 [23](23-public-deploy.md) 同构 |
| 实景 / 立体视频环境 | ✅ 优先于重 3DGS | 带宽与解码可控 |
| 3DGS 漫游皮肤 | ✅ 目标态 · 后于视频 | 预热加载；禁止当物理 |
| Gazebo 后端 | 后置适配器 | Gateway `physics` 族扩展，客户端无感 |
| 真机 G1 | 后置适配器 | 边缘侧 ROS/厂商 SDK → 映射为 MW `cmd`/`state` |
| UE 原生 App | 非默认 | 性能墙或系统 API 不够再开 |
| 把头显做成完整游戏 Hub | ❌ | 娱乐壳仍在 Godot |

---

## 5. 落地切片（建议执行序）

### XR-0 · 设备烟测（约 0.5～1 日）

- Pico Ultra 打开内置浏览器，跑最小 WebXR（空天空盒 + 头追）。
- 记录：浏览器版本、WebXR / WebGL2 /（若有）WebGPU、手柄/手势可用性。
- **验收**：稳定进入/退出 `immersive-vr`。

### XR-1 · 同网协议接通（核心竖切）

- 新客户端（Three.js）实现 MW WS 最小子集。
- `join` → `take_control` → 手柄/键盘 `velocity`；`state.base_pose` 驱动简易机体 mesh（插值）。
- **仓**：并列 `mine-world-xr`（已实现）。
- **验收**：头显或桌面看见机体随权威态动；本地 Gateway 有 cmd/state。

### XR-2 · 环境呈现（视频优先）

- 叠加：平面/等距/双目视频层（实景或仿真相机流），与 mech 位姿可不同源。
- **验收**：遥操同时能看「环境视频」；断流有降级提示。

### XR-3 · 3DGS 漫游皮肤

- 预烘焙/预热加载的小场景 3DGS（或等价高斯表示）仅作背景漫游；机体仍跟 Gateway。
- 明确 **不** 在浏览器做 3DGS↔接触物理。
- **验收**：同网小场景可走可看；帧率可接受（阈值门槛另表）。

### XR-4 · 后端族扩展

- Gateway 适配：`gazebo` 桥、`hw_g1`（名称待定）——对外仍是 `cmd`/`state`。
- 异网：边缘机跑 Gateway 或中继；头显只连 WSS。
- **验收**：切换后端不换客户端协议；真机/仿真各一条冒烟。

---

## 6. 仓库与集成策略

| 选项 | 建议 |
|------|------|
| **A. 本仓 `webxr/` 或 `clients/pico-webxr/`** | 协议样例、冒烟、文档靠近 SSOT；适合竖切期 |
| **B. 独立仓 `mineworld-xr`** | 前端迭代快、与 Godot 发布解耦；通过 submodule/文档互链 |
| **推荐** | 并列仓 **`mine-world-xr`**（已建 XR-0 脚手架）；本仓只保留协议/Gateway SSOT |

**改造 MineWorld 的上限（本建议书）**：

- 允许：schema 兼容扩展、Gateway 多 physics 后端、录制字段、公网路由说明。
- 避免：重写 Godot 主链、把 Hub 搬进 WebXR、为 XR 破坏现有 Demo。

---

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| Pico WebXR 特性参差 / 引擎兼容坑 | XR-0 固定浏览器基线；锁定一小套 API |
| 3DGS 在浏览器性能不够 | XR-2 视频先行；3DGS 降分辨率 / 流式 / 预热 |
| 真机延迟与安全 | 边缘就近部署；急停与权限在边缘侧，不靠头显 |
| 与 Phase B 抢带宽 | XR 作 **并行赛道**，不阻塞棋牌/竞速；人力按周切片 |

---

## 8. 与现网产品的关系

- **数聚球传送门**（[21](21-ecosystem-federation.md)）：Hub 发现「头显遥操」入口 → 打开 WebXR URL（同身份 cookie/token 后置）。
- **采数飞轮**（[04](04-data-collection.md)）：头显会话与 Godot 会话同一 `frames.jsonl` 语义，便于 IL。
- **UE / Godot Pico 旧实验**：可作参考，**不**挡 WebXR 主路。

---

## 9. 建议立刻拍板的三件事

1. **主路径 = Pico WebXR + MW Gateway**（本文）；UE 为后备。  
2. **下一刀 = XR-0 → XR-1**（空 VR → 同网 DiffBot/工坊遥操）。  
3. **代码落点 = 并列仓 `mine-world-xr`**（已初始化），文档以本页为 SSOT。

拍板后：本页状态改为 Living；[09-todo.md](09-todo.md) 增「XR」并行条；changelog 记一笔。

---

## 10. 非目标（本建议书明确不做）

- XR 内完整棋牌/Hub 社交副本（棋牌室仍走 Godot，见既有 Chess-P）。
- 浏览器内嵌 MuJoCo / 真 3DGS 物理权威。
- 一上来多真机机型矩阵（先 1 个仿真 + 1 个真机适配模板）。
