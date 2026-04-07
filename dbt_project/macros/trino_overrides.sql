{% macro trino__create_table_as(temporary, relation, sql) -%}
  {%- set materialized = 'table' -%}
  
  {# GRACEFUL FALLBACK FOR ELEMENTARY/OBSERVABILITY 
     The standard dbt-trino adapter (1.10.1) crashes if 'config' is missing during temp table queries. 
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
    {# ICEBERG NATIVE: Use 'format' property instead of the deprecated 'type' property. #}
    create table {{ relation }}
    with (
      format = 'PARQUET'
    )
    as (
      {{ sql }}
    );
  {%- endif -%}
{%- endmacro %}
