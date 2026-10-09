-- RFM segments: size and value.
with customers as (
    select * from {{ ref('dim_customers') }}
    where delivered_orders > 0
)

select
    rfm_segment,
    count(*) as customers,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as customers_pct,
    sum(lifetime_revenue) as revenue_brl,
    round(100.0 * sum(lifetime_revenue) / sum(sum(lifetime_revenue)) over (), 1)
        as revenue_share_pct,
    round(avg(lifetime_revenue), 2) as avg_lifetime_revenue_brl,
    round(avg(recency_days)) as avg_recency_days
from customers
group by rfm_segment
order by revenue_brl desc
