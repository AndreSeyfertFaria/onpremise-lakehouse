#!/bin/bash
# auto_repair.sh
# Checks for the signal file and truncates Postgres catalog if found.

SIGNAL_FILE="/signals/reset_required"

echo "[Iceberg Maintenance] Checking for reset signal..."

if [ -f "$SIGNAL_FILE" ]; then
    echo "--------------------------------------------------------"
    echo "SIGNAL DETECTED: LocalStack has restarted into a fresh state."
    echo "Truncating Iceberg catalog to prevent 'Zombie' metadata errors."
    echo "--------------------------------------------------------"
    
    # Run the TRUNCATE command safely (checking if views exist for backwards compatibility)
    psql -h iceberg-catalog -U iceberg -d iceberg -c "
      TRUNCATE iceberg_tables, iceberg_namespaces, iceberg_namespace_properties CASCADE;
      DO \$\$ BEGIN IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'iceberg_views') THEN EXECUTE 'TRUNCATE iceberg_views CASCADE'; END IF; END \$\$;
    "
    
    if [ $? -eq 0 ]; then
        echo "[Iceberg Maintenance] SUCCESS: Catalog cleared."
        # Remove the signal file after successful reset
        rm -f "$SIGNAL_FILE"
        echo "[Iceberg Maintenance] Signal cleared."
    else
        echo "[Iceberg Maintenance] ERROR: Truncate failed. Check Postgres connectivity."
        exit 1
    fi
else
    echo "[Iceberg Maintenance] No reset required. Catalog state matches S3."
fi
