"""Stand-ins for dbt_utils macros so sqlfluff's jinja templater can render models.

They only need to return SQL that parses; dbt itself uses the real package.
"""


def date_spine(datepart, start_date, end_date):
    return "select cast('2016-01-01' as date) as date_day"


def generate_surrogate_key(field_list):
    return "md5(" + " || ".join(field_list) + ")"
