-- One row per order that has items: amounts before any revenue rule is applied.
with items as (
    select * from {{ ref('stg_olist__order_items') }}
),

aggregated as (
    select
        order_id,
        count(*) as items_count,
        count(distinct seller_id) as sellers_count,
        sum(price) as items_amount,
        sum(freight_value) as freight_amount
    from items
    group by order_id
)

select * from aggregated
