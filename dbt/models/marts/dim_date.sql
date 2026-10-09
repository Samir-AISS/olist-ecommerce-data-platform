-- One row per calendar day covering every purchase and promised delivery date.
with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}
),

holidays as (
    select * from {{ ref('br_national_holidays') }}
),

final as (
    select
        spine.date_day::date as date_day,
        extract(year from spine.date_day)::int as year,
        extract(quarter from spine.date_day)::int as quarter,
        extract(month from spine.date_day)::int as month,
        to_char(spine.date_day, 'YYYY-MM') as year_month,
        date_trunc('month', spine.date_day)::date as month_start_date,
        extract(isodow from spine.date_day)::int as day_of_week,
        trim(to_char(spine.date_day, 'Day')) as day_name,
        extract(isodow from spine.date_day) in (6, 7) as is_weekend,
        holidays.holiday_date is not null as is_br_holiday,
        holidays.holiday_name,
        -- Black Friday is the fourth Friday of November
        coalesce(
            extract(month from spine.date_day) = 11
            and extract(isodow from spine.date_day) = 5
            and extract(day from spine.date_day) between 22 and 28,
            false
        ) as is_black_friday
    from spine
    left join holidays on spine.date_day::date = holidays.holiday_date
)

select * from final
