# Design Spec: Telemetry Optimization (Postgres Partitioning)

**Date:** 2026-04-07
**Status:** Approved

## Problem Statement
The `truck_telemetry` table in the source Postgres grows indefinitely without indexing or partitioning. This results in slow performance for:
1.  **Logistics Engine:** Scanning millions of records to find the "latest position" of a truck.
2.  **Operations Dashboard (Streamlit):** Querying `DISTINCT ON (truck_id)` with `ORDER BY timestamp DESC` becomes extremely expensive over time.
3.  **Database Maintenance:** Indexing and cleaning up a monolithic table is resource-intensive.

## Proposed Architecture

### 1. Declarative Partitioning
Reconstruct the `truck_telemetry` table using Postgres Declarative Partitioning by **Daily Range**.

-   **Partition Key:** `timestamp` (TIMESTAMP).
-   **Partition Interval:** Daily (e.g., `telemetry_y2026_m04_d07`).
-   **Retention:** Keep forever (demo context), but the structure allows easy drops if needed later.

### 2. Optimized Indexing
Apply a composite B-Tree index to every partition:
-   **Index Columns:** `(truck_id, timestamp DESC)`
-   **Purpose:** Enables O(log N) lookups for "get latest position for truck X" and efficient `DISTINCT ON` queries.

### 3. Migration Strategy (Zero Data Loss)
The migration will follow these steps:
1.  **Lock & Rename:** `ALTER TABLE truck_telemetry RENAME TO truck_telemetry_old;`
2.  **Create Parent:** Create the new partitioned `truck_telemetry` table.
3.  **Bootstrap Partitions:** Create partitions for all unique dates found in `truck_telemetry_old` plus current/future days.
4.  **Data Transfer:** `INSERT INTO truck_telemetry SELECT * FROM truck_telemetry_old;`
5.  **Verify & Index:** Once data is transferred, apply the composite indexes and verify record counts.
6.  **Debezium Update:** Re-add the new table to the publication if necessary (Debezium handles partitioned tables as a single stream in newer versions).

## Success Criteria
-   The Logistics Dashboard map updates in < 1 second.
-   `simulate_movement` queries in `engine.py` use index scans.
-   No telemetry data is lost during the migration.
