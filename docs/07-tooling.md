# 07 · 工具链与自动化（Blender / MCP / CLI）

| 字段 | 值 |
|------|-----|
| **状态** | Draft |
| **日期** | 2026-07-17 |

---

## 1. 总原则

```text
主链路 = 文件/脚本/CLI（可重复、可 CI）
MCP    = 交互式辅助（改场景、查状态），非生产唯一依赖
```

---

## 2. Blender

### 2.1 角色

- 机甲/障碍 **网格与骨骼** 制作
- 导出 glTF/FBX/OBJ 供 Godot 3D 场景使用
- 可选：布局导出为场景契约中的 `static_obstacles` 参考坐标

### 2.2 CLI（稳定自动化）

```bash
# 无头执行 Python 脚本
blender -b scene.blend -P export_assets.py -- --out ./export
```

适合：批量导出、CI 资产管线。

### 2.3 MCP（Cursor / Claude 等）

社区方案（需自行安装配置，**当前 Cursor 会话未默认启用**）：

| 项目 | 说明 |
|------|------|
| [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp) | 常用；Blender 内 Addon + MCP Server |
| [RFingAdam/mcp-blender](https://github.com/RFingAdam/mcp-blender) | 工具面更大 |

典型配置（Cursor Settings → MCP）：

```json
{
  "mcpServers": {
    "blender": {
      "command": "uvx",
      "args": ["blender-mcp"]
    }
  }
}
```

使用前：Blender 已打开，Addon 已启动 TCP 服务。

**适用**：对话式建模、迭代调整；**不适用**：无人值守批量流水线（用 CLI）。

---

## 3. Godot

| 能力 | 支持度 | 说明 |
|------|--------|------|
| 桌面 GUI 编辑 | ✅ | 主路径 |
| 工程文本化（`project.godot` / `*.tscn`） | ✅ | Git diff/review 友好 |
| 无头运行 | ✅ | `--headless --script`（已用于 M1 协议验收） |
| CLI 导出 | ✅ | `--export-release`（需导出模板） |
| 官方 MCP 遥控 IDE | ❌ | 无 |

详见 [05-godot.md](05-godot.md)。

---

## 4. MuJoCo / Gateway

| 能力 | 说明 |
|------|------|
| Python API | 主集成方式 |
| Docker + mujoco-base | 生产/CI 对齐 |
| MCP | 一般不需要；逻辑在 Gateway 脚本 |

---

## 5. Cursor / AI 助手在本项目中的分工

| 可做 | 暂不宜作为唯一手段 |
|------|-------------------|
| 编写/审查场景契约、WS 协议、Gateway 代码 | 代替 Godot GUI 拖关卡 |
| 改 `*.tscn` / 写 GDScript 与编辑器插件 | 实时点选编辑器 |
| 配置 Blender MCP 辅助资产 | 无头批量导出替代 |
| 设计录制 schema、回放脚本 | — |

---

## 6. 推荐工具栈（MVP）

```text
Godot 桌面版        → 关卡与客户端
Blender + CLI       → 资产
Python Gateway      → WS + MuJoCo + 录制
Git                 → 工程与契约版本管理
（可选）Blender MCP → 资产迭代
```

---

## 7. 待建自动化（P1）

- [x] `scripts/export_godot.sh [web|macos]`：导出 Web / macOS（默认 web）
- [x] `scripts/serve_web_demo.py`：本地 Web 静态托管 + COOP/COEP
- [ ] `scripts/validate-contract.sh`：JSON Schema 校验场景契约
- [ ] `scripts/replay-session.py`：读取 JSONL 回放（`replay_xy.py` 已覆盖轨迹）

---

## 8. 资产来源与许可（2026-07-18 联网验证）

### 8.1 可用来源（实测存活）

| 来源 | 内容 | 许可 | 用途 |
|------|------|------|------|
| [godot-demo-projects](https://github.com/godotengine/godot-demo-projects)（官方） | `3d/` 30 个工程：`platformer`、`truck_town`、`squash_the_creeps`；技术演示 `kinematic_character`、`rigidbody_character`、`navigation`、`physics_interpolation`、`ik` | MIT | 关卡组织参照（Truck Town）；**`physics_interpolation`/`kinematic_character` 是 T2.7 延迟补偿与傀儡插值的官方参考** |
| [Kenney.nl](https://kenney.nl/assets) | 套件（已验证 slug）：`platformer-kit`、`city-kit-commercial`、`racing-kit`、`prototype-textures`、`blocky-characters` | **CC0** | 拼测试关首选；方块模块天然契盒体近似（C3） |
| [Quaternius.com](https://quaternius.com) | 100+ 低模 packs（robot/mech、带动画角色） | **CC0** | 机甲皮肤、装饰物 |
| Godot Asset Library（编辑器内 AssetLib） | 模板/插件/演示，API 实时可查 | 混合，逐项看 | 编辑器内直接安装 |

> 提示：GitHub 直连不可用时用镜像 `git clone https://gh-proxy.com/https://github.com/<org>/<repo>`；
> Kenney 套件 slug 会变动（如 `mini-mechs` 已 404），引用前先探活。

### 8.2 许可护栏（商业数据产品必须遵守）

1. **CC0 / MIT**：直接用（Kenney、Quaternius、Poly Haven、官方 demos、GDQuest）。
2. **CC-BY**：可用，但必须登记署名 → 仓库根目录 [`ASSETS.md`](../ASSETS.md) 台账。
3. **禁止**：CC-BY-NC / CC-BY-SA /「仅供个人学习」类许可；Sketchfab 逐项核查。
4. 每批资产入库 = 资产文件 + `ASSETS.md` 台账条目同提交。
