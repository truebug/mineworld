# 38 · 3D 资产观感提升与生成管线（SSOT）

| 字段 | 值 |
|------|-----|
| **状态** | Active · 立项 2026-08-20 · 明日继续 |
| **关联** | [37](37-improvement-plan-2026-08.md)（观感短板①）· [33](33-splat-bg-poc.md) · [35](35-splat-render-handover.md) · v23d（video→3DGS 栈，sitmaster 主控 + binjiegpu worker） |

> 根本诉求：MineWorld 场景观感停留在「工程 demo 级」。结论：**主战场是渲染氛围 + 实拍皮肤规模化，AI 生成只做幻想皮肤补充**。

## 1. 三层资产供给线（已冻结）

| 层 | 用途 | 路线 | 状态 |
|----|------|------|------|
| 1 · 场景皮肤 | 整屋氛围（Hub/关卡） | **实拍视频 → v23d → SPZ**（igs0047 已验证） | 管线通，待产品化 |
| 2 · 幻想皮肤 | 无实拍条件的风格化场景 | 文/图生图 → **TripoSplat**（MIT，自托管 binjiegpu，作 v23d 第五 backend） | 待装 |
| 3 · 道具件 | 奖杯/展柜/门牌 | TRELLIS（v23d 已有）+ 程序几何 | 够用 |

- AI 生成**不接**可行走场景皮肤（结构错误一眼看穿）；层 2 只供风格化容错场景。
- 备选 `apple/ml-sharp`（8.8k★，秒级单图 3DGS）许可证 NOASSERTION，入仓前逐条核授权，暂第二顺位。

## 2. 明日执行序

| 序 | 任务 | 验收 | 状态 |
|----|------|------|------|
| S1 | `scripts/skin_bake.py`：拉 S3 PLY → `ply_to_spz.mjs` → 质检（splat 数 ≤80 万、SPZ ≤8MB）→ occupancy（entry=质心/ground=5% 分位，可人工覆盖）→ `media/splats/` | igs0047 重 bake 产物与现网一致 | [ ] 明日 |
| S2 | 皮肤目录 `media/splats/catalog.json`（id/名称/预览图/大小） | Portal 皮肤页可读 | [ ] |
| S3 | 实拍 Pilot：拍一段房间视频 → v23d `/v1/jobs` → bake → 挂训练场/Hub 外场第二皮肤位 | 契约 `skin="splat:<id>"` 免 URL 生效 | [ ] 待素材 |
| S4 | binjiegpu 装 TripoSplat；一张概念图试跑出 PLY | 幻想皮肤 demo 一张 | [ ] |
| S5 | 渲染氛围第二轮：全域调光/雾/假阴影（不写新管线） | 四关截图对比入 PR | [ ] |

## 3. 风险与红线

- 尺度/朝向：bake 时按 occupancy ground 强制归一（复用 igs0047 floor-snap 逻辑）
- Web 性能：双 Canvas 架构下 splat 数封顶；bake 出 high/lite 两档
- 授权：实拍零风险；AI 生成件进 `ASSETS.md` 台账并标注来源服务；NC/SA 零容忍
- v23d 对接纪律：S2S key 不下发浏览器；MCP 入口在 sitmaster localhost（待定 ssh 隧道或内网监听）

## 4. 环境备忘（2026-08-20）

- `eggsearch` MCP 已装（`~/.cargo/bin/eggsearch`，Rust 编译，Clash 7897 代理）并写入 `~/.codex/config.toml`；**重启会话生效**。HTML 引擎本网络被反爬，建议配 GitHub token 点亮 `github_*` 引擎
- `[tools] web_search = true` 已写入但 moonbridge 桥未转发，仍 unsupported；联网检索走 curl + GitHub API
