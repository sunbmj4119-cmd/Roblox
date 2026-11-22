#!/usr/bin/env bash
# Build the place with Rojo and publish it to Roblox with the Open Cloud
# Place Publishing API - no Studio needed after the experience exists.
#
# Usage:
#   ROBLOX_API_KEY=xxxx tools/publish.sh <universeId> <placeId> [Published|Saved]
#
# The API key needs the place-write permission (universe-places / Write)
# for this experience. Create it at Creator Hub -> Open Cloud -> API Keys.
# "Saved" uploads a version without making it live; "Published" makes it live.
set -euo pipefail

UNIVERSE_ID="${1:?usage: tools/publish.sh <universeId> <placeId> [Published|Saved]}"
PLACE_ID="${2:?usage: tools/publish.sh <universeId> <placeId> [Published|Saved]}"
VERSION_TYPE="${3:-Published}"

cd "$(dirname "$0")/.."

# safety checks before anything goes live
if command -v stylua >/dev/null 2>&1; then
	stylua --check src >/dev/null 2>/tmp/stylua_err.txt || true
	if grep -qi "error" /tmp/stylua_err.txt; then
		echo "Syntax error found - not publishing:"
		cat /tmp/stylua_err.txt
		exit 1
	fi
fi
if command -v lune >/dev/null 2>&1; then
	lune run tests/ConfigCheck.luau
	lune run tests/ApiCheck.luau
fi

rojo build default.project.json -o MeteorMiners.rbxlx

echo "Publishing to universe ${UNIVERSE_ID}, place ${PLACE_ID} (${VERSION_TYPE})..."
curl -sS --fail-with-body -X POST \
	"https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=${VERSION_TYPE}" \
	-H "x-api-key: ${ROBLOX_API_KEY:-set-by-proxy}" \
	-H "Content-Type: application/xml" \
	--data-binary @MeteorMiners.rbxlx
echo
echo "Done. Leave the game and rejoin to get the new version."
