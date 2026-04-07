-- ============================================================
-- Trino Init Script (Iceberg Native)
-- Auto-runs at startup via the trino-init container.
-- ============================================================

-- -- Iceberg Schemas ---------------------------------------------
-- These are the only schemas we need. All tables and data 
-- now live in the Iceberg catalog.

CREATE SCHEMA IF NOT EXISTS iceberg.bronze
WITH (location = 's3://data-lakehouse-bronze/iceberg/');

CREATE SCHEMA IF NOT EXISTS iceberg.silver
WITH (location = 's3://data-lakehouse-silver/iceberg/');

CREATE SCHEMA IF NOT EXISTS iceberg.gold
WITH (location = 's3://data-lakehouse-gold/iceberg/');

CREATE SCHEMA IF NOT EXISTS iceberg.elementary
WITH (location = 's3://data-lakehouse-silver/elementary/');

CREATE SCHEMA IF NOT EXISTS iceberg.test_failures
WITH (location = 's3://data-lakehouse-silver/test_failures/');
