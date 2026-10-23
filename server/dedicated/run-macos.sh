#!/bin/bash
# Dedicated room server on a Mac: the macOS server export ("SERVER Rally Fans
# Simulator", its own icon) run headless as an invisible room host
# (game/scripts/net/dedicated.gd, docs/DEDICATED_SERVER.md).
#   npm run build:macos-server
#   RALLY_DEDICATED_TOKEN=… server/dedicated/run-macos.sh --stage=3 --room=C0FFEE
# The key may also live in ~/.rally-dedicated-token (chmod 600). Arguments go to
# the game as they are; RALLY_APP points at another build, such as the player's
# Rally Fans Simulator.app.
# The Mac stays awake while the server runs, and a crashed server starts again.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
app="${RALLY_APP:-$root/dist-macos-server/SERVER Rally Fans Simulator.app}"
zip="$root/dist-macos-server/SERVER Rally Fans Simulator.zip"
if [ ! -d "$app" ] && [ -z "${RALLY_APP:-}" ] && [ -f "$zip" ]; then
	ditto -x -k "$zip" "$root/dist-macos-server"
fi
if [ ! -d "$app" ]; then
	echo "No $app: build it with npm run build:macos-server" >&2
	exit 1
fi
if [ -z "${RALLY_DEDICATED_TOKEN:-}" ] && [ -f "$HOME/.rally-dedicated-token" ]; then
	RALLY_DEDICATED_TOKEN="$(tr -d '[:space:]' < "$HOME/.rally-dedicated-token")"
fi
if [ -z "${RALLY_DEDICATED_TOKEN:-}" ]; then
	echo "Set RALLY_DEDICATED_TOKEN (the Worker's DEDICATED_TOKEN) or write it to ~/.rally-dedicated-token" >&2
	exit 1
fi
export RALLY_DEDICATED_TOKEN
# The server build flushes its log by itself (project.godot, feature
# "dedicated"); another build reads override.cfg next to its executable.
if [ -n "${RALLY_APP:-}" ]; then
	cp "$root/server/dedicated/override.cfg" "$app/Contents/MacOS/override.cfg"
fi
binary="$app/Contents/MacOS/$(defaults read "$app/Contents/Info" CFBundleExecutable)"
trap 'exit 0' INT TERM
while true; do
	caffeinate -i "$binary" --headless -- --dedicated "$@" || true
	echo "[run-macos] the server stopped; starting it again in 5 s (Ctrl+C to quit)"
	sleep 5
done
