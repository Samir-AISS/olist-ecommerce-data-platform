-- Customer retention by monthly cohort (month of first delivered order).
-- Share of each cohort that ordered again N months later.
with orders as (
    select
        customer_unique_id,
        date_trunc('month', purchase_date)::date as order_month
    from {{ ref('fct_orders') }}
    where is_delivered
),

first_month as (
    select
        customer_unique_id,
        min(order_month) as cohort_month
    from orders
    group by customer_unique_id
),

activity as (
    select distinct
        orders.customer_unique_id,
        first_month.cohort_month,
        (
            (extract(year from orders.order_month) - extract(year from first_month.cohort_month))
            * 12
            + extract(month from orders.order_month) - extract(month from first_month.cohort_month)
        )::int as months_since_first
    from orders
    inner join first_month on orders.customer_unique_id = first_month.customer_unique_id
)

select
    cohort_month,
    count(*) filter (where months_since_first = 0) as cohort_customers,
    round(
        100.0 * count(*) filter (where months_since_first = 1)
        / count(*) filter (where months_since_first = 0), 2
    ) as m1_pct,
    round(
        100.0 * count(*) filter (where months_since_first = 3)
        / count(*) filter (where months_since_first = 0), 2
    ) as m3_pct,
    round(
        100.0 * count(*) filter (where months_since_first = 6)
        / count(*) filter (where months_since_first = 0), 2
    ) as m6_pct,
    round(
        100.0 * count(*) filter (where months_since_first between 1 and 12)
        / count(*) filter (where months_since_first = 0), 2
    ) as any_repeat_12m_pct
from activity
where cohort_month between '2017-01-01' and '2017-12-01'
group by cohort_month
order by cohort_month
