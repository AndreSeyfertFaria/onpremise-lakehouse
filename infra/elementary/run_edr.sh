#!/bin/bash

# Wait for Trino to be ready before starting loop
sleep 10

# Create a directory for the report
mkdir -p /app/report

# Generate the report initially and then every 2 minutes
while true; do
  echo "Generating Elementary report..."
  # The dbt project and profiles are mounted at /dbt
  edr report --project-dir /dbt --profiles-dir /dbt --file-path /app/report/index.html

  if [ $? -eq 0 ]; then
      echo "Report generated successfully."
  else
      echo "WARNING: Failed to generate report. Is Trino available and dbt project initialized?"
  fi
  sleep 120

done