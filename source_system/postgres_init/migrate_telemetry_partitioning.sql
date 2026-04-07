-- Rename existing table to preserve data
ALTER TABLE truck_telemetry RENAME TO truck_telemetry_old;

-- Remove the old table from the Debezium publication
-- Note: When a table is renamed, the publication still tracks it by OID under the new name.
ALTER PUBLICATION debezium_publication DROP TABLE truck_telemetry_old;

-- Create new partitioned parent table
CREATE TABLE truck_telemetry (
    id SERIAL,
    truck_id VARCHAR(10) REFERENCES trucks(id),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    speed_kmh INT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id, timestamp)
) PARTITION BY RANGE (timestamp);

-- Create a default partition to handle data outside specific ranges
CREATE TABLE truck_telemetry_default PARTITION OF truck_telemetry DEFAULT;

-- Add the new partitioned table to the Debezium publication
ALTER PUBLICATION debezium_publication ADD TABLE truck_telemetry;

-- Add optimized index to the parent table (propagates to partitions)
CREATE INDEX idx_telemetry_truck_time ON truck_telemetry (truck_id, timestamp DESC);
