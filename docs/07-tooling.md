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
- 导出 glTF/FBX/OBJ 供 GDevelop 3D 对象使用
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

## 3. GDevelop

| 能力 | 支持度 | 说明 |
|------|--------|------|
| 桌面 GUI 编辑 | ✅ | 主路径 |
| 工程 JSON 直改 | ✅ | Git + 外部工具 |
| CLI 导出 | ⚠️ | `--run-command EXPORT_HTML5_EXTERNAL` / gdexporter |
| 官方 MCP 遥控 IDE | ❌ | 无 |
| 社区 gdevelop-mcp | 极少 | 不可依赖 |

详见 [05-gdevelop.md](05-gdevelop.md)。

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
| 编写/审查场景契约、WS 协议、Gateway 代码 | 代替 GDevelop GUI 拖关卡 |
| 改 `game.json`、写 GDevelop JS 扩展 | 实时点选编辑器 |
| 配置 Blender MCP 辅助资产 | 无头批量导出替代 |
| 设计录制 schema、回放脚本 | — |

---

## 6. 推荐工具栈（MVP）

```text
GDevelop 桌面版     → 关卡与客户端
Blender + CLI       → 资产
Python Gateway      → WS + MuJoCo + 录制
Git                 → 工程与契约版本管理
（可选）Blender MCP → 资产迭代
```

---

## 7. 待建自动化（P1）

- [ ] `scripts/export-gdevelop.sh`：gdexport 一键导出 HTML5
- [ ] `scripts/validate-contract.sh`：JSON Schema 校验场景契约
- [ ] `scripts/replay-session.py`：读取 JSONL 回放
