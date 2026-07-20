# mw_platform — Phase A identity API

Independent HTTP API for player identity (SQLite default; swap via `MW_PLATFORM_DB_URL`).

```bash
# Standalone (port 8090)
.venv/bin/python mw_platform/api_server.py

# Same routes on game server (recommended local)
bash scripts/serve_web.sh restart
open http://127.0.0.1:8080/portal/login.html   # demo / demo
```

Env:

| Variable | Default | Notes |
|----------|---------|-------|
| `MW_PLATFORM_DB_URL` | `sqlite:///<repo>/mw_platform/data/platform.sqlite` | Future: `postgres://...` |
| `MW_PLATFORM_AUTH` | `1` | `0` disables login gate |
| `MW_PLATFORM_ADMIN_KEY` | `dev-admin` | Admin player CRUD / identity links |
| `MW_PLATFORM_GATEWAY_KEY` | falls back to admin / `mineworld-gateway-dev` | Score posts |
| `MW_PLATFORM_FEDERATION_STUB_KEY` | `dev-federation` | E2 federated stub secret |
| `MW_PLATFORM_SECRET` | dev default | Token pepper (future) |
| `MW_PLATFORM_PORT` | `8090` | Standalone api_server only |

Routes (excerpt):

| Method | Path | Notes |
|--------|------|-------|
| POST | `/api/platform/login` | password → Bearer |
| POST | `/api/platform/login/federated` | E2 stub: issuer+sub → Bearer |
| GET | `/api/platform/me` | Bearer; includes `identity_links` |
| GET | `/api/platform/leaderboard` | Top N totals |
| POST | `/api/platform/scores` | Gateway score write (`X-Gateway-Key`) |
| POST | `/api/platform/admin/identity-links` | Admin link external user |

Identity mapping SSOT: [`docs/22-identity-mapping.md`](../docs/22-identity-mapping.md).

Smoke: `.venv/bin/python scripts/platform_smoke.py`
