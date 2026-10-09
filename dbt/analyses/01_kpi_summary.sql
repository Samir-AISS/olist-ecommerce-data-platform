-- Headline KPIs, as defined in docs/kpi_dictionary.md.
with orders as (
    select
        sum(revenue) as revenue_brl,
        count(*) filter (where is_delivered) as delivered_orders,
        count(*) filter (where is_late) as late_orders,
        count(*) filter (where is_late is not null) as orders_with_delivery_date,
        avg(review_score) as average_review_score
    from {{ ref('fct_orders') }}
),

customers as (
    select
        count(*) filter (where is_repeat_customer) as repeat_customers,
        count(*) filter (where delivered_orders > 0) as buying_customers
    from {{ ref('dim_customers') }}
)

select
    orders.revenue_brl,
    orders.delivered_orders,
    round(orders.revenue_brl / orders.delivered_orders, 2) as average_order_value_brl,
    round(100.0 * orders.late_orders / orders.orders_with_delivery_date, 2)
        as late_delivery_rate_pct,
    round(orders.average_review_score, 2) as average_review_score,
    round(100.0 * customers.repeat_customers / customers.buying_customers, 2)
        as repeat_purchase_rate_pct
from orders
cross join customers
