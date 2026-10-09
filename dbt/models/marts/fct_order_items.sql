-- One row per ordered item (order_id + order_item_id). Main fact table.
-- Incremental: each run re-processes the last N days of purchases
-- (var incremental_lookback_days) to pick up late status changes.
{{ config(
    materialized='incremental',
    unique_key='order_item_sk',
    incremental_strategy='delete+insert',
    on_schema_change='append_new_columns'
) }}

with items as (
    select * from {{ ref('stg_olist__order_items') }}
),

orders as (
    select * from {{ ref('int_orders_enriched') }}
    {% if is_incremental() %}
        where purchased_at >= (
            select
                max(previous_run.purchased_at)
                - interval '{{ var("incremental_lookback_days") }} days'
            from {{ this }} as previous_run
        )
    {% endif %}
),

final as (
    select
        {{ dbt_utils.generate_surrogate_key(['items.order_id', 'items.order_item_id']) }}
            as order_item_sk,
        items.order_id,
        items.order_item_id,
        orders.customer_unique_id,
        orders.customer_state,
        items.product_id,
        items.seller_id,
        orders.purchase_date,
        orders.purchased_at,
        orders.order_status,
        orders.is_delivered,
        items.price,
        items.freight_value,
        case when orders.is_delivered then items.price else 0 end as revenue
    from items
    inner join orders on items.order_id = orders.order_id
)

select * from final
