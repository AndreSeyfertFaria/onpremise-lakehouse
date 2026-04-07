# Logistics Data Platform

![Tech Stack Badges](https://img.shields.io/badge/Kafka-231F20?style=for-the-badge&logo=apachekafka&logoColor=white) ![Trino](https://img.shields.io/badge/Trino-DD00A1?style=for-the-badge&logo=trino&logoColor=white) ![Apache Iceberg](https://img.shields.io/badge/Apache%20Iceberg-00B4EB?style=for-the-badge&logo=apache&logoColor=white) ![dbt](https://img.shields.io/badge/dbt-FF694B?style=for-the-badge&logo=dbt&logoColor=white) ![Airflow](https://img.shields.io/badge/Airflow-017CEE?style=for-the-badge&logo=apacheairflow&logoColor=white) ![Superset](https://img.shields.io/badge/Superset-00A699?style=for-the-badge&logo=apachesuperset&logoColor=white) ![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)

*[PLACEHOLDER: High-quality GIF/Image of the final Superset Dashboard or Streamlit UI]*

## Overview & Business Value

This project implements a production-grade, local **Data Lakehouse** built on an Iceberg-native architecture. 

Its primary purpose is to simulate, capture, and analyze real-time logistics operations and fleet telemetry. The core of this data generation is the **Logistics Operations Command**, a custom simulation engine that generates realistic logistics events, including order dispatching and high-frequency fleet movement.

## Architecture & Data Flow

*[PLACEHOLDER: Architecture Diagram (Mermaid or Image)]*

The platform is divided into distinct operational and analytical layers:

1. **Source System (Operational):** PostgreSQL acts as the primary database for the Logistics Operations Command.
2. **Streaming Stack:** Debezium Change Data Capture (CDC) captures row-level changes and pushes them to **Apache Kafka**, which acts as the high-speed message buffer.
3. **Lakehouse (Iceberg-Native):** 
   - **Trino:** Distributed SQL query engine.
   - **MinIO/LocalStack (S3):** Object storage for Iceberg Parquet files and metadata.
   - **PostgreSQL:** Serves as the Iceberg JDBC Catalog for ACID transactions.
4. **Transformation:** **dbt** (data build tool) handles Pull-based ingestion from Kafka into the Raw layer, and subsequent transformations into Staging, Silver, and Gold layers.
5. **Orchestration & Observability:** **Apache Airflow** (via Astronomer Cosmos) orchestrates the dbt models, while **Elementary Data** monitors data quality and lineage.
6. **Analytics & Visualization:** **Apache Superset** serves the analytical Gold layer, while **Streamlit** provides a real-time operational view.

## Data Engineering Highlights

This project addresses several advanced data engineering challenges:

### 1. Pull-Based CDC Ingestion
Instead of using a Kafka Sink connector to push data directly into the data lake, this architecture uses a **Pull-based pattern**. The Trino Kafka Connector exposes live topics, and dbt pulls this data into a persistent Iceberg Raw layer. This bypasses transient Kafka topic retention limits and creates a permanent, auditable "Source of Truth."

### 2. Exactly-Once Processing
Relying solely on timestamps for incremental ingestion can lead to data loss during high-frequency events. The Raw ingestion models track Kafka partition offsets (`_partition_id`, `_partition_offset`) to guarantee exactly-once, idempotent ingestion, even if timestamp collisions occur.

### 3. 100% Self-Healing Infrastructure
Managing ephemeral local infrastructure (like LocalStack) alongside persistent database catalogs often leads to "Zombie" metadata (`ICEBERG_MISSING_METADATA` errors) when the S3 state is lost but the catalog remains. This project features a custom meta-controller (`lakehouse-setup`) that:
- Detects local environment resets.
- Automatically purges orphaned metadata from the Postgres catalog.
- Re-runs Terraform to recreate S3 buckets.
- Uses Docker-in-Docker signaling to trigger dbt logical repairs and Elementary manifest syncs without manual intervention.

### 4. Trino & Iceberg Adaptations
The Trino Iceberg JDBC catalog does not natively support SQL Views. To integrate seamlessly with dbt and Elementary Data (which rely heavily on temporary views and tables), the project implements **Macro Shadowing**. Custom local overrides (`trino__create_table_as`, `trino__create_view_as`) force dbt to use persistent Iceberg tables for temporary artifacts, ensuring full compatibility without hacking package source code.

## The Logistics Operations Command (Simulation Engine)

To provide a realistic data source, the project includes a Python-based Finite State Machine (FSM). This engine simulates a high-fidelity delivery operation featuring:
- **State Transitions:** Assets move through defined operational states (Idle, Collecting, En Route, Completed).
- **Movement Physics:** Realistic GPS updates calculated using Haversine formulas and velocity-based displacements.

*[PLACEHOLDER: Streamlit "Control Room" Dashboard Print]*

## Analytics & Dashboards

The Gold analytical layer powers zero-touch automated dashboards in Apache Superset, analyzing key metrics:
- **On-Time Delivery (OTD):** Analyzing delivery performance tiers and district-level success rates.
- **Fleet Utilization:** Tracking the ratio of "Deadhead" (empty) to "Loaded" kilometers.
- **District Heatmap:** Visualizing corridor volume and average trip durations.

*[PLACEHOLDER: Prints/GIFs of the two Superset Dashboards]*

## Execution Guide

### 1. Environment Variables
Before running any services, you must create a `.env` file in each of the main component directories. Example files (`.env.example`) have been provided for you. 

Run the following commands to copy the examples into active `.env` files:

**Linux/macOS:**
```bash
cp source_system/.env.example source_system/.env
cp streaming/.env.example streaming/.env
cp infra/.env.example infra/.env
cp superset/.env.example superset/.env
```

**Windows (PowerShell):**
```powershell
Copy-Item source_system\.env.example source_system\.env
Copy-Item streaming\.env.example streaming\.env
Copy-Item infra\.env.example infra\.env
Copy-Item superset\.env.example superset\.env
```
*(Note: You can open these `.env` files and modify the default passwords and keys if desired.)*

### 2. Start the Logistics Operations Command (Source System)
Start the PostgreSQL database and the Python simulation engine that generates logistics data.
```bash
docker-compose -f source_system/docker-compose.yaml up -d --build
```
*(The Streamlit operational dashboard will be available at `http://localhost:8501`)*

### 3. Start the Streaming Stack
Start the Kafka broker, Kafka Connect, and Debezium.
```bash
docker-compose -f streaming/docker-compose.yaml up -d
```
Wait a few seconds for Kafka Connect to be ready, then register the CDC and Sink connectors:
- **Linux/macOS:** `./streaming/register_connectors.sh`
- **Windows:** `.\streaming\register_connectors.ps1`

### 4. Start the Lakehouse Infrastructure
Start the data lakehouse components (MinIO/LocalStack, Trino, Postgres Catalog, Airflow, and Elementary). The `lakehouse-setup` meta-controller will automatically initialize the S3 buckets and Trino schemas.
```bash
docker-compose -f infra/docker-compose.yaml up -d --build
```
*(The Trino UI will be available at `http://localhost:8080`)*

### 5. Trigger the dbt Pipelines
Once Airflow is healthy, access the Airflow UI at `http://localhost:8081` (default login: `admin`/`admin` from `infra/.env`).
1. Trigger the `lakehouse_ingestion_raw` DAG to pull CDC data from Kafka into the Iceberg Raw layer.
2. Trigger the `lakehouse_transformation_analytics` DAG to transform the Raw data into Silver and Gold layers.
*(The Elementary UI for data quality will be available at `http://localhost:8082`)*

### 6. Start the Analytics Layer (Superset)
Start Apache Superset to visualize the Gold layer metrics. The container will automatically install the Trino driver, initialize the database, and import the zero-touch dashboards.
```bash
docker-compose -f superset/docker-compose.yml up -d --build
```
Access the Superset UI at `http://localhost:8088` (default login: `admin`/`admin_change_me` from `superset/.env`). Navigate to **Dashboards** to view the final analytics.
