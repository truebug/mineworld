# 05 · GDevelop 环境与工程

| 字段 | 值 |
|------|-----|
| **状态** | Draft |
| **日期** | 2026-07-17 |
| **官方** | [gdevelop.io](https://gdevelop.io/zh-cn) · [Wiki](https://wiki.gdevelop.io/) |

---

## 1. 使用方式结论

| 方式 | 是否推荐 | 说明 |
|------|----------|------|
| **桌面版 + 本地项目** | ✅ 首选 | 编辑、预览、导出；工程存本机 |
| 网页版 editor.gdevelop.io | 可选 | 偏云协作，非底座主路径 |
| 源码自托管网页编辑器 | 一般不优先 | 可构建编辑器前端，非完整 SaaS |
| 源码编译改引擎 | 进阶 | 改 GDJS / 扩展时再考虑 |

---

## 2. 本地安装（macOS）

1. 下载：[https://gdevelop.io/download](https://gdevelop.io/download) → **Download the desktop app**
2. 安装：DMG 拖入「应用程序」
3. 新建项目：**创建** → 本地保存（勿仅依赖云项目）
4. 语言：已支持简体中文

### 2.1 离线能力

- 本地项目：编辑、预览、导出可大体离线
- 需联网：AI 助手、资源商店、云同步、部分账号服务

---

## 3. 与本项目相关的扩展

| 扩展 | 用途 |
|------|------|
| **WebSocket Client** | 连接仿真网关，收发 JSON |
| **3D 相关**（模型对象、3D 碰撞等） | 机甲与场景表现 |
| 自定义扩展（P1） | 场景契约导出、协议编解码封装 |

WebSocket Client 参考：[官方文档](https://wiki.gdevelop.io/gdevelop5/extensions/web-socket-client/)

- 仅字符串，无二进制
- 动作用 `Send data to the server`，收包用 `An event was received` + `WebSocketClient::Data()`

### 3.1 不推荐误用

- **Multiplayer 扩展**：玩家联机用，**不是** MuJoCo 桥

---

## 4. JavaScript 扩展（进阶）

当事件表解析 JSON 过重时：

- 用 [JavaScript Code 事件](https://wiki.gdevelop.io/gdevelop5/events/js-code/) 或封装为扩展 actions
- 访问 `runtimeScene`、对象实例、变量
- 3D 底层为 Three.js，深度需求见 [Use JavaScript in extensions](https://wiki.gdevelop.io/gdevelop5/events/js-code/javascript-in-extensions/)

---

## 5. 导出与自动化

### 5.1 运行时交付物

- **HTML5 导出**：轻客户端，部署到静态托管 + 指向 Gateway WS URL

### 5.2 CLI（CI / 无 GUI）

官方 Electron 构建支持（源码 `newIDE/README.md`）：

```bash
# 概念示例，可执行文件名以安装为准
gdevelop --disable-update-check --run-command EXPORT_HTML5_EXTERNAL /path/to/game.json
```

社区工具 [gdexporter](https://github.com/arthuro555/gdexporter)：

```bash
npm i -g gdexporter
gdexport --in path/to/game.json --out path/to/export
```

### 5.3 工程文件

- 项目为 JSON（`game.json` 等），可被 Git 管理、被外部工具读取
- 自动化优先：**改 JSON + CLI 导出**，而非遥控 GUI

---

## 6. 付费课程

官方「学习」页付费课面向完整游戏品类教学，**对本底座非必需**；免费 Wiki + 示例 + 本项目文档即可起步。

---

## 7. 本仓工程目录（规划）

```
gdevelop/
├── mineworld/          # 主工程（待建）
│   └── game.json
└── extensions/         # 自定义扩展导出（待建）
```

---

## 8. 检查清单

- [ ] 桌面版已安装，能创建本地 3D 项目
- [ ] 已安装 WebSocket Client 扩展
- [ ] 能预览空场景并成功 HTML5 导出
- [ ] 场景变量中可存 `session_id`、网关 URL
