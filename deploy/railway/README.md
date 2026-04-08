# Railway: Control UI `allowedOrigins`

Use this when the browser shows: `origin not allowed`.

## 1. Config file path on the container

If `OPENCLAW_STATE_DIR=/data` (matches `fly.toml` / many Railway setups), the gateway reads:

**`/data/openclaw.json`**

If you set `OPENCLAW_CONFIG_PATH`, that path wins instead.

## 2. Apply the example

- Copy `openclaw.json.example` to the server as `/data/openclaw.json`, **or**
- Merge its `gateway.controlUi` object into your existing `openclaw.json`.

Replace the URL in `allowedOrigins` with the exact origin you use in the browser (include `https://`, no path). Add more entries for custom domains.

## 3. Restart

Redeploy or restart the Railway service so the gateway reloads config.

## 4. Verify

Open DevTools → Network → WS → check the request header `Origin:` matches an entry in `allowedOrigins`.

Docs: [Control UI](https://docs.openclaw.ai/web/control-ui)
