-- One row per real customer (customer_unique_id), with RFM scores and segment.
-- Recency is measured against the last purchase in the dataset, not today,
-- so the segments are reproducible.
with customers as (
    select * from {{ ref('int_customer_orders') }}
),

locations as (
    select * from {{ ref('int_zip_code_locations') }}
),

dataset_end as (
    select max(purchased_at)::date as as_of_date
    from {{ ref('int_orders_enriched') }}
),

scored as (
    select
        customers.*,
        dataset_end.as_of_date - customers.last_delivered_order_at::date as recency_days,
        -- R and M: quintiles among customers with a delivered order (5 = best)
        ntile(5) over (
            partition by customers.delivered_orders > 0
            order by customers.last_delivered_order_at asc, customers.customer_unique_id asc
        ) as recency_quintile,
        ntile(5) over (
            partition by customers.delivered_orders > 0
            order by customers.lifetime_revenue asc, customers.customer_unique_id asc
        ) as monetary_quintile
    from customers
    cross join dataset_end
),

rfm as (
    select
        *,
        case when delivered_orders > 0 then recency_quintile end as r_score,
        -- F uses fixed bands: 97% of customers buy once, so quintiles would be meaningless
        case
            when delivered_orders >= 3 then 5
            when delivered_orders = 2 then 3
            when delivered_orders = 1 then 1
        end as f_score,
        case when delivered_orders > 0 then monetary_quintile end as m_score
    from scored
),

final as (
    select
        rfm.customer_unique_id,
        rfm.zip_code_prefix,
        rfm.city,
        rfm.state,
        locations.latitude,
        locations.longitude,
        rfm.first_order_at,
        rfm.last_order_at,
        rfm.orders_count,
        rfm.delivered_orders,
        rfm.delivered_orders >= 2 as is_repeat_customer,
        rfm.lifetime_revenue,
        rfm.recency_days,
        rfm.r_score,
        rfm.f_score,
        rfm.m_score,
        case
            when rfm.delivered_orders = 0 then 'no_delivered_order'
            when rfm.f_score >= 3 and rfm.r_score >= 4 then 'champions'
            when rfm.f_score >= 3 then 'loyal'
            when rfm.m_score = 5 and rfm.r_score >= 3 then 'big_spenders'
            when rfm.r_score >= 4 then 'recent'
            when rfm.r_score <= 2 and rfm.m_score >= 4 then 'at_risk'
            when rfm.r_score <= 2 then 'lost'
            else 'need_attention'
        end as rfm_segment
    from rfm
    left join locations on rfm.zip_code_prefix = locations.zip_code_prefix
)

select * from final
