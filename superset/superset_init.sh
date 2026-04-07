#!/bin/bash
set -e


# If initialization has not run before, run it
if [ ! -f "/app/superset_home/.initialized" ]; then
    echo "Initializing Superset..."

    # Initialize the database
    /app/.venv/bin/superset db upgrade

    # Create admin user
    /app/.venv/bin/superset fab create-admin \
        --username "${ADMIN_USERNAME}" \
        --firstname "${ADMIN_FIRSTNAME}" \
        --lastname "${ADMIN_LASTNAME}" \
        --email "${ADMIN_EMAIL}" \
        --password "${ADMIN_PASSWORD}"

    # Initialize Superset
    /app/.venv/bin/superset init

    # Import automated assets (Dashboards, Charts, Datasets)
    if [ -d "/app/superset_home/assets" ]; then
        echo "Importing automated assets..."
        /app/.venv/bin/python /app/superset_home/assets/import_assets.py
    fi

    # Create a marker file to skip initialization on next restart
    touch /app/superset_home/.initialized
    echo "Superset initialization complete."
fi

# Hand off to the original entrypoint/command
exec /usr/bin/run-server.sh
