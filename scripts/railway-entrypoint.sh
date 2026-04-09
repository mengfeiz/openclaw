#!/usr/bin/env bash
# Railway startup entrypoint for OpenClaw.
#
# Detects the Railway public domain from environment variables and injects it
# into gateway.controlUi.allowedOrigins in the config file before starting
# the gateway. This ensures WebSocket connections from the browser are not
# rejected with "origin not allowed" on Railway deployments.
#
# Usage (Railway start command or Dockerfile CMD override):
#   /app/scripts/railway-entrypoint.sh
#
# Relevant Railway environment variables:
#   RAILWAY_PUBLIC_DOMAIN        - e.g. openclaw-copy-production.up.railway.app
#   RAILWAY_ENVIRONMENT_NAME     - e.g. production
#   OPENCLAW_CONFIG_PATH         - path to the config file (default: /app/config/openclaw.railway.json)
#
# The script is idempotent: re-running it will not duplicate origins that are
# already present in the config.

set -euo pipefail

CONFIG_FILE="${OPENCLAW_CONFIG_PATH:-/app/config/openclaw.railway.json}"

# ── Detect Railway environment ───────────────────────────────────────────────

RAILWAY_DOMAIN="${RAILWAY_PUBLIC_DOMAIN:-}"
RAILWAY_ENV="${RAILWAY_ENVIRONMENT_NAME:-}"

if [[ -z "$RAILWAY_DOMAIN" && -z "$RAILWAY_ENV" ]]; then
  echo "[railway-entrypoint] Not running on Railway (RAILWAY_PUBLIC_DOMAIN and RAILWAY_ENVIRONMENT_NAME are unset). Skipping config patch." >&2
  exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
fi

if [[ -z "$RAILWAY_DOMAIN" ]]; then
  echo "[railway-entrypoint] Warning: RAILWAY_ENVIRONMENT_NAME is set but RAILWAY_PUBLIC_DOMAIN is empty. Cannot inject allowedOrigins." >&2
  exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
fi

# Normalise: strip any leading https:// the user may have set
RAILWAY_DOMAIN="${RAILWAY_DOMAIN#https://}"
RAILWAY_DOMAIN="${RAILWAY_DOMAIN#http://}"
# Strip trailing slash
RAILWAY_DOMAIN="${RAILWAY_DOMAIN%/}"

RAILWAY_ORIGIN="https://${RAILWAY_DOMAIN}"

echo "[railway-entrypoint] Railway domain: ${RAILWAY_DOMAIN}" >&2
echo "[railway-entrypoint] Injecting origin '${RAILWAY_ORIGIN}' into ${CONFIG_FILE}" >&2

# ── Patch config file using Node.js ─────────────────────────────────────────
# Node.js is always available in the runtime image (it is the process manager).
# Using it here avoids a python3 / jq dependency and keeps JSON handling safe.

node - "$CONFIG_FILE" "$RAILWAY_ORIGIN" <<'NODE_SCRIPT'
"use strict";

const fs   = require("node:fs");
const path = require("node:path");

const [,, configFile, newOrigin] = process.argv;

if (!configFile || !newOrigin) {
  process.stderr.write("[railway-entrypoint] Usage: node <script> <config-file> <origin>\n");
  process.exit(1);
}

// ── Read existing config ────────────────────────────────────────────────────
let raw;
try {
  raw = fs.readFileSync(configFile, "utf8");
} catch (err) {
  if (err.code === "ENOENT") {
    process.stderr.write(
      `[railway-entrypoint] Config file not found: ${configFile}. Creating a minimal one.\n`
    );
    raw = "{}";
  } else {
    process.stderr.write(`[railway-entrypoint] Error reading ${configFile}: ${err.message}\n`);
    process.exit(1);
  }
}

let config;
try {
  config = JSON.parse(raw);
} catch (err) {
  process.stderr.write(
    `[railway-entrypoint] Config file is not valid JSON (${configFile}): ${err.message}. Leaving unchanged.\n`
  );
  // Non-fatal: let the gateway handle the bad config itself.
  process.exit(0);
}

if (typeof config !== "object" || config === null || Array.isArray(config)) {
  process.stderr.write(
    `[railway-entrypoint] Config file does not contain a top-level object. Leaving unchanged.\n`
  );
  process.exit(0);
}

// ── Navigate / create the nested path ──────────────────────────────────────
if (typeof config.gateway !== "object" || config.gateway === null) {
  config.gateway = {};
}
if (typeof config.gateway.controlUi !== "object" || config.gateway.controlUi === null) {
  config.gateway.controlUi = {};
}

const controlUi = config.gateway.controlUi;
const existing  = Array.isArray(controlUi.allowedOrigins) ? controlUi.allowedOrigins : [];

// Deduplicate: only add the new origin if it is not already present.
if (existing.includes(newOrigin)) {
  process.stderr.write(
    `[railway-entrypoint] Origin '${newOrigin}' is already in allowedOrigins. No change needed.\n`
  );
  process.exit(0);
}

controlUi.allowedOrigins = [...existing, newOrigin];

// ── Write atomically (tmp → rename) ────────────────────────────────────────
const dir     = path.dirname(configFile);
const tmpFile = path.join(dir, `.openclaw.railway.tmp.${process.pid}`);

try {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(tmpFile, JSON.stringify(config, null, 2) + "\n", "utf8");
  fs.renameSync(tmpFile, configFile);
} catch (err) {
  // Clean up temp file on failure.
  try { fs.unlinkSync(tmpFile); } catch (_) {}
  process.stderr.write(`[railway-entrypoint] Failed to write config: ${err.message}\n`);
  process.exit(1);
}

process.stderr.write(
  `[railway-entrypoint] Added '${newOrigin}' to gateway.controlUi.allowedOrigins in ${configFile}\n`
);
NODE_SCRIPT

# ── Start the gateway ────────────────────────────────────────────────────────
echo "[railway-entrypoint] Starting OpenClaw gateway..." >&2
exec node /app/openclaw.mjs gateway --allow-unconfigured "$@"
