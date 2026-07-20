# 示例

| 路径 | 说明 |
|------|------|
| `contracts/demo_workshop.json` | **默认主演示关**（封闭车间 + 料箱；L3） |
| `hub/exhibits.v0.json` | Hub 展柜元数据（E5）；与 `godot/spike/data/exhibits.v0.json` 同步 |
| `contracts/demo_city.json` | 次要：随机街区空气墙 + 终点；楼宇由 `block_layout.json` 摆 |
| `contracts/tutorial_01.json` | POC 教程关场景契约（对齐 scene-contract.v0） |
| `ws/hello.json` · `cmd_velocity.json` · `cmd_joint_targets.json` · `cmd_velocity_and_joints.json` · `state_full.json` | WS 消息样例 |
| `recordings/sample_header.json` · `sample_frames.jsonl` | 录制样例 |

Gateway 实现：[`gateway/echo_server.py`](../gateway/echo_server.py) · 冒烟：[`scripts/ws_smoke_test.py`](../scripts/ws_smoke_test.py)  

校验：见 [`schemas/README.md`](../schemas/README.md)。
