#!/usr/bin/env bash
# register_connectors.sh
# Waits for Kafka Connect to be ready, then registers all three connectors.
# Run this AFTER: docker-compose up -d

set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTORS_DIR="$(dirname "$0")/connectors"
STREAMING_ENV="$(dirname "$0")/.env"
MAX_WAIT=120   # seconds to wait for Kafka Connect to become healthy
INTERVAL=5

if [[ -f "${STREAMING_ENV}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${STREAMING_ENV}"
  set +a
fi

# Wait for Kafka Connect
echo "[WAIT] Waiting for Kafka Connect to be ready at ${CONNECT_URL} ..."
elapsed=0
until curl -sf "${CONNECT_URL}/" > /dev/null 2>&1; do
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "[ERROR] Kafka Connect did not become ready within ${MAX_WAIT}s. Aborting."
    exit 1
  fi
  echo "   ... still waiting (${elapsed}s elapsed)"
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done
echo "[OK] Kafka Connect is ready!"
echo ""

# Register / Update a connector
register_connector() {
  local file="$1"
  local name
  local rendered
  local config
  rendered=$(python3 - "$file" <<'PY'
import json
import os
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    raw = fh.read()

required = {
    "__POSTGRES_USER__": os.getenv("POSTGRES_USER"),
    "__POSTGRES_PASSWORD__": os.getenv("POSTGRES_PASSWORD"),
    "__POSTGRES_DB__": os.getenv("POSTGRES_DB"),
}

for token, value in required.items():
    if token in raw:
        if not value:
            raise SystemExit(f"Missing required environment value for {token}")
        raw = raw.replace(token, value)

doc = json.loads(raw)
print(json.dumps({"name": doc["name"], "config": doc["config"]}))
PY
)
  name=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['name'])" "$rendered")
  config=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(json.dumps(d['config']))" "$rendered")

  echo "[REGISTER] ${name}"

  # Use PUT to handle both create and update idempotently
  http_code=$(curl -s -o /tmp/connect_response.json -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: application/json" \
    --data "${config}" \
    "${CONNECT_URL}/connectors/${name}/config")

  if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
    echo "   [OK] ${name} registered (HTTP ${http_code})"
  else
    echo "   [ERROR] Failed to register ${name} (HTTP ${http_code})"
    cat /tmp/connect_response.json
    exit 1
  fi
}

# Register all connectors (ORDER MATTERS: source must be first)
register_connector "${CONNECTORS_DIR}/debezium-postgres-source.json"
sleep 3   # give the source connector a moment to initialise
register_connector "${CONNECTORS_DIR}/s3-sink-cdc.json"
register_connector "${CONNECTORS_DIR}/s3-sink-telemetry.json"

echo ""
echo "[DONE] All connectors registered! Checking status..."
echo ""

# Status check
for connector in logistics-postgres-source s3-sink-cdc s3-sink-telemetry; do
  echo "--- ${connector} ---"
  curl -sf "${CONNECT_URL}/connectors/${connector}/status" | \
    python3 -c "
import json, sys
d = json.load(sys.stdin)
state = d['connector']['state']
tasks = d.get('tasks', [])
mark = '[OK]' if state == 'RUNNING' else '[WARN]'
print(f'  Connector: {mark} {state}')
for t in tasks:
    tm = '[OK]' if t['state'] == 'RUNNING' else '[WARN]'
    print(f'  Task {t[\"id\"]}: {tm} {t[\"state\"]}')
"
  echo ""
done

echo "Done. Monitor logs with:"
echo "  docker logs -f kafka_connect"
