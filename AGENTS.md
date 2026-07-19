# Repository Guidelines

MineWorld bridges a Godot 4 world editor with a headless MuJoCo physics authority over WebSocket, for simulation gameplay and teleoperation data capture. The project is at POC stage: `schemas/` and `docs/` are the source of truth, and design docs are written in Chinese — keep new docs consistent. The client engine was switched from GDevelop to Godot (see `docs/adr/003-client-engine-godot.md`); `gdevelop/` is archived legacy. Local Web single-player and `demo` room multiplayer are done (`docs/13-web-multiplayer-demo.md`); current focus is **Godot scene ↔ MuJoCo fusion** (visual parity, URDF/MJCF mech swap — `docs/14-godot-mujoco-fusion.md`). Public HTTPS/wss and feel/latency (T2.7) remain deferred.

## Project Structure & Module Organization

- `docs/` — design docs (`00-vision.md` … `14-godot-mujoco-fusion.md`); decisions in `docs/adr/`; `docs/09-todo.md` is the execution entry point.
- `gateway/` — WebSocket gateway (`echo_server.py`), Python 3.11+, dual physics backends (`--physics fake|mujoco`). MuJoCo mode (T2.2) loads MJCF and appends contract `static_obstacles` as static geoms (T2.3).
- `godot/` — Godot client projects; `spike/` is the verified baseline (`project.godot` + `*.tscn` + `*.gd`). Main demo: `demo_city.tscn` (Kenney city decor + authoritative curbs/chicanes/finish). Also `main.tscn` (tutorial_01) and `tutorial_02.tscn`. CameraRig: follow-orbit, RMB/MMB drag, wheel zoom.
- `gdevelop/` — archived GDevelop POC-A project (`demo0/`); do not extend.
- `mujoco/` — MJCF models (`models/mechs/box_mech.xml`, `models/world_flat.xml`) and headless scripts (`scripts/headless_run.py`). Mech is slide x/y + hinge z + velocity servos.
- `schemas/` — JSON Schema SSOT (draft 2020-12), files named `*.v0.json`.
- `examples/` — sample contracts, WS messages, and recordings used for validation.
- `scripts/` — helper scripts (`ws_smoke_test.py`).

## Build, Test, and Development Commands

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt    # install deps (websockets)
python gateway/echo_server.py              # serve ws://127.0.0.1:8765
python scripts/ws_smoke_test.py            # end-to-end check, expect "smoke OK"
ajv validate -s schemas/ws-messages.v0.json -d examples/ws/hello.json
```
### MuJoCo acceptance (T2.1–T2.3, run from repo root)

```bash
.venv/bin/python mujoco/scripts/headless_run.py              # T2.1 PASS
.venv/bin/python gateway/echo_server.py --physics mujoco     # serve with real physics
.venv/bin/python scripts/ws_smoke_test.py                    # regression → smoke OK
.venv/bin/python scripts/replay_xy.py recordings/sessions/<id>/frames.jsonl  # replay tool
```

`ajv` requires `npm i -g ajv-cli ajv-formats`; add `-c ajv-formats` for schemas using formats.

## Coding Style & Naming Conventions

- Python: PEP 8, 4-space indent, type hints with `from __future__ import annotations`, dataclasses for state, `UPPER_SNAKE_CASE` constants, loggers named `mineworld.<module>`.
- Docs: numbered `NN-topic.md` under `docs/`; ADRs `NNN-title.md` under `docs/adr/`.
- Schemas: bump compatible additions in place; breaking changes go into a new `*.v1.json`.

## Testing Guidelines

No unit-test framework is configured yet. Every gateway change must pass `python scripts/ws_smoke_test.py`; every schema change must pass `ajv validate` against the matching `examples/` file. Add a sample JSON under `examples/` when introducing new message types.

## Commit & Pull Request Guidelines

- Conventional Commits with scope, as in history: `feat(gateway): add echo server`, `docs: freeze POC decisions`.
- PRs: state intent, link task IDs from `docs/09-todo.md` (e.g. T1.3), paste validation output (`smoke OK`, ajv results), and attach Godot screenshots for scene changes.

## Schema & Configuration Rules

- `schemas/` is the SSOT: consumers must ignore unknown keys, put extensions in the `extensions` bag (`vendor.*` / `mw.*`), and never set `additionalProperties: false` on v0 payloads.
- Coordinates are meters, right-handed, Z-up; frozen rates: `dt=0.02`, sim 50 Hz, state broadcast 20 Hz.
- Godot→MuJoCo coordinate mapping (see `godot/spike/scripts/mech_puppet.gd`):
  `godot_pos = Vector3(mw.x, mw.z, -mw.y)` and `rotation.y = mw.yaw`.
- Never commit `.venv/`, `recordings/`, or `gdevelop/**/Exported/`; bind the gateway to `127.0.0.1` for local dev.
- Third-party assets: only CC0/MIT (CC-BY requires attribution); every asset commit must include an `ASSETS.md` ledger entry — never commit NC/SA-licensed content.
