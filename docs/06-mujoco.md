# 06 · MuJoCo 无头仿真集成

| 字段 | 值 |
|------|-----|
| **状态** | Draft |
| **日期** | 2026-07-17 |
| **关联资产** | 数聚球 `mujoco-base` · `viser-gateway/examples/mujoco_g1` |

---

## 1. 角色

MuJoCo 在本项目中是 **机甲与契约内物理实体的唯一权威**：

- 关节位置/速度、基座位姿、接触
- 固定 `dt` 步进
- 无头运行，不依赖客户端渲染

---

## 2. 运行环境

### 2.1 基础镜像（现网 SSOT）

仓库路径：`数聚球/projects/mujoco-base/`

| 项 | 值 |
|----|-----|
| MuJoCo 版本 | `mujoco==3.6.0` |
| 许可 | >=2.1.0 无需 `mjkey.txt` |
| 无头 | `xvfb` + `start-xvfb.sh` |
| 继承 | `FROM .../mujoco-base:latest` |

容器内典型启动：

```bash
start-xvfb.sh
export DISPLAY_NUM=${DISPLAY_NUM:-:99}
```

### 2.2 本地开发

- Python 3.x + `mujoco==3.6.0`
- 或与 `mujoco-base` 镜像一致的 Docker 环境

---

## 3. Gateway 内仿真循环（伪代码）

```python
while running:
    apply_controls(session, pending_cmds)
    mujoco.mj_step(model, data)
    tick += 1
    if tick % broadcast_stride == 0:
        ws_broadcast(build_state_message(data, tick))
    recorder.write_frame(tick, cmds, state, events)
```

---

## 4. 机甲模型（MJCF）

| 阶段 | 内容 |
|------|------|
| POC/MVP | **自建盒子机甲**（单刚体/少 geom，平地 `velocity` 驱动） |
| P1 | 对接现有人形/四足资源（如 g1 示例） |
| P2 | 多机甲、武器/技能抽象为控制通道或约束 |

模型文件规划目录：

```
mujoco/
├── models/
│   └── mechs/
├── assets/
└── scripts/
    └── headless_run.py
```

---

## 5. 控制接口

与 [03-websocket-protocol.md](03-websocket-protocol.md) 对齐：

| control_mode | MuJoCo 实现思路 |
|--------------|-----------------|
| `velocity` | 基座速度跟踪 PD / 轮式约束；POC 实现：slide x/y + hinge z + 速度舵机（`models/mechs/box_mech.xml`）。**注意**：slide 关节平移轴在父系（世界系），Gateway 须按当前 yaw 把机体系 cmd 旋转后再写 `ctrl`（见 `mujoco/scripts/headless_run.py`） |
| `target_pose` | 操作空间目标 + IK |
| `joint_targets` | 直接写 actuator / position control |

MVP 建议从 `velocity` 或少量关节 `joint_targets` 开始。

---

## 6. 场景契约实例化

Gateway 读取 [02-scene-contract.md](02-scene-contract.md)：

1. 加载基础 MJCF（地面 + 机甲）
2. 按 `static_obstacles` 追加 geom 或 merge 子 XML（T2.3 已实现：MjSpec 追加 box geom）
3. 注册 `entity_id` → body/qpos 地址映射
4. `reset(seed)` 保证可复现

T2.3 落地要点（`gateway/echo_server.py::_build_mujoco_world`）：

- 用 `MjSpec.from_file` 加载基础 MJCF，按契约向 `worldbody` 追加静态 geom
- 契约 `size` 是 Z-up **[x, y, z] 全边长**；MJCF geom `size` 是半长，入库时除 2
- 只处理 `physics_role=mujoco_authoritative` 且 `shape=box` 的障碍；其余跳过并告警
- 经 MjSpec 追加的 geom **不继承** box_mech.xml 的 `<default>`，
  须显式设置 `contype=1 conaffinity=1 friction=[0.8 0.02 0.01]`
- 验收：机甲以 vx=1.5 冲向 wall_01（x=5），停于 x≈4.65（0.25 机体半长 + 0.1 墙半深）

---

## 7. 参考实现

| 路径 | 可借鉴点 |
|------|----------|
| `pms-system/platform/viser-gateway/examples/mujoco_g1/` | MuJoCo + 网关/可视化模式 |
| `demos/*/unitree_rl_mjlab/` | 仿真目录结构与第三方 MJCF |

MineWorld 网关可复用「Python + MuJoCo step + WS」模式；**Viewer 由 Godot 承担**，不必强绑 viser。

---

## 8. 确定性

- 固定 `dt`、固定 `seed`、契约版本哈希写入录制头
- 版本升级时记录 `mujoco_version` 与 `model_hash`

---

## 9. 检查清单

- [x] 本机或容器可 `mj_step` 无头运行（`mujoco==3.6.0`，venv）
- [x] 单机甲 + 平地 10s 仿真稳定（`headless_run.py` → T2.1 PASS）
- [x] 外部 `ctrl` 向量可改变关节/基座行为（速度舵机跟踪，三组配置）
- [ ] 状态可序列化为 JSON 供 WS 发送
