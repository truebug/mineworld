# 3DGS room skins (same-origin `.spz`)

Hosted under `/media/splats/` — not packed into Godot `.pck`. Load via `?splat=<name>&splatOn=1`.

| File | Source | Size | Notes |
|------|--------|------|-------|
| `lab3.spz` | DISCOVERSE / mine-world-xr walk-in | ~3.0MB | Small study; PoC |
| `igs0047.spz` | InteriorGS `0047_839892` via Spark `transcodeSpz` | ~5.1MB | Larger indoor; chessroom preferred |
| `igs0047.occupancy.json` | InteriorGS occupancy (entry/ground) | tiny | arm-parity mount; not optional for igs fit |

Transcode:

```bash
# cwd = mine-world-arm/web (has @sparkjsdev/spark)
node scripts/ply_to_spz.mjs path/to/in.ply path/to/mineworld/godot/spike/web/media/splats/NAME.spz
```

Chessroom smoke URL:

`https://playground.dev.databall.tech/?splat=igs0047&splatOn=1&room=chess`

Ledger: repo root `ASSETS.md`.
