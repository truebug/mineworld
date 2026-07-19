# 资产台账（ASSETS Ledger）

| 字段 | 值 |
|------|-----|
| **状态** | Living |
| **创建日期** | 2026-07-18 |
| **规则** | [docs/07-tooling.md](docs/07-tooling.md) §8.2 许可护栏 |

---

## 许可政策（商业数据产品，必须遵守）

1. **允许直接用**：CC0（Kenney / Quaternius / Poly Haven）、MIT（官方 demos / GDQuest）。
2. **允许但需署名**：CC-BY——必须在本文件登记署名信息。
3. **禁止入库**：CC-BY-NC、CC-BY-SA、「仅供个人学习/非商用」类许可；Sketchfab 资产逐项核查后再决定。
4. **入库纪律**：资产文件与本文件条目同一提交；禁止只进资产不登记。

## 台账

| 资产 | 来源 | 许可 | 用途 / 存放位置 | 署名要求 | 入库日期 |
|------|------|------|----------------|----------|----------|
| Platformer Kit 4.1 | [kenney.nl/assets/platformer-kit](https://kenney.nl/assets/platformer-kit) | CC0 | `tutorial_02` 平台跳跃素材；`godot/spike/assets/platformer/`（含 License）；**F1** 亦用于 `main.tscn` / tutorial_01 装饰 | 无 | 2026-07-18 |
| City Kit (Commercial) 2.1 | [kenney.nl/assets/city-kit-commercial](https://kenney.nl/assets/city-kit-commercial) | CC0 | 城市/建筑环境素材；`godot/spike/assets/city/` | 无 | 2026-07-18 |
| planar_cart URDF/MJCF | 本仓库自研 F2 试点 | MIT（仓库许可） | `mujoco/models/mechs/planar_cart.urdf` → `planar_cart.xml`（fallback） | 无 | 2026-07-19 |
| DiffBot URDF skin（F5） | [ros2_control_demos](https://github.com/ros-controls/ros2_control_demos) `@1c5c439` `ros2_control_demo_description/diffbot/` | Apache-2.0 | `mujoco/models/mechs/third_party/diffbot/` → `diffbot_planar.xml`（默认 world） | 保留 `LICENSE` | 2026-07-19 |
