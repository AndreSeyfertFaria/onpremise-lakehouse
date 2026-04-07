-- infra/postgres_init/init.sql

-- Trucks Table (Company Assets)
CREATE TABLE IF NOT EXISTS trucks (
    id VARCHAR(10) PRIMARY KEY, -- License Plate
    model VARCHAR(50),
    capacity_kg INT,
    status VARCHAR(20) DEFAULT 'available' -- 'in_transit', 'available', 'maintenance'
);

-- Orders Table (Sales/Deliveries)
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    customer_name VARCHAR(100),
    pickup_address VARCHAR(255),
    pickup_latitude DOUBLE PRECISION,
    pickup_longitude DOUBLE PRECISION,
    collected_at TIMESTAMP,
    delivery_address VARCHAR(255),
    dest_latitude DOUBLE PRECISION,
    dest_longitude DOUBLE PRECISION,
    weight_kg INT,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'loading', 'en_route', 'delivered'
    truck_id VARCHAR(10) REFERENCES trucks(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    dispatched_at TIMESTAMP,
    delivered_at TIMESTAMP
);

-- Telemetry Table (Real-time Streaming Pulse)
CREATE TABLE IF NOT EXISTS truck_telemetry (
    id SERIAL PRIMARY KEY,
    truck_id VARCHAR(10) REFERENCES trucks(id),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    speed_kmh INT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- CDC / Debezium Setup
-- ============================================================

-- Grant REPLICATION privilege so Debezium can open a replication slot
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolreplication
  ) THEN
    -- Only runs if the user doesn't already have replication
    EXECUTE format('ALTER USER %I REPLICATION', current_user);
  END IF;
END
$$;

-- Create a publication for the three CDC/streaming tables.
-- Debezium will subscribe to this publication via the pgoutput plugin.
CREATE PUBLICATION debezium_publication
  FOR TABLE trucks, orders, truck_telemetry;