# Repository Guidelines

MineWorld bridges a Godot 4 world editor with a headless MuJoCo physics authority over WebSocket, for simulation gameplay and teleoperation data capture. Docs are Chinese SSOT. POC + Hub（母港 · H12a–g）+ Portal + E1–E5 + W1 + R3 + H8–H12 + PL2 + IL-place 飞轮 Done. **Role：数聚球 3D 传送门前台** — `docs/21-ecosystem-federation.md`. **Hub 布局** — `docs/24-hub-mothership.md`（FakeMech；不上 Hub MuJoCo）。**Now：W2 公网** — `docs/23-public-deploy.md`（databall.cloud；待 DNS）。Changelog: `docs/19-changelog.md`. Platform: `docs/20-platform-portal.md`, `mw_platform/`. Identity map: `docs/22-identity-mapping.md`.

## Project Structure & Module Organization

- `docs/` — design docs (`00` … `25-qa-local-export.md`); `09-todo.md` execution; **`16` V-sprint**; **`18` Hub**; **`19` changelog**; **`20` portal**; **`21` 生态对接**; **`24` 母港布局**; **`25` 本地 Web 验收 + City 踩坑**. 私有运维：`docs/ops.local.md`（**gitignore**，勿提交）。
- `mw_platform/` — identity HTTP API (SQLite; swap via `MW_PLATFORM_DB_URL`).
- `gateway/` — WebSocket gateway (`echo_server.py`), Python 3.11+, `--physics fake|mujoco`; Hub rooms force FakeMech; `recording_store.py`.
- `godot/` — spike baseline; default main scene **`demo_hub`**; doors → `demo_workshop` / `demo_city`; autoloads `MWTransition` / `MWi18n` / `MWFonts`（Noto SC）; `?menu=1` text lobby.
- `gdevelop/` — archived legacy.
- `mujoco/` — MJCF + headless scripts; DiffBot + arm/gripper for workshop.
- `schemas/` — JSON Schema SSOT (`*.v0.json`).
- `examples/` — contracts / WS / recordings samples (incl. `demo_hub`).
- `scripts/` — smoke, web serve, city-block gen, trajectory export, hub presence, `journey_smoke.py`.

## Build, Test, and Development Commands

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r gateway/requirements.txt    # install deps (websockets)
python gateway/echo_server.py              # serve ws://127.0.0.1:8765
python scripts/ws_smoke_test.py            # end-to-end check, expect "smoke OK"
python scripts/platform_smoke.py         # platform identity API
python scripts/grasp_lift_smoke.py       # P1a friction grasp (MuJoCo)
python scripts/bc_offline_check.py --csv examples/il/bc_sample.csv  # P1b
python scripts/admin_ops_smoke.py        # PL2 admin rooms/level toggle
python scripts/il_place_smoke.py         # IL: record place → export → BC
python scripts/journey_smoke.py          # C3: login → city success → score/me/lb
python mw_platform/api_server.py         # standalone :8090 (optional)
ajv validate -s schemas/ws-messages.v0.json -d examples/ws/hello.json
```
### Local Web + Portal login

```bash
bash scripts/export_godot.sh web
bash scripts/serve_web.sh restart
# http://127.0.0.1:8080/portal/           # Landing（E1）
# http://127.0.0.1:8080/portal/login.html  (demo / demo)
# → /portal/me.html Profile+榜 → Enter hangar → /
# MW_PLATFORM_AUTH=0  disables login gate for dev
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
