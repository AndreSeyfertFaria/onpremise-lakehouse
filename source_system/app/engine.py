import os, time, random, psycopg2
from psycopg2.extras import execute_values
from faker import Faker

DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_NAME = os.getenv('DB_NAME', 'logistics_db')
DB_USER = os.getenv('DB_USER')
DB_PASS = os.getenv('DB_PASS')

fake = Faker()

LOCATIONS = {
    "Central Warehouse (CIC)": (-25.5000, -49.3400),
    "Batel District": (-25.4474, -49.2821),
    "Santa Felicidade": (-25.4024, -49.3224),
    "Botanical Garden": (-25.4431, -49.2398),
    "Portao Area": (-25.4750, -49.2922),
    "Civic Center": (-25.4131, -49.2672)
}

def get_connection():
    return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)

def generate_order(conn):
    cur = conn.cursor()
    cur.execute("SELECT id FROM trucks WHERE status = 'available' LIMIT 1")
    truck = cur.fetchone()

    if truck:
        truck_id = truck[0]
        # Logic: Pickup and Destination must be different
        loc_names = list(LOCATIONS.keys())
        pickup_name = random.choice(loc_names)
        delivery_name = random.choice([l for l in loc_names if l != pickup_name])
        
        pickup_coords = LOCATIONS[pickup_name]
        delivery_coords = LOCATIONS[delivery_name]
        
        print(f"New Order! {pickup_name} -> {delivery_name}. Assigned to {truck_id}")
        
        cur.execute("""
            INSERT INTO orders (
                customer_name, pickup_address, pickup_latitude, pickup_longitude,
                delivery_address, dest_latitude, dest_longitude, 
                weight_kg, truck_id, status, dispatched_at
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'collecting', CURRENT_TIMESTAMP)
        """, (fake.name(), pickup_name, pickup_coords[0], pickup_coords[1], 
              delivery_name, delivery_coords[0], delivery_coords[1], 
              random.randint(100, 5000), truck_id))
        
        cur.execute("UPDATE trucks SET status = 'in_transit' WHERE id = %s", (truck_id,))
        conn.commit()

def simulate_movement(conn):
    cur = conn.cursor()
    # Fetch orders that are either moving to pickup or moving to destination
    cur.execute("""
        SELECT id, truck_id, status, 
               pickup_latitude, pickup_longitude, 
               dest_latitude, dest_longitude 
        FROM orders WHERE status IN ('collecting', 'en_route')
    """)
    active_orders = cur.fetchall()
    
    delta_t_hours = 5 / 3600 

    for ord_id, truck_id, status, p_lat, p_lon, d_lat, d_lon in active_orders:
        # Get current position from telemetry
        cur.execute("SELECT latitude, longitude FROM truck_telemetry WHERE truck_id = %s ORDER BY timestamp DESC LIMIT 1", (truck_id,))
        last_pos = cur.fetchone()
        # Default start point is CIC if no telemetry exists yet
        lat_now, lon_now = last_pos if last_pos else LOCATIONS["Central Warehouse (CIC)"]

        # Determine target based on status
        target_lat, target_lon = (p_lat, p_lon) if status == 'collecting' else (d_lat, d_lon)

        speed = random.randint(40, 80)
        # Physics: Degrees moved = (speed * time) / constant
        lat_step = (speed * delta_t_hours) / 111
        lon_step = (speed * delta_t_hours) / 100

        new_lat = lat_now + (lat_step if target_lat > lat_now else -lat_step)
        new_lon = lon_now + (lon_step if target_lon > lon_now else -lon_step)

        # Check for arrival (threshold of approx 200 meters)
        if abs(new_lat - target_lat) < 0.002 and abs(new_lon - target_lon) < 0.002:
            if status == 'collecting':
                print(f"Truck {truck_id} picked up order {ord_id} at destination. Now en route.")
                cur.execute("UPDATE orders SET status = 'en_route', collected_at = CURRENT_TIMESTAMP WHERE id = %s", (ord_id,))
            else:
                print(f"Truck {truck_id} delivered order {ord_id}!")
                cur.execute("UPDATE orders SET status = 'delivered', delivered_at = CURRENT_TIMESTAMP WHERE id = %s", (ord_id,))
                cur.execute("UPDATE trucks SET status = 'available' WHERE id = %s", (truck_id,))
        else:
            # Continue moving
            cur.execute("INSERT INTO truck_telemetry (truck_id, latitude, longitude, speed_kmh) VALUES (%s, %s, %s, %s)", 
                        (truck_id, new_lat, new_lon, speed))
        conn.commit()

def run():
    print("Advanced Logistics Engine Started!")
    while True:
        try:
            conn = get_connection()
            # 1. Initialize fleet if empty
            cur = conn.cursor()
            cur.execute("SELECT COUNT(*) FROM trucks")
            if cur.fetchone()[0] == 0:
                fleet = [('TRK-001', 'Volvo FH', 25000), ('TRK-002', 'Scania R', 20000), 
                         ('TRK-003', 'Mercedes', 22000), ('TRK-004', 'VW Const', 15000), 
                         ('TRK-005', 'Iveco Hi', 24000)]
                execute_values(cur, "INSERT INTO trucks (id, model, capacity_kg) VALUES %s", fleet)
                conn.commit()

            # 2. Generate new orders (20% chance)
            if random.random() < 0.2: generate_order(conn)
            
            # 3. Simulate movement for all active assets
            simulate_movement(conn)
            conn.close()
        except Exception as e: print(f"Simulation Error: {e}")
        time.sleep(5)

if __name__ == "__main__":
    run()