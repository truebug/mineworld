# demo0 · GDevelop POC-A 联调说明

工程：`gdevelop/demo0/GlossyDemo0.json`（场景名 **Game Scene**）

## 已具备

| 项 | 状态 |
|----|------|
| WebSocket Client 扩展 | 已安装 |
| 对象 `MechPlayer`（3D 盒子） | 已有；脚本会确保场景里有实例 |
| 事件组 **MineWorld POC-A** | 已写入工程 JSON |

## 你怎么操作

1. **若 GDevelop 正开着本工程**：先保存其它改动，再 **关闭并重新打开** `GlossyDemo0.json`（避免覆盖我们写入的事件）。
2. 点顶部标签 **「Game Scene (事件)」**，应能看到事件组 **MineWorld POC-A**。
3. 本机启动 Gateway：
   ```bash
   cd /Users/songyanzhang/Downloads/projects/mineworld
   source .venv/bin/activate
   python gateway/echo_server.py
   ```
4. 在 GDevelop 点 **预览**。
5. 用 **WASD** 控制 `MechPlayer`（W/S 进退，A/D 转向）。
6. Gateway 终端应出现 `client connected` / `joined`；盒子应移动。

## 事件组在做什么

1. **场景开始** → `WebSocketClient::Connect` → `ws://127.0.0.1:8765`
2. **每帧 JS**：处理 `hello`→`join`→`take_control`；用 `state.base_pose` 更新 `MechPlayer`；WASD 发 `velocity` cmd

坐标系：本工程 3D 的 Z 为高度，与 MuJoCo Z-up 一致；米→像素用缩放 `80`，原点约 `(720, 750, 24)`。

## 原有玩法

场景里仍有 `Player` 胶囊 + 摇杆/跳跃（模板自带）。POC 机甲是 **`MechPlayer`**，不要和 `Player` 搞混。

## 若预览连不上

- Gateway 是否在跑、端口是否 8765
- 预览是否在本机（不要用远程设备预览连 127.0.0.1）
- 事件表里是否仍有 **MineWorld POC-A**（若你在 GD 里另存覆盖了，再说一声我帮你重打补丁）
- **Connect 地址必须是带引号的字符串表达式**：`"ws://127.0.0.1:8765"`（含两边的 `"`）。写成无引号的 `ws://...` 会被解析坏，预览报 `file is not allowed`。
