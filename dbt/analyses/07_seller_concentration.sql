-- How concentrated is revenue among sellers? Revenue share by seller decile.
with by_seller as (
    select
        seller_id,
        sum(revenue) as revenue_brl
    from {{ ref('fct_order_items') }}
    where is_delivered
    group by seller_id
),

deciles as (
    select
        *,
        ntile(10) over (order by revenue_brl desc, seller_id asc) as revenue_decile
    from by_seller
)

select
    revenue_decile,
    count(*) as sellers,
    sum(revenue_brl) as revenue_brl,
    round(100.0 * sum(revenue_brl) / sum(sum(revenue_brl)) over (), 1) as revenue_share_pct
from deciles
group by revenue_decile
order by revenue_decile
