-- Which categories drive revenue? Ranked with cumulative share (Pareto) and satisfaction.
with items as (
    select * from {{ ref('fct_order_items') }}
    where is_delivered
),

orders as (
    select * from {{ ref('fct_orders') }}
),

products as (
    select * from {{ ref('dim_products') }}
),

by_category as (
    select
        products.category_name_en as category,
        sum(items.revenue) as revenue_brl,
        count(distinct items.order_id) as orders,
        round(avg(orders.review_score), 2) as avg_review_score,
        round(100.0 * avg(orders.is_late::int), 1) as late_rate_pct
    from items
    inner join products on items.product_id = products.product_id
    inner join orders on items.order_id = orders.order_id
    group by products.category_name_en
),

ranked as (
    select
        row_number() over (order by revenue_brl desc, category asc) as revenue_rank,
        category,
        revenue_brl,
        round(100.0 * revenue_brl / sum(revenue_brl) over (), 1) as revenue_share_pct,
        round(
            100.0 * sum(revenue_brl) over (
                order by revenue_brl desc, category asc
                rows between unbounded preceding and current row
            ) / sum(revenue_brl) over (),
            1
        ) as cumulative_share_pct,
        orders,
        avg_review_score,
        late_rate_pct,
        count(*) over () as categories_count
    from by_category
)

select * from ranked
where revenue_rank <= 15
order by revenue_rank
