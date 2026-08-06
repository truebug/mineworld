# playground 邻站路径（简表）

完整台账在 **g1claw**：`ops/2026-08-06-playground-route-map.md`。

| 路径 | 仓 | 备注 |
|------|-----|------|
| `/` + `wss://…/ws` | **本仓** mineworld | Godot + MuJoCo Gateway |
| `/xr/` | mine-world-xr | 共用 `/ws`；静态 `dist/xr/` |
| `/arm/` `/arm-ws` | mine-world-arm | WS → databall01 `10.200.0.2:8766` |
| `/g1/` `/g1-ws` | g1claw | **预留**；WS → PC2 `10.200.0.10:8100`；静态建议 `dist/g1/` |

发版 **禁止** 对 `/opt/mineworld` 使用整树 `rsync --delete`。
