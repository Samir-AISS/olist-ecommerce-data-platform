-- One row per real customer (customer_unique_id): order history used for RFM.
with orders as (
    select * from {{ ref('int_orders_enriched') }}
),

customers as (
    select * from {{ ref('stg_olist__customers') }}
),

latest_address as (
    -- a customer can move: keep the address of the most recent order
    select distinct on (orders.customer_unique_id)
        orders.customer_unique_id,
        customers.zip_code_prefix,
        customers.city,
        customers.state
    from orders
    inner join customers on orders.customer_id = customers.customer_id
    order by orders.customer_unique_id asc, orders.purchased_at desc
),

history as (
    select
        customer_unique_id,
        min(purchased_at) as first_order_at,
        max(purchased_at) as last_order_at,
        count(*) as orders_count,
        count(*) filter (where is_delivered) as delivered_orders,
        max(purchased_at) filter (where is_delivered) as last_delivered_order_at,
        coalesce(sum(items_amount) filter (where is_delivered), 0) as lifetime_revenue
    from orders
    group by customer_unique_id
)

select
    history.*,
    latest_address.zip_code_prefix,
    latest_address.city,
    latest_address.state
from history
inner join latest_address on history.customer_unique_id = latest_address.customer_unique_id
