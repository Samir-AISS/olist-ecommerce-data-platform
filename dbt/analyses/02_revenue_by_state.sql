-- Why does revenue vary by region? Volume, basket, freight and delivery by customer state.
with orders as (
    select * from {{ ref('fct_orders') }}
    where is_delivered
),

by_state as (
    select
        customer_state as state,
        sum(revenue) as revenue_brl,
        count(*) as delivered_orders,
        round(avg(revenue), 2) as average_order_value_brl,
        round(100.0 * sum(freight_amount) / sum(items_amount), 1) as freight_pct_of_items,
        round(avg(delivery_days), 1) as avg_delivery_days,
        round(100.0 * avg(is_late::int), 1) as late_rate_pct,
        round(avg(review_score), 2) as avg_review_score
    from orders
    group by customer_state
)

select
    rank() over (order by revenue_brl desc) as revenue_rank,
    state,
    revenue_brl,
    round(100.0 * revenue_brl / sum(revenue_brl) over (), 1) as revenue_share_pct,
    delivered_orders,
    average_order_value_brl,
    freight_pct_of_items,
    avg_delivery_days,
    late_rate_pct,
    avg_review_score
from by_state
order by revenue_rank
