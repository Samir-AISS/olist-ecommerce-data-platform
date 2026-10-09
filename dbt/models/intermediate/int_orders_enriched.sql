-- One row per order, with the real customer key, amounts, review and delivery metrics.
-- The two business rules reused by every mart are defined here:
--   is_delivered : order_status = 'delivered' (only these orders count as revenue)
--   is_late      : delivered after the date promised at purchase
with orders as (
    select * from {{ ref('stg_olist__orders') }}
),

customers as (
    select * from {{ ref('stg_olist__customers') }}
),

items as (
    select * from {{ ref('int_items_per_order') }}
),

payments as (
    select * from {{ ref('int_payments_per_order') }}
),

reviews as (
    select * from {{ ref('int_reviews_per_order') }}
),

joined as (
    select
        orders.order_id,
        orders.customer_id,
        customers.customer_unique_id,
        customers.state as customer_state,
        orders.order_status,
        orders.order_status = 'delivered' as is_delivered,
        orders.purchased_at,
        orders.purchased_at::date as purchase_date,
        orders.approved_at,
        orders.delivered_to_carrier_at,
        orders.delivered_to_customer_at,
        orders.estimated_delivery_date,
        coalesce(items.items_count, 0) as items_count,
        coalesce(items.sellers_count, 0) as sellers_count,
        coalesce(items.items_amount, 0) as items_amount,
        coalesce(items.freight_amount, 0) as freight_amount,
        coalesce(payments.payment_amount, 0) as payment_amount,
        payments.payments_count,
        payments.max_installments,
        payments.used_voucher,
        payments.main_payment_type,
        reviews.review_id,
        reviews.review_score,
        reviews.has_comment,
        reviews.reviews_count
    from orders
    inner join customers on orders.customer_id = customers.customer_id
    left join items on orders.order_id = items.order_id
    left join payments on orders.order_id = payments.order_id
    left join reviews on orders.order_id = reviews.order_id
),

with_delivery as (
    select
        *,
        delivered_to_customer_at::date - purchase_date as delivery_days,
        delivered_to_customer_at::date - estimated_delivery_date as delivery_delay_days,
        case
            when delivered_to_customer_at is null then null
            else delivered_to_customer_at::date > estimated_delivery_date
        end as is_late
    from joined
)

select * from with_delivery
