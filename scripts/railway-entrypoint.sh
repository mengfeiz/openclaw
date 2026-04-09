#!/usr/bin/env bash
# Railway entrypoint for OpenClaw Gateway.
#
# Runs at container startup on Railway deployments. Patches
# gateway.controlUi.allowedOrigins in the Railway config file with the
# public Railway domain so that browser WebSocket connections are not
# rejected with "origin not allowed".
#
# Environment variables consumed:
#   RAILWAY_PUBLIC_DOMAIN      - Public domain assigned by Railway (e.g. foo.up.railway.app)
#   RAILWAY_ENVIRONMENT_NAME   - Set by Railway in all environments (used for detection)
#   OPENCLAW_CONFIG_PATH       - Overrides the config file path read by the gateway
#
# The script is idempotent: it only appends the origin when it is not already
# present, and it preserves all existing config values.

set -euo pipefail

RAILWAY_CONFIG_FILE="/app/config/openclaw.railway.json"

# ── Railway detection ────────────────────────────────────────────────────────
# RAILWAY_ENVIRONMENT_NAME is injected by Railway into every service container.
# Fall back to checking RAILWAY_PUBLIC_DOMAIN as a secondary signal.
if [ -z "${RAILWAY_ENVIRONMENT_NAME:-}" ] && [ -z "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  echo "[railway-entrypoint] Not running on Railway — skipping config patch."
  exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
fi

echo "[railway-entrypoint] Railway environment detected."

# ── Resolve the public domain ────────────────────────────────────────────────
DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-}"
if [ -z "$DOMAIN" ]; then
  echo "[railway-entrypoint] RAILWAY_PUBLIC_DOMAIN is not set — skipping allowedOrigins patch."
else
  ORIGIN="https://${DOMAIN}"
  echo "[railway-entrypoint] Patching allowedOrigins with origin: ${ORIGIN}"

  # Use Node.js to safely parse and modify the JSON config.
  # The inline script:
  #   1. Reads the config file (creates a minimal skeleton if missing).
  #   2. Ensures gateway.controlUi.allowedOrigins exists.
  #   3. Appends the origin only when not already present (idempotent).
  #   4. Writes the result back atomically via a temp file + rename.
  node - "$RAILWAY_CONFIG_FILE" "$ORIGIN" <<'EOF'
const fs = require('fs');
const path = require('path');

const [,, configFile, origin] = process.argv;

// Read existing config or start from an empty object.
let raw = '{}';
try {
  raw = fs.readFileSync(configFile, 'utf8');
} catch (err) {
  if (err.code !== 'ENOENT') throw err;
  console.error(`[railway-entrypoint] Config file not found at ${configFile} — creating from scratch.`);
}

let cfg;
try {
  cfg = JSON.parse(raw);
} catch (err) {
  console.error(`[railway-entrypoint] Failed to parse config JSON: ${err.message}`);
  process.exit(1);
}

// Ensure nested path exists.
if (!cfg.gateway || typeof cfg.gateway !== 'object') cfg.gateway = {};
if (!cfg.gateway.controlUi || typeof cfg.gateway.controlUi !== 'object') cfg.gateway.controlUi = {};
if (!Array.isArray(cfg.gateway.controlUi.allowedOrigins)) cfg.gateway.controlUi.allowedOrigins = [];

const existing = cfg.gateway.controlUi.allowedOrigins;
const normalizedOrigin = origin.toLowerCase();
const alreadyPresent = existing.some((o) => typeof o === 'string' && o.toLowerCase() === normalizedOrigin);

if (alreadyPresent) {
  console.error(`[railway-entrypoint] Origin ${origin} already present in allowedOrigins — no change needed.`);
  process.exit(0);
}

existing.push(origin);
console.error(`[railway-entrypoint] Added ${origin} to gateway.controlUi.allowedOrigins.`);

// Write atomically: write to a temp file then rename.
const dir = path.dirname(configFile);
fs.mkdirSync(dir, { recursive: true });
const tmp = `${configFile}.railway-patch.tmp`;
fs.writeFileSync(tmp, JSON.stringify(cfg, null, 2) + '\n', 'utf8');
fs.renameSync(tmp, configFile);
console.error(`[railway-entrypoint] Config saved to ${configFile}.`);
EOF

fi

# ── Point the gateway at the Railway config file ─────────────────────────────
# Only set OPENCLAW_CONFIG_PATH when the caller has not already overridden it,
# so that explicit user overrides are always respected.
if [ -z "${OPENCLAW_CONFIG_PATH:-}" ]; then
  export OPENCLAW_CONFIG_PATH="$RAILWAY_CONFIG_FILE"
  echo "[railway-entrypoint] OPENCLAW_CONFIG_PATH set to ${OPENCLAW_CONFIG_PATH}"
fi

# ── Start the gateway ────────────────────────────────────────────────────────
echo "[railway-entrypoint] Starting OpenClaw gateway..."
exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
