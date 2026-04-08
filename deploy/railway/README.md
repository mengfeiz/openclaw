# Railway: Control UI `allowedOrigins`

Use this when the browser shows: `origin not allowed`.

## Default model without OpenCode

This template sets **`agents.defaults.model`** to **`openai/gpt-5.4`**. Set **`OPENAI_API_KEY`** on Railway and ensure billing/quota is OK.

To use **Anthropic** instead, change it to e.g. **`anthropic/claude-sonnet-4-6`** (or your chosen `anthropic/…` id) and set **`ANTHROPIC_API_KEY`**.

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

## `pairing required` over WebSocket (Railway + browser)

Behind Railway, the Control UI still presents **device identity**. Until that device is **paired**, the gateway returns **`1008 pairing required`**.

**Option A – break-glass (typical for a token-gated HTTPS deploy):** set in config:

- `gateway.controlUi.dangerouslyDisableDeviceAuth: true`

This skips **device pairing** for the Control UI operator path. You **must** keep a **strong** `OPENCLAW_GATEWAY_TOKEN` and HTTPS; see [Control UI security](https://docs.openclaw.ai/web/control-ui).

This example file includes that flag and **`gateway.trustedProxies`** (`100.64.0.0/10`) so logs stop warning about proxy headers from Railway’s internal addresses. Tighten the CIDR if your host documents a smaller range.

**Option B – keep device pairing:** run on the gateway host (e.g. Railway shell):

`openclaw pairing approve ...`

using the code the UI shows (see [Pairing](https://docs.openclaw.ai/gateway/pairing)).

## Verify

DevTools → Network → WS → request header `Origin:` must match an entry in `allowedOrigins`.

Docs: [Control UI](https://docs.openclaw.ai/web/control-ui)
