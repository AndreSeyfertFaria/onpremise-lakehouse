import os
import psycopg2
from datetime import timedelta, date

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'logistics_db')
DB_USER = os.getenv('DB_USER', 'admin')
DB_PASS = os.getenv('DB_PASS', 'admin')

def get_connection():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)

def main():
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor()

    print("Starting data migration and partition bootstrapping...")

    # 1. Identify date ranges from the old table
    cur.execute("SELECT MIN(timestamp), MAX(timestamp) FROM truck_telemetry_old")
    min_ts, max_ts = cur.fetchone()

    # Also check if there's data in the default partition that needs a specific partition
    cur.execute("SELECT MIN(timestamp), MAX(timestamp) FROM truck_telemetry_default")
    def_min, def_max = cur.fetchone()

    if min_ts is None: min_ts = def_min
    elif def_min is not None: min_ts = min(min_ts, def_min)

    if max_ts is None: max_ts = def_max
    elif def_max is not None: max_ts = max(max_ts, def_max)

    if min_ts is None or max_ts is None:
        print("No data found. Creating a default partition for today and exiting.")
        today = date.today()
        min_ts = today
        max_ts = today
    else:
        # Convert datetime to date
        min_ts = min_ts.date()
        max_ts = max_ts.date()

    print(f"Data range found: from {min_ts} to {max_ts}")

    # Temporary table to hold data from default partition if it exists
    cur.execute("CREATE TEMP TABLE telemetry_temp (LIKE truck_telemetry INCLUDING ALL) ON COMMIT PRESERVE ROWS")
    cur.execute("ALTER TABLE telemetry_temp DROP COLUMN timestamp") # Partition key must be handled carefully
    cur.execute("ALTER TABLE telemetry_temp ADD COLUMN timestamp TIMESTAMP")

    print("Checking for data in default partition...")
    cur.execute("INSERT INTO telemetry_temp SELECT * FROM truck_telemetry_default")
    cur.execute("TRUNCATE truck_telemetry_default")

    # Calculate end date (max_ts + 7 days)
    end_date = max_ts + timedelta(days=7)

    # 3. Loop through dates and create partitions
    current_date = min_ts
    while current_date <= end_date:
        next_date = current_date + timedelta(days=1)
        partition_name = f"truck_telemetry_y{current_date.year}_m{current_date.month:02d}_d{current_date.day:02d}"
        
        # Partition bounds are [current_date, next_date)
        start_bound = current_date.strftime('%Y-%m-%d')
        end_bound = next_date.strftime('%Y-%m-%d')
        
        print(f"Creating partition {partition_name} for range [{start_bound}, {end_bound})...")
        
        create_partition_query = f"""
            CREATE TABLE IF NOT EXISTS {partition_name} 
            PARTITION OF truck_telemetry 
            FOR VALUES FROM ('{start_bound}') TO ('{end_bound}');
        """
        cur.execute(create_partition_query)
        
        current_date = next_date

    # 4. Insert data from old table AND temp table back to new partitioned table
    print("Moving data from truck_telemetry_old to truck_telemetry...")
    
    insert_old_query = """
        INSERT INTO truck_telemetry (id, truck_id, latitude, longitude, speed_kmh, timestamp)
        SELECT id, truck_id, latitude, longitude, speed_kmh, timestamp 
        FROM truck_telemetry_old
        ON CONFLICT (id, timestamp) DO NOTHING;
    """
    cur.execute(insert_old_query)

    print("Moving data from temp table (original default partition) to truck_telemetry...")
    insert_temp_query = """
        INSERT INTO truck_telemetry (id, truck_id, latitude, longitude, speed_kmh, timestamp)
        SELECT id, truck_id, latitude, longitude, speed_kmh, timestamp 
        FROM telemetry_temp
        ON CONFLICT (id, timestamp) DO NOTHING;
    """
    cur.execute(insert_temp_query)
    
    print("Data migration completed successfully.")
    
    cur.close()
    conn.close()

if __name__ == '__main__':
    main()
