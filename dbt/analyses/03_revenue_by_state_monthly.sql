-- Month-over-month revenue change per state (drill-down for "why did revenue drop here?").
with monthly as (
    select
        customer_state as state,
        date_trunc('month', purchase_date)::date as month,
        sum(revenue) as revenue_brl
    from {{ ref('fct_order_items') }}
    where purchase_date between '2017-01-01' and '2018-08-31'
    group by customer_state, date_trunc('month', purchase_date)
),

with_previous as (
    select
        state,
        month,
        revenue_brl,
        lag(revenue_brl) over (partition by state order by month) as previous_month_brl
    from monthly
)

select
    state,
    month,
    revenue_brl,
    previous_month_brl,
    round(100.0 * (revenue_brl - previous_month_brl) / nullif(previous_month_brl, 0), 1)
        as mom_change_pct
from with_previous
where state in ('SP', 'RJ', 'MG') and month >= '2018-01-01'
order by state, month
