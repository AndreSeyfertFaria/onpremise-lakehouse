{{
  config(
    materialized='incremental',
    unique_key=['metric_date', 'truck_id'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

/*
  fleet_utilization.sql  (gold)
  ------------------------------
  Daily fleet utilization summary.

  Utilization = time a truck spends actively moving (in_transit)
  as a fraction of the total observed window (active hours from telemetry).

  Two complementary views are produced in one model via UNION:
    1. Fleet-level daily summary (district = '__fleet__')
    2. Per-truck daily summary (for individual drill-down)

  This keeps the dashboard query simple — filter district = '__fleet__'
  for the headline number, or filter by truck_id for individual analysis.

  Recomputes last N days on each incremental run (lookback_days var).
*/


with activity as (

    select * from {{ ref('truck_activity') }}
    {% if is_incremental() %}
    where activity_date >= current_date - interval '{{ var("lookback_days", 1) + 6}}' day
    {% endif %}

),

final as (

    select
        activity_date                               as metric_date,
        truck_id,
        model,
        capacity_kg,
        primary_district                            as district,
        
        trips_completed,
        total_distance_km,
        total_duration_min,
        avg_deadhead_ratio,
        
        -- Utilization = (trip hours / observed active hours)
        round(
            (total_duration_min / 60.0) / nullif(active_hours, 0),
            4
        )                                           as utilization_index

    from activity

)

select
    metric_date,
    truck_id,
    model,
    capacity_kg,
    district,
    trips_completed,
    total_distance_km,
    total_duration_min,
    avg_deadhead_ratio,
    utilization_index,

    -- 7-day rolling utilization index per truck
    round(
        avg(utilization_index) over (
            partition by truck_id
            order by metric_date
            rows between 6 preceding and current row
        ),
        2
    )                                               as utilization_index_7d

from final
order by metric_date desc, utilization_index desc
