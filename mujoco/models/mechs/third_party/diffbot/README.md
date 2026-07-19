# Third-party DiffBot (MineWorld F5 pilot)

| Field | Value |
|-------|-------|
| **Upstream** | [ros-controls/ros2_control_demos](https://github.com/ros-controls/ros2_control_demos) Example 2 “DiffBot” / [ros2_controllers](https://github.com/ros-controls/ros2_controllers) diff_drive test bot conventions |
| **License** | Apache License 2.0 |
| **What we vendor** | Simplified **plain URDF** (boxes/cylinders only, no mesh binaries) matching the common DiffBot chassis + dual wheel + caster layout used in those demos |
| **What we add** | MineWorld planar free-plane joints (`slide_x`/`slide_y`/`yaw_z`) via `urdf_to_mjcf_planar.py` — control protocol unchanged |

Apache-2.0 requires retaining copyright notices; see `LICENSE` in this folder (SPDX excerpt + NOTICE).

This is a **skin/geometry** pilot: wheels are visual in MJCF; teleop remains body-frame velocity.
