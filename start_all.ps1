# start_all.ps1
# Master startup script for the Logistics Data Platform
# Coordinates the entire setup (System -> Infra -> Terraform -> Streaming -> Connectors)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "STARTING LOGISTICS DATA PLATFORM" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Start Source System
Write-Host "1. Starting Source System (Postgres, Engine, Dashboard)..." -ForegroundColor Yellow
cd "source_system"
docker-compose up -d
cd ..
Write-Host "   OK.`n"

# 2. Start Infra Stack
Write-Host "2. Starting Infra Stack (LocalStack, Trino)..." -ForegroundColor Yellow
cd "infra"
docker-compose up -d
cd ..
Write-Host "   OK.`n"

# 3. Wait for LocalStack
Write-Host "3. Waiting for LocalStack to be ready..." -ForegroundColor Yellow
$localStackUrl = "http://localhost:4566/_localstack/health"
$elapsed = 0
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri $localStackUrl -Method Get -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Host "   LocalStack is ready!" -ForegroundColor Green
            break
        }
    } catch {}
    if ($elapsed -ge 60) { Write-Host "   LocalStack taking too long. Continuing anyway..."; break }
    Start-Sleep -Seconds 5
    $elapsed += 5
}
Write-Host ""

# 4. Terraform Apply
Write-Host "4. Applying Terraform to create S3 Buckets..." -ForegroundColor Yellow
cd "infra/terraform"
terraform init
terraform apply -auto-approve
cd ../..
Write-Host "   OK.`n"

# 5. Start Streaming Stack
Write-Host "5. Starting Streaming Stack (Kafka, Kafka Connect)..." -ForegroundColor Yellow
cd "streaming"
# Build Kafka Connect custom image (needed for plugins)
Write-Host "   Building Kafka Connect image (first time may take 3-5 mins)..." -ForegroundColor Gray
docker-compose build kafka-connect
docker-compose up -d
Write-Host "   OK.`n"

# 6. Register Connectors
Write-Host "6. Registering Kafka Connectors..." -ForegroundColor Yellow
./register_connectors.ps1
cd ..
Write-Host "   OK.`n"

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "ALL SYSTEMS GO!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "`n"
Write-Host "Access URLs:"
Write-Host "   - Logistics Dashboard: http://localhost:8501" -ForegroundColor Gray
Write-Host "   - Trino SQL Engine:    http://localhost:8080" -ForegroundColor Gray
Write-Host "   - LocalStack S3:      http://localhost:4566" -ForegroundColor Gray
Write-Host "`n"
Write-Host "Try querying data in DBeaver (Trino) now!" -ForegroundColor Cyan
