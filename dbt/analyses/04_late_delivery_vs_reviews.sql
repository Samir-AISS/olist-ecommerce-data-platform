-- Do late deliveries hurt review scores? Delivered and reviewed orders by delay bucket.
with orders as (
    select * from {{ ref('fct_orders') }}
    where is_delivered and is_late is not null and review_score is not null
),

bucketed as (
    select
        review_score,
        case
            when delivery_delay_days <= -10 then '1. 10+ days early'
            when delivery_delay_days <= 0 then '2. 0-9 days early'
            when delivery_delay_days <= 3 then '3. 1-3 days late'
            when delivery_delay_days <= 7 then '4. 4-7 days late'
            when delivery_delay_days <= 14 then '5. 8-14 days late'
            else '6. 15+ days late'
        end as delay_bucket
    from orders
)

select
    delay_bucket,
    count(*) as orders,
    round(100.0 * count(*) / sum(count(*)) over (), 1) as share_of_orders_pct,
    round(avg(review_score), 2) as avg_review_score,
    round(100.0 * avg((review_score <= 2)::int), 1) as one_or_two_stars_pct
from bucketed
group by delay_bucket
order by delay_bucket
