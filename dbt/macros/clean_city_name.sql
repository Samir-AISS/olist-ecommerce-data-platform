{#- Normalize a Brazilian city name: lowercase, no accents, and drop suffixes
    such as "lages - sc", "auriflama/sp" or "rio de janeiro, brasil". -#}
{% macro clean_city_name(column) -%}
    nullif(
        trim(
            split_part(
                split_part(
                    split_part(
                        translate(
                            lower({{ column }}),
                            'áàâãäéèêëíìîïóòôõöúùûüç',
                            'aaaaaeeeeiiiiooooouuuuc'
                        ),
                        ' - ', 1
                    ),
                    '/', 1
                ),
                ',', 1
            )
        ),
        ''
    )
{%- endmacro %}
