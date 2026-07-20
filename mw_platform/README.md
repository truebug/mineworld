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
| `MW_PLATFORM_ADMIN_KEY` | unset | Enables admin player CRUD |
| `MW_PLATFORM_SECRET` | dev default | Token pepper (future) |
| `MW_PLATFORM_PORT` | `8090` | Standalone api_server only |

| `GET /api/platform/leaderboard` | Top N totals |
| `POST /api/platform/scores` | Gateway score write (`X-Gateway-Key`) |

Smoke: `.venv/bin/python scripts/platform_smoke.py`
