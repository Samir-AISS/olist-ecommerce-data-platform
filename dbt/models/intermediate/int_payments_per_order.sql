-- One row per order: payments aggregated, main payment type = largest amount.
with payments as (
    select * from {{ ref('stg_olist__order_payments') }}
),

ranked as (
    select
        *,
        row_number() over (
            partition by order_id
            order by payment_value desc, payment_sequential asc
        ) as amount_rank
    from payments
),

aggregated as (
    select
        order_id,
        sum(payment_value) as payment_amount,
        count(*) as payments_count,
        max(payment_installments) as max_installments,
        bool_or(payment_type = 'voucher') as used_voucher,
        max(case when amount_rank = 1 then payment_type end) as main_payment_type
    from ranked
    group by order_id
)

select * from aggregated
