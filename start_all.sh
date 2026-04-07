#!/bin/bash
# start_all.sh
# Master startup script for the Logistics Data Platform
# Coordinates the entire setup (System -> Infra -> Terraform -> Streaming -> Connectors)

# Exit on error
set -e

echo -e "\033[0;36m==========================================================\033[0m"
echo -e "\033[0;36mSTARTING LOGISTICS DATA PLATFORM\033[0m"
echo -e "\033[0;36m==========================================================\033[0m"
echo ""

# 1. Start Source System
echo -e "\033[0;33m1. Starting Source System (Postgres, Engine, Dashboard)...\033[0m"
cd source_system
docker-compose up -d
cd ..
echo -e "   OK\n"

# 2. Start Infra Stack
echo -e "\033[0;33m2. Starting Infra Stack (LocalStack, Trino)...\033[0m"
cd infra
docker-compose up -d
cd ..
echo -e "   OK\n"

# 3. Wait for LocalStack
echo -e "\033[0;33m3. Waiting for LocalStack to be ready...\033[0m"
MAX_WAIT=60
ELAPSED=0
until $(curl --output /dev/null --silent --head --fail http://localhost:4566/_localstack/health); do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo -e "   \033[0;31mLocalStack taking too long. Continuing anyway...\033[0m"
        break
    fi
    echo -ne "   ...waiting ($ELAPSED""s)\r"
    sleep 5
    ELAPSED=$((ELAPSED+5))
done
echo -e "   \033[0;32mLocalStack is ready!\033[0m\n"

# 4. Terraform Apply
echo -e "\033[0;33m4. Applying Terraform to create S3 Buckets...\033[0m"
cd infra/terraform
terraform init
terraform apply -auto-approve
cd ../..
echo -e "   OK\n"

# 5. Start Streaming Stack
echo -e "\033[0;33m5. Starting Streaming Stack (Kafka, Kafka Connect)...\033[0m"
cd streaming
echo -e "\033[0;90m   Building Kafka Connect image (first time may take 3-5 mins)...\033[0m"
docker-compose build kafka-connect
docker-compose up -d
echo -e "   OK\n"

# 6. Register Connectors
echo -e "\033[0;33m6. Registering Kafka Connectors...\033[0m"
bash register_connectors.sh
cd ..
echo -e "   OK\n"

echo -e "\033[0;32m==========================================================\033[0m"
echo -e "\033[0;32mALL SYSTEMS GO!\033[0m"
echo -e "\033[0;32m==========================================================\033[0m"
echo ""
echo "Access URLs:"
echo -e "\033[0;90m   - Logistics Dashboard: http://localhost:8501\033[0m"
echo -e "\033[0;90m   - Trino SQL Engine:    http://localhost:8080\033[0m"
echo -e "\033[0;90m   - LocalStack S3:      http://localhost:4566\033[0m"
echo ""
echo -e "\033[0;36mTry querying data in DBeaver (Trino) now!\033[0m"
