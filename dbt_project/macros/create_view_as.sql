{% macro trino__create_view_as(relation, sql) -%}
  {# 
     Iceberg JDBC catalogs do not support VIEWS by default (unless V1 schema is enabled). 
     Many dbt packages (like Elementary) use temporary views during incremental builds. 
     This professional shadow macro replaces view creation with table creation to ensure compatibility.
  #}
  create table {{ relation }}
  with (
    format = 'PARQUET'
  )
  as (
    {{ sql }}
  )
{%- endmacro %}
