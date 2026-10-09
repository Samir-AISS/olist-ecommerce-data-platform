-- Total revenue must be identical whether computed from items or from orders.
with items as (
    select sum(revenue) as revenue from {{ ref('fct_order_items') }}
),

orders as (
    select sum(revenue) as revenue from {{ ref('fct_orders') }}
)

select
    items.revenue as items_revenue,
    orders.revenue as orders_revenue
from items
cross join orders
where items.revenue <> orders.revenue
