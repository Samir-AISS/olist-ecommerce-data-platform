-- One row per order.
with orders as (
    select * from {{ ref('int_orders_enriched') }}
)

select
    order_id,
    customer_unique_id,
    customer_state,
    purchase_date,
    purchased_at,
    order_status,
    is_delivered,
    items_count,
    sellers_count,
    items_amount,
    freight_amount,
    payment_amount,
    payments_count,
    case when is_delivered then items_amount else 0 end as revenue,
    main_payment_type,
    max_installments,
    used_voucher,
    review_score,
    has_comment,
    delivered_to_customer_at,
    estimated_delivery_date,
    delivery_days,
    delivery_delay_days,
    is_late
from orders
