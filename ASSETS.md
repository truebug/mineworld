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
| City Kit (Commercial) 2.1 | [kenney.nl/assets/city-kit-commercial](https://kenney.nl/assets/city-kit-commercial) | CC0 | 城市/建筑环境素材；`godot/spike/assets/city/`（仍可用于 tutorial_02） | 无 | 2026-07-18 |
| KayKit City Builder Bits 1.0（子集） | [itch](https://kaylousberg.itch.io/city-builder-bits) · [GitHub](https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0) | CC0 | `demo_city` 默认关城市皮；`godot/spike/assets/kaykit_city/`（gltf+atlas；见目录 ASSETS.md） | 无（可署名 Kay Lousberg） | 2026-07-19 |
| planar_cart URDF/MJCF | 本仓库自研 F2 试点 | MIT（仓库许可） | `mujoco/models/mechs/planar_cart.urdf` → `planar_cart.xml`（fallback） | 无 | 2026-07-19 |
| DiffBot URDF skin（F5） | [ros2_control_demos](https://github.com/ros-controls/ros2_control_demos) `@1c5c439` `ros2_control_demo_description/diffbot/` | Apache-2.0 | `mujoco/models/mechs/third_party/diffbot/` → `diffbot_planar.xml`（默认 world） | 保留 `LICENSE` | 2026-07-19 |
| DiffBot+臂+爪 MJCF（V2a） | 本仓库自研（底盘几何对齐 DiffBot 皮） | MIT（仓库许可） | `mujoco/models/mechs/diffbot_arm_gripper.xml`；`demo_workshop` 默认机体 | 无 | 2026-07-19 |
| Factory Kit 3.0（子集） | [kenney.nl/assets/factory-kit](https://kenney.nl/assets/factory-kit) | CC0 | `demo_workshop` viewer_only 皮；`godot/spike/assets/kenney_factory/`（见目录 ASSETS.md） | 无 | 2026-07-19 |
| KayKit Dungeon Remastered 1.0（子集） | [itch](https://kaylousberg.itch.io/kaykit-dungeon-remastered) · [GitHub](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0) | CC0 | `demo_hub` 地下城入口厅皮；`godot/spike/assets/kaykit_dungeon/` | 无（可署名 Kay Lousberg） | 2026-07-20 |
| Blocky Characters 2.0（子集） | [kenney.nl/assets/blocky-characters](https://kenney.nl/assets/blocky-characters) | CC0 | Hub 人形纸片人；`godot/spike/assets/kenney_blocky/` | 无 | 2026-07-20 |
| Noto Sans SC Regular（子集 TTF） | [fontsource](https://github.com/fontsource/font-files) · [Noto CJK](https://github.com/notofonts/noto-cjk) | SIL OFL 1.1 | Hub `Label3D`/HUD 中文；`godot/spike/assets/fonts/`（见 OFL.txt） | 保留 OFL | 2026-07-21 |
| Racing Kit 1.x（子集） | [kenney.nl/assets/racing-kit](https://kenney.nl/assets/racing-kit) | CC0 | `demo_race` viewer 护栏/旗/树；`godot/spike/assets/kenney_racing/` | 无 | 2026-07-22 |
| Car Kit 3.1（子集） | [kenney.nl/assets/car-kit](https://kenney.nl/assets/car-kit) | CC0 | `demo_race` viewer 车皮；`godot/spike/assets/kenney_car/` | 无 | 2026-07-22 |
| Metal Toolbox（2K） | [polyhaven.com/a/metal_toolbox](https://polyhaven.com/a/metal_toolbox) | CC0 | Hub 中央碑旁英雄静物（PBR）；`godot/spike/assets/polyhaven_metal_toolbox/` | 无（可署名 Poly Haven） | 2026-07-22 |

### 候选（未入库 · demo_race 皮）

| 资产 | 来源 | 许可 | 拟用途 |
|------|------|------|--------|
| Toy Car Kit | [kenney.nl/assets/toy-car-kit](https://kenney.nl/assets/toy-car-kit) | CC0 | 备选玩具风赛道块 |
| Godot Racing Starter（参考） | [github.com/KenneyNL/Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | 看仓库许可 | 仅对照玩法/镜头，不整包迁入 |
