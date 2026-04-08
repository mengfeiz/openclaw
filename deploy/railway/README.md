# Railway: Control UI `allowedOrigins`

Use this when the browser shows: `origin not allowed`.

## Git push + image rebuild (recommended)

The Docker image ships a template at:

**`/app/config/openclaw.railway.json`**

(source: `openclaw.json.example` in this folder)

1. Edit `openclaw.json.example` locally (your public `https://…` origins), commit, and push.
2. In Railway → **Variables**, set (one time):

   **`OPENCLAW_CONFIG_PATH=/app/config/openclaw.railway.json`**

3. Trigger a **new deploy** so the image is rebuilt and picks up the file.

`OPENCLAW_STATE_DIR` (e.g. `/data`) can stay as-is for sessions; config is read from `OPENCLAW_CONFIG_PATH` when set.

## Manual path (volume / SSH)

If `OPENCLAW_STATE_DIR=/data` and you do **not** set `OPENCLAW_CONFIG_PATH`, the gateway reads:

**`/data/openclaw.json`**

Copy or merge `openclaw.json.example` there, then restart.

## Verify

DevTools → Network → WS → request header `Origin:` must match an entry in `allowedOrigins`.

Docs: [Control UI](https://docs.openclaw.ai/web/control-ui)
