#!/bin/bash
# detect_fresh_start.sh
# Runs on LocalStack startup to check if state persists.

# Path inside LocalStack container
DATA_DIR="/var/lib/localstack/data"
SIGNAL_FILE="/signals/reset_required"

echo "[LocalStack Init] Checking for existing S3 data..."

# If data directory is empty or missing 'recorded_api_calls.json' (typical persistence marker), 
# then it's a fresh start.
if [ ! -d "$DATA_DIR" ] || [ -z "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
    echo "[LocalStack Init] Fresh start detected! Signaling Iceberg Catalog Reset..."
    mkdir -p /signals
    touch "$SIGNAL_FILE"
else
    echo "[LocalStack Init] Persistent data found. No reset needed."
fi
