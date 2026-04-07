{%- macro trino__get_drop_sql(relation) -%}
  {% set relation_type = relation.type|replace("_", " ") %}
  {#
     Because we override create_view_as to create tables in Iceberg,
     when dbt attempts to drop what it thinks is a view, we must instruct Trino to drop a table instead.
  #}
  {% if relation_type == 'view' %}
    drop table if exists {{ relation }}
  {% else %}
    drop {{ relation_type }} if exists {{ relation }}
  {% endif %}
{% endmacro %}
