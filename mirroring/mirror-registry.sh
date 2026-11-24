#!/bin/sh
# Wrapper for mirror-registry.mjs (Node.js), so existing ./mirroring/mirror-registry.sh commands keep working.
# All logic lives in mirror-registry.mjs; run with --help for usage.
if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js 18+ is required to run mirror-registry (https://nodejs.org)" >&2
  exit 1
fi
exec node "$(dirname "$0")/mirror-registry.mjs" "$@"
