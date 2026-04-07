# Streaming Stack - CDC & Real-time Telemetry

This stack adds **Change Data Capture (CDC)** and **streaming ingestion** to the logistics lakehouse, using:

- **Apache Kafka** (Bitnami, KRaft - no Zookeeper)
- **Kafka Connect** with Debezium PostgreSQL source + Confluent S3 Sink
- Target: **LocalStack S3** `data-lakehouse-bronze` bucket

---

## Architecture

```
PostgreSQL (wal_level=logical)
      | WAL / pgoutput
      V
  Debezium PostgreSQL Source Connector
  (Kafka Connect)
      |
      V
  Kafka topics:
  |-- cdc.public.trucks           -> s3://data-lakehouse-bronze/cdc/trucks/
  |-- cdc.public.orders           -> s3://data-lakehouse-bronze/cdc/orders/
  \-- cdc.public.truck_telemetry  -> s3://data-lakehouse-bronze/streaming/cdc.public.truck_telemetry/
```

| Pattern | Tables | Flush | Path in Bronze |
|---|---|---|---|
| CDC | `trucks`, `orders` | 100 records / 5 min | `cdc/` |
| Streaming | `truck_telemetry` | 500 records / 1 min | `streaming/` |

---

## Prerequisites

Both other stacks **must be running** before starting this one:

```bash
# 1. Start the source system (PostgreSQL + simulation engine)
cd source_system
docker-compose up -d

# 2. Start the infra stack (LocalStack + Trino + dbt)
cd ../infra
docker-compose up -d
```

> **First-time PostgreSQL setup**: If you already have a `postgres_data` volume from before
> enabling `wal_level=logical`, you must wipe it first:
> ```bash
> cd source_system
> docker-compose down -v
> docker-compose up -d
> ```

---

## Quick Start

```bash
# 1. Copy the env file
cd streaming
cp .env.example .env
# (Edit .env if your Postgres credentials differ)

# 2. Build the custom Kafka Connect image (first time takes ~3 minutes)
docker-compose build kafka-connect

# 3. Start Kafka and Kafka Connect
docker-compose up -d

# 4. Wait ~60 seconds, then register connectors
bash register_connectors.sh        # For Linux/macOS
.\register_connectors.ps1           # For Windows (PowerShell)
```

Expected output:
```
[OK] Kafka Connect is ready!
[REGISTER] logistics-postgres-source  [OK] 200/201
[REGISTER] s3-sink-cdc                [OK] 200/201
[REGISTER] s3-sink-telemetry          [OK] 200/201
[DONE] All connectors registered!
```

---

## Validation

### 1. Check connector status
```bash
curl -s http://localhost:8083/connectors/logistics-postgres-source/status | python -m json.tool
```
All connectors and tasks should show `"state": "RUNNING"`.

### 2. List Kafka topics
```bash
docker exec kafka_broker kafka-topics.sh --bootstrap-server localhost:29092 --list
```

### 3. Peek at messages on a topic
```bash
docker exec kafka_broker kafka-console-consumer.sh \
  --bootstrap-server localhost:29092 \
  --topic cdc.public.orders \
  --from-beginning --max-messages 5
```

### 4. Verify data landed in S3 (bronze layer)
```bash
# CDC tables
aws --endpoint-url=http://localhost:4566 s3 ls s3://data-lakehouse-bronze/cdc/ --recursive

# Streaming telemetry
aws --endpoint-url=http://localhost:4566 s3 ls s3://data-lakehouse-bronze/streaming/ --recursive
```

### 5. Monitor Kafka Connect logs
```bash
docker logs -f kafka_connect
```

---

## Tear Down

```bash
# Stop streaming stack only
cd streaming && docker-compose down

# Full reset (removes Kafka data volume)
docker-compose down -v
```

---

## Connector Files

| File | Purpose |
|---|---|
| `connectors/debezium-postgres-source.json` | Watches all 3 tables via WAL |
| `connectors/s3-sink-cdc.json` | Writes trucks + orders to S3 bronze/cdc/ |
| `connectors/s3-sink-telemetry.json` | Writes telemetry to S3 bronze/streaming/ |
