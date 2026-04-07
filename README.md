# Logistics Data Platform - Iceberg-Native Lakehouse & Real-time Streaming

A complete, production-grade Data Lakehouse architecture running entirely on your local machine. This project demonstrates high-level data engineering skills including CDC, real-time "Live" streaming, infrastructure-as-code (Terraform), and a distributed SQL engine (Trino).

---

## Architecture (100% Iceberg-Native)

This project uses a modern **Apache Iceberg** stack with a **persistent Raw landing zone** for maximum durability.

### Key Components

1.  **Source System**: PostgreSQL database with a logistics simulation engine.
2.  **Streaming Stack**:
    *   **Debezium**: Captures row-level database changes (CDC).
    *   **Apache Kafka**: Distributed message broker.
    *   **Trino Kafka Connector**: Exposes Kafka topics as virtual tables for dbt to "pull" from.
3.  **Local Data Lakehouse (S3 + Postgres)**:
    *   **PostgreSQL (Iceberg Catalog)**: Serves as the JDBC-backed metastore for ACID transactions.
    *   **LocalStack (S3)**: Stores Iceberg Parquet files and metadata.
4.  **Transformation & Ingestion**:
    *   **dbt (data build tool)**: Handles both **Ingestion** (Kafka $\rightarrow$ Raw Iceberg) and **Transformation** (Raw $\rightarrow$ Silver $\rightarrow$ Gold).
    *   **Airflow Orchestration**: Automates the pipeline via scheduled DAGs (`lakehouse_ingestion_raw` and `lakehouse_transformation_analytics`).

---

## Service Endpoints

| Service | Endpoint | Connection Info |
|---|---|---|
| **Trino (SQL Engine)** | [http://localhost:8080](http://localhost:8080) | `admin` / (none) |
| **Airflow (Orchestrator)**| [http://localhost:8081](http://localhost:8081) | `${AIRFLOW_ADMIN_USER}` / `${AIRFLOW_ADMIN_PASSWORD}` |
| **Iceberg Metadata** | `localhost:5433` | Postgres: `iceberg`/`iceberg` |
| **Logistics Database** | `localhost:5432` | `admin` / `admin` |

---

## How to Query the Data

### 1. The Persistent Raw Layer (Source of Truth)
Query the raw Kafka messages now consolidated into Iceberg:
```sql
SELECT op, ts_ms, json_parse(after) as payload
FROM iceberg.bronze.orders_raw
ORDER BY ts_ms DESC
LIMIT 10;
```

### 2. The Analytical Layers (Silver/Gold)
Query the transactional tables populated by dbt transformations:
```sql
SELECT truck_id, event_ts, speed_kmh, latitude, longitude
FROM iceberg.silver.truck_activity
ORDER BY event_ts DESC
LIMIT 10;
```

---

## Documentation Links

- [Lessons Learned & Architecture Insights](file:///c:/Users/andre/Desktop/Gerenciamento Pessoal/projetos/Data enginner stack/lakehouse-terraform-setup/implementations/Lessons%20Learned.md)
- [CDC & Kafka-to-Iceberg "Pull" Architecture](file:///c:/Users/andre/Desktop/Gerenciamento Pessoal/projetos/Data enginner stack/lakehouse-terraform-setup/implementations/context_streaming.md)
- [dbt Persistent Landing Strategy](file:///c:/Users/andre/Desktop/Gerenciamento Pessoal/projetos/Data enginner stack/lakehouse-terraform-setup/implementations/dbt_implementation.md)
- [Airflow Orchestration Patterns](file:///c:/Users/andre/Desktop/Gerenciamento Pessoal/projetos/Data enginner stack/lakehouse-terraform-setup/implementations/airflow_orchestration.md)
