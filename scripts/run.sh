#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
killall NotesTool 2>/dev/null || true
open ./NotesTool.app
echo "Launched NotesTool — look for the note icon in the menu bar."
