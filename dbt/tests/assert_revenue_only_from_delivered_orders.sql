-- Revenue must never include cancelled, unavailable or in-progress orders.
select
    order_id,
    order_item_id,
    order_status,
    revenue
from {{ ref('fct_order_items') }}
where revenue <> 0 and order_status <> 'delivered'
