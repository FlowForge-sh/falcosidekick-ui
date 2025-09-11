#!/usr/bin/env bash
set -euo pipefail

FALCOSIDEKICK_UI_URL="http://localhost:2802/api/v1/events/add"
AUTH="-u admin:admin"   # Remove if auth is disabled

EVENT_COUNT=100       # total events
EVENTS_PER_SECOND=20  # rate limit

echo "[*] Sending $EVENT_COUNT events at $EVENTS_PER_SECOND events/sec to $FALCOSIDEKICK_UI_URL"

for i in $(seq 1 $EVENT_COUNT); do
  uuid=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '\n')
  time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  case $((RANDOM % 3)) in
    0) priority="Info" ;;
    1) priority="Warning" ;;
    2) priority="Error" ;;
  esac

  json=$(jq -n \
    --arg uuid "$uuid" \
    --arg time "$time" \
    --arg output "TEST-EVENT-$i $(date +%s)" \
    --arg rule "TestRule-$((i % 10))" \
    --arg priority "$priority" \
    --arg msg "naked-$i" \
    '{
      event: {
        uuid: $uuid,
        time: $time,
        output: $output,
        rule: $rule,
        priority: $priority,
        output_fields: {
          msg: $msg,
          nested: { foo: ("bar-" + $msg) },
          list: ["val1", "val2", "val3"]
        }
      },
      outputs: []
    }')

  response=$(curl -s -o /tmp/resp.json -w "%{http_code}" $AUTH \
    -H "Content-Type: application/json" \
    -d "$json" \
    "$FALCOSIDEKICK_UI_URL")

  if [[ "$response" == "200" ]]; then
    echo "[✓] Sent event $i ($priority): TEST-EVENT-$i"
  else
    echo "[✗] Failed to send event $i ($priority) -> $(cat /tmp/resp.json)"
  fi

  sleep $(bc <<< "scale=3; 1 / $EVENTS_PER_SECOND")
done
