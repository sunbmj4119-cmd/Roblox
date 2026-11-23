#!/usr/bin/env bash
# Safe release: upload a SAVED (not live) version, boot the real server code
# on a Roblox server with the cloud test, and only then publish it live.
#
#   tools/release.sh
#
# Needs the API key permissions: place publishing + luau-execution-session.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1/3 upload a saved (test) version"
OUT=$(tools/publish.sh "" "" Saved 2>&1 || true)
echo "$OUT" | tail -3
VERSION=$(echo "$OUT" | grep -o '"versionNumber":[0-9]*' | grep -o '[0-9]*$')
if [ -z "$VERSION" ]; then
	echo "upload failed - not releasing"
	exit 1
fi

echo "== 2/3 cloud boot test on version $VERSION"
if ! VERSION="$VERSION" tools/cloud_run.sh tests/cloud/Boot.luau 120; then
	echo "cloud test FAILED - version $VERSION stays unpublished"
	exit 1
fi

echo "== 3/3 publish live"
tools/publish.sh "" "" Published | tail -2
