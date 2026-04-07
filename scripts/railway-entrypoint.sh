#!/usr/bin/env bash
# Railway entrypoint — auto-configures gateway.controlUi.allowedOrigins
# from RAILWAY_PUBLIC_DOMAIN before starting the OpenClaw gateway.
#
# Usage (Railway start command):
#   /app/scripts/railway-entrypoint.sh
#
# The script detects a Railway deployment via RAILWAY_ENVIRONMENT_NAME or
# RAILWAY_PUBLIC_DOMAIN, injects the public HTTPS origin into the OpenClaw
# config file so the Control UI WebSocket handshake is not rejected with
# "origin not allowed", then exec-replaces itself with the gateway process.
#
# If neither Railway env var is set the script is a transparent pass-through
# and simply starts the gateway unchanged.
set -euo pipefail

# ── Resolve config file path ────────────────────────────────────────────────
# Mirror the precedence used by OpenClaw itself:
#   1. OPENCLAW_CONFIG_PATH (explicit override)
#   2. $OPENCLAW_STATE_DIR/openclaw.json
#   3. $HOME/.openclaw/openclaw.json  (default)
resolve_config_path() {
  if [[ -n "${OPENCLAW_CONFIG_PATH:-}" ]]; then
    printf '%s' "$OPENCLAW_CONFIG_PATH"
    return
  fi
  local state_dir="${OPENCLAW_STATE_DIR:-}"
  if [[ -z "$state_dir" ]]; then
    state_dir="${HOME:-/home/node}/.openclaw"
  fi
  printf '%s/openclaw.json' "$state_dir"
}

CONFIG_PATH="$(resolve_config_path)"

# ── Detect Railway ───────────────────────────────────────────────────────────
RAILWAY_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-}"

if [[ -z "$RAILWAY_DOMAIN" && -z "${RAILWAY_ENVIRONMENT_NAME:-}" ]]; then
  # Not running on Railway — start gateway directly.
  exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
fi

if [[ -z "$RAILWAY_DOMAIN" ]]; then
  echo "railway-entrypoint: RAILWAY_ENVIRONMENT_NAME is set but RAILWAY_PUBLIC_DOMAIN is empty." >&2
  echo "railway-entrypoint: Cannot auto-configure allowedOrigins without a public domain." >&2
  echo "railway-entrypoint: Set RAILWAY_PUBLIC_DOMAIN or configure gateway.controlUi.allowedOrigins manually." >&2
  exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
fi

RAILWAY_ORIGIN="https://${RAILWAY_DOMAIN}"
echo "railway-entrypoint: detected Railway deployment (domain=${RAILWAY_DOMAIN})"

# ── Patch openclaw.json ──────────────────────────────────────────────────────
# Use Node.js (always available in the image) to safely merge the Railway
# origin into gateway.controlUi.allowedOrigins without clobbering any other
# config the user may have set.  The merge is idempotent: re-running with the
# same domain is a no-op.
patch_config() {
  local config_path="$1"
  local origin="$2"

  node - "$config_path" "$origin" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const configPath = process.argv[2];
const origin = process.argv[3];

// Read existing config (or start from empty object).
let cfg = {};
try {
  cfg = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch (err) {
  if (err.code !== "ENOENT") {
    process.stderr.write(
      `railway-entrypoint: warning: could not read ${configPath}: ${err.message}\n`,
    );
  }
}

// Navigate / create the nested path: gateway.controlUi.allowedOrigins
if (!cfg.gateway || typeof cfg.gateway !== "object") {
  cfg.gateway = {};
}
if (!cfg.gateway.controlUi || typeof cfg.gateway.controlUi !== "object") {
  cfg.gateway.controlUi = {};
}

const existing = cfg.gateway.controlUi.allowedOrigins;
const existingOrigins = Array.isArray(existing) ? existing : [];

if (existingOrigins.includes(origin)) {
  process.stdout.write(
    `railway-entrypoint: gateway.controlUi.allowedOrigins already contains ${origin} — no change needed.\n`,
  );
  process.exit(0);
}

cfg.gateway.controlUi.allowedOrigins = [...existingOrigins, origin];

// Ensure the directory exists before writing.
const dir = path.dirname(configPath);
fs.mkdirSync(dir, { recursive: true });
fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + "\n", "utf8");

process.stdout.write(
  `railway-entrypoint: added ${origin} to gateway.controlUi.allowedOrigins in ${configPath}\n`,
);
NODE
}

patch_config "$CONFIG_PATH" "$RAILWAY_ORIGIN"

# ── Start gateway ────────────────────────────────────────────────────────────
exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
