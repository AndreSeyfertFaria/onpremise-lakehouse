# register_connectors.ps1
# Waits for Kafka Connect to be ready, then registers all three connectors.
# Run this AFTER: docker-compose up -d

$ErrorActionPreference = "Stop"

$CONNECT_URL = "http://localhost:8083"
$CONNECTORS_DIR = Join-Path $PSScriptRoot "connectors"
$MAX_WAIT = 120
$INTERVAL = 5
$STREAMING_ENV = Join-Path $PSScriptRoot ".env"

if (Test-Path $STREAMING_ENV) {
    Get-Content $STREAMING_ENV | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
        $name, $value = $_ -split '=', 2
        [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim())
    }
}

# Wait for Kafka Connect
Write-Host "[WAIT] Waiting for Kafka Connect at $CONNECT_URL ..." -ForegroundColor Cyan
$elapsed = 0
while ($true) {
    try {
        $response = Invoke-WebRequest -Uri "$CONNECT_URL/" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Host "[OK] Kafka Connect is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Continue waiting
    }

    if ($elapsed -ge $MAX_WAIT) {
        Write-Host "[ERROR] Kafka Connect did not become ready within $MAX_WAIT seconds." -ForegroundColor Red
        exit 1
    }

    Write-Host "   ... still waiting ($($elapsed)s elapsed)"
    Start-Sleep -Seconds $INTERVAL
    $elapsed += $INTERVAL
}
Write-Host ""

# Register or update a connector via PUT to /connectors/<name>/config
# The PUT /config endpoint expects ONLY the config object (not the full wrapper with "name")
function Register-Connector {
    param([string]$FilePath)

    $rawJson = Get-Content $FilePath -Raw
    $replacements = @{
        "__POSTGRES_USER__" = $env:POSTGRES_USER
        "__POSTGRES_PASSWORD__" = $env:POSTGRES_PASSWORD
        "__POSTGRES_DB__" = $env:POSTGRES_DB
    }

    foreach ($key in $replacements.Keys) {
        if ($rawJson.Contains($key)) {
            if ([string]::IsNullOrWhiteSpace($replacements[$key])) {
                Write-Host "[ERROR] Missing required environment value for $key" -ForegroundColor Red
                exit 1
            }
            $rawJson = $rawJson.Replace($key, $replacements[$key])
        }
    }

    $fullJson = $rawJson | ConvertFrom-Json
    $name = $fullJson.name
    $configBody = $fullJson.config | ConvertTo-Json -Depth 10

    Write-Host "[REGISTER] $name" -ForegroundColor Cyan

    $uri = "$CONNECT_URL/connectors/$name/config"

    $result = Invoke-WebRequest -Uri $uri -Method Put -ContentType "application/json" -Body $configBody -UseBasicParsing -ErrorAction SilentlyContinue
    if ($result.StatusCode -ge 200 -and $result.StatusCode -lt 300) {
        Write-Host "   [OK] $name registered (HTTP $($result.StatusCode))" -ForegroundColor Green
    } else {
        Write-Host "   [ERROR] Failed to register $name (HTTP $($result.StatusCode))" -ForegroundColor Red
        Write-Host "   Response: $($result.Content)"
        exit 1
    }
}

# Register all connectors (source must be first)
Register-Connector (Join-Path $CONNECTORS_DIR "debezium-postgres-source.json")
Start-Sleep -Seconds 3
Register-Connector (Join-Path $CONNECTORS_DIR "s3-sink-cdc.json")
Register-Connector (Join-Path $CONNECTORS_DIR "s3-sink-telemetry.json")

Write-Host ""
Write-Host "[DONE] All connectors registered! Checking status..." -ForegroundColor Magenta
Write-Host ""

# Status check
$connectors = @("logistics-postgres-source", "s3-sink-cdc", "s3-sink-telemetry")
foreach ($connector in $connectors) {
    Write-Host "--- $connector ---" -ForegroundColor Yellow
    $statusResult = Invoke-WebRequest -Uri "$CONNECT_URL/connectors/$connector/status" -Method Get -UseBasicParsing -ErrorAction SilentlyContinue
    if ($statusResult.StatusCode -eq 200) {
        $status = $statusResult.Content | ConvertFrom-Json

        $cState = $status.connector.state
        $cMark = if ($cState -eq "RUNNING") { "[OK]" } else { "[WARN]" }
        Write-Host "  Connector: $cMark $cState"

        foreach ($task in $status.tasks) {
            $tState = $task.state
            $tMark = if ($tState -eq "RUNNING") { "[OK]" } else { "[WARN]" }
            Write-Host "  Task $($task.id): $tMark $tState"
        }
    } else {
        Write-Host "  [ERROR] Failed to fetch status (HTTP $($statusResult.StatusCode))" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "Done. Monitor logs with:"
Write-Host "  docker logs -f kafka_connect"
