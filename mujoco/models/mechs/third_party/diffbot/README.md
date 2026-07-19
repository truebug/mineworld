# Third-party DiffBot (MineWorld F5)

| Field | Value |
|-------|-------|
| **Upstream** | [ros-controls/ros2_control_demos](https://github.com/ros-controls/ros2_control_demos) `ros2_control_demo_description/diffbot/` |
| **Revision** | `1c5c4399a66302987af83684469fe9fde42a0e67` |
| **License** | Apache License 2.0 (`LICENSE`) |
| **Vendored as-is** | `urdf/*.xacro`, `rviz/*.rviz` |
| **Derived** | `diffbot.urdf` — plain URDF (prefix="") from xacro, **geometry ×10** (~1 m footprint) for POC visibility |
| **MineWorld add** | Planar joints + F6 wheels; F8 Godot visual JSON from same URDF |

This is a **skin/geometry** pilot: wheels/casters are visual in MJCF; teleop remains body-frame velocity.
