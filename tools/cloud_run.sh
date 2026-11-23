#!/usr/bin/env bash
# Run a Luau script on a real Roblox server for the published place
# (Open Cloud Luau Execution API) and print its return values + server logs.
#
# Usage:
#   tools/cloud_run.sh tests/cloud/Boot.luau [timeoutSeconds]
#   VERSION=12 tools/cloud_run.sh tests/cloud/Boot.luau   # test a saved (not live) version
#
# Needs an API key with the luau-execution-session (write) permission for this
# experience. The key is read from ROBLOX_API_KEY (or injected by a proxy).
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT_FILE="${1:?usage: tools/cloud_run.sh <script.luau> [timeoutSeconds]}"
TIMEOUT="${2:-120}"
source tools/place.env
KEY="${ROBLOX_API_KEY:-set-by-proxy}"
API="https://apis.roblox.com/cloud/v2"

BODY=$(python3 -c 'import json,sys; print(json.dumps({"script": open(sys.argv[1], encoding="utf-8").read(), "timeout": sys.argv[2] + "s"}))' "$SCRIPT_FILE" "$TIMEOUT")
TARGET="$API/universes/$UNIVERSE_ID/places/$PLACE_ID"
if [ -n "${VERSION:-}" ]; then
	TARGET="$TARGET/versions/$VERSION"
fi
TASK=$(curl -sS --fail-with-body -X POST "$TARGET/luau-execution-session-tasks" \
	-H "x-api-key: $KEY" -H "Content-Type: application/json" --data "$BODY")
TASK_PATH=$(echo "$TASK" | python3 -c 'import json,sys; print(json.load(sys.stdin)["path"])')
echo "task: $TASK_PATH"

STATE=""
RESULT=""
for _ in $(seq 1 $((TIMEOUT / 3 + 10))); do
	RESULT=$(curl -sS "$API/$TASK_PATH" -H "x-api-key: $KEY")
	STATE=$(echo "$RESULT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state",""))')
	if [ "$STATE" != "PROCESSING" ] && [ "$STATE" != "QUEUED" ]; then
		break
	fi
	sleep 3
done

echo "state: $STATE"
echo "$RESULT" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in (d.get("output") or {}).get("results", []):
    print("result:", r)
if d.get("error"):
    print("error:", json.dumps(d["error"], ensure_ascii=False))
'
echo "--- logs"
curl -sS "$API/$TASK_PATH/logs?view=STRUCTURED&maxPageSize=10000" -H "x-api-key: $KEY" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for page in d.get("luauExecutionSessionTaskLogs", []):
    for m in page.get("structuredMessages", []):
        print("[%s] %s" % (m.get("messageType", "?"), m.get("message", "")))
    for m in page.get("messages", []):
        print(m)
'
[ "$STATE" = "COMPLETE" ]
