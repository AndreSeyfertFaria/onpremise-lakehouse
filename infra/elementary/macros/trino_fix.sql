{% macro trino__create_table_as(temporary, relation, sql) -%}
  {%- set materialized = 'table' -%}
  
  {# GRACEFUL FALLBACK FOR ELEMENTARY: 
     The standard dbt-trino adapter (1.10.1) crashes if 'config' is missing. 
     We provide a resilient version that defaults to Iceberg. #}
  {%- if config is not none and config.get is defined -%}
    {%- set materialized = config.get('materialized', 'table') -%}
  {%- endif -%}

  {%- if temporary -%}
    create table {{ relation }} 
    as (
      {{ sql }}
    );
  {%- else -%}
    {# ICEBERG NATIVE: Use 'format' property instead of the non-existent 'type'. #}
    create table {{ relation }}
    with (
      format = 'PARQUET'
    )
    as (
      {{ sql }}
    );
  {%- endif -%}
{%- endmacro %}
