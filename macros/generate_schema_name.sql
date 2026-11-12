{#- Schema = nome da camada (staging, intermediate, marts), sem o prefixo do target. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
