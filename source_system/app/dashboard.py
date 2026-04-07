import streamlit as st
import pandas as pd
import psycopg2
import pydeck as pdk
import os
import time

# Page Config: Stabilized for a clean professional look
st.set_page_config(page_title="Logistics Command Center", layout="wide")

# Custom CSS for Light Mode consistency
st.markdown("""
    <style>
    .stMetric {
        background-color: #ffffff;
        padding: 15px;
        border-radius: 8px;
        border: 1px solid #e0e0e0;
        box-shadow: 0px 2px 4px rgba(0,0,0,0.05);
    }
    [data-testid="stHeader"] { background-color: rgba(0,0,0,0); }
    </style>
    """, unsafe_allow_html=True)

LOCATIONS = {
    "Central Warehouse (CIC)": [-49.3400, -25.5000],
    "Batel District": [-49.2821, -25.4474],
    "Santa Felicidade": [-49.3224, -25.4024],
    "Botanical Garden": [-49.2398, -25.4431],
    "Portao Area": [-49.2922, -25.4750],
    "Civic Center": [-49.2672, -25.4131]
}

def get_data(query):
    try:
        conn = psycopg2.connect(
            host=os.getenv('DB_HOST', 'localhost'),
            database=os.getenv('DB_NAME', 'logistics_db'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASS')
        )
        df = pd.read_sql(query, conn)
        conn.close()
        return df
    except Exception as e:
        st.error(f"DB Connection Error: {e}")
        return pd.DataFrame()

st.title("Logistics Operations Command")

# --- 1. KPI SECTION ---
df_kpi = get_data("""
    SELECT 
        COUNT(*) FILTER (WHERE status IN ('collecting', 'en_route')) as active_assets,
        AVG(EXTRACT(EPOCH FROM (delivered_at - dispatched_at))/60) as avg_cycle
    FROM orders WHERE delivered_at IS NOT NULL
""")

k1, k2, k3 = st.columns(3)
if not df_kpi.empty:
    k1.metric("Active Assets", int(df_kpi['active_assets'].iloc[0] or 0))
    k2.metric("Avg Delivery Time (Completed)", f"{float(df_kpi['avg_cycle'].iloc[0] or 0.0):.1f} min")
    k3.metric("Fleet Region", "Curitiba, BR")

st.divider()

# --- 2. MAP & OPERATIONS ---
col_map, col_tables = st.columns([2, 1.3])

with col_map:
    # Warehouse Data
    warehouse_df = pd.DataFrame([{"name": k, "lon": v[0], "lat": v[1]} for k, v in LOCATIONS.items()])
    warehouse_df["icon_data"] = [{"url": "https://img.icons8.com/fluency/48/warehouse.png", "width": 128, "height": 128, "anchorY": 128}] * len(warehouse_df)

    # Truck Telemetry
    df_telemetry = get_data("""
        SELECT DISTINCT ON (t.truck_id) t.truck_id, t.latitude, t.longitude, t.speed_kmh
        FROM truck_telemetry t
        JOIN orders o ON t.truck_id = o.truck_id AND o.status IN ('collecting', 'en_route')
        ORDER BY t.truck_id, t.timestamp DESC
    """)
    
    if not df_telemetry.empty:
        df_telemetry["icon_data"] = [{"url": "https://img.icons8.com/color/48/truck.png", "width": 128, "height": 128, "anchorY": 128}] * len(df_telemetry)

    # Layers
    layer_ware = pdk.Layer("IconLayer", warehouse_df, get_icon="icon_data", get_size=25, get_position='[lon, lat]')
    layer_ware_names = pdk.Layer("TextLayer", warehouse_df, get_position='[lon, lat]', get_text="name", get_size=11, get_color=[100, 100, 100], get_pixel_offset=[0, 5], get_alignment_baseline="'top'")
    
    layer_truck = pdk.Layer("IconLayer", df_telemetry, get_icon="icon_data", get_size=30, get_position='[longitude, latitude]')
    layer_truck_plates = pdk.Layer("TextLayer", df_telemetry, get_position='[longitude, latitude]', get_text="truck_id", get_size=13, get_color=[0, 0, 0], get_pixel_offset=[0, -35], get_alignment_baseline="'bottom'")

    st.pydeck_chart(pdk.Deck(
        layers=[layer_ware, layer_ware_names, layer_truck, layer_truck_plates],
        initial_view_state=pdk.ViewState(latitude=-25.44, longitude=-49.27, zoom=11.3),
        map_style="light" 
    ))

with col_tables:
    st.subheader("Active Missions")
    df_active = get_data("""
        SELECT 
            truck_id as "Plate",
            status as "Phase",
            pickup_address as "Pickup",
            delivery_address as "Destination"
        FROM orders 
        WHERE status IN ('collecting', 'en_route')
        ORDER BY dispatched_at DESC
    """)
    st.dataframe(df_active, use_container_width=True, hide_index=True)

    st.divider()
    
    st.subheader("Fleet Status")
    df_fleet = get_data("SELECT id as \"Plate\", model as \"Model\", status as \"Condition\" FROM trucks")
    st.dataframe(df_fleet, use_container_width=True, hide_index=True)

time.sleep(3)
st.rerun()