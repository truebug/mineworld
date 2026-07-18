# Repository Guidelines

MineWorld bridges a Godot 4 world editor with a headless MuJoCo physics authority over WebSocket, for simulation gameplay and teleoperation data capture. The project is at POC stage: `schemas/` and `docs/` are the source of truth, and design docs are written in Chinese — keep new docs consistent. The client engine was switched from GDevelop to Godot (see `docs/adr/003-client-engine-godot.md`); `gdevelop/` is archived legacy.

## Project Structure & Module Organization

- `docs/` — design docs (`00-vision.md` … `11-poc-mvp-architecture.md`); decisions in `docs/adr/`; `docs/09-todo.md` is the execution entry point.
- `gateway/` — POC-A WebSocket gateway (`echo_server.py`), Python 3.11+, fake kinematic state (no MuJoCo yet).
- `godot/` — Godot client projects; `spike/` is the verified M1 baseline (`project.godot` + `*.tscn` + `*.gd`).
- `gdevelop/` — archived GDevelop POC-A project (`demo0/`); do not extend.
- `mujoco/` — MJCF models and headless sim scripts (placeholder).
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
- Never commit `.venv/`, `recordings/`, or `gdevelop/**/Exported/`; bind the gateway to `127.0.0.1` for local dev.
- Third-party assets: only CC0/MIT (CC-BY requires attribution); every asset commit must include an `ASSETS.md` ledger entry — never commit NC/SA-licensed content.
