-- Black Friday 2017 vs the other days of November 2017.
with daily as (
    select
        items.purchase_date,
        dates.is_black_friday,
        sum(items.revenue) as revenue_brl,
        count(distinct items.order_id) as orders
    from {{ ref('fct_order_items') }} as items
    inner join {{ ref('dim_date') }} as dates on items.purchase_date = dates.date_day
    where items.purchase_date between '2017-11-01' and '2017-11-30'
    group by items.purchase_date, dates.is_black_friday
)

select
    case when is_black_friday then 'Black Friday (2017-11-24)' else 'Other November days' end
        as day_type,
    count(*) as day_count,
    round(avg(orders)) as avg_orders_per_day,
    round(avg(revenue_brl), 2) as avg_revenue_per_day_brl
from daily
group by is_black_friday
order by is_black_friday desc
