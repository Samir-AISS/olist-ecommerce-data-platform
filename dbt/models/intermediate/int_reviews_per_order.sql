-- One row per reviewed order: when an order has several reviews, keep the latest answer.
with reviews as (
    select * from {{ ref('stg_olist__order_reviews') }}
),

ranked as (
    select
        *,
        count(*) over (partition by order_id) as reviews_count,
        row_number() over (
            partition by order_id
            order by answered_at desc, survey_sent_at desc, review_id asc
        ) as recency_rank
    from reviews
),

latest as (
    select
        order_id,
        review_id,
        review_score,
        comment_message is not null as has_comment,
        answered_at as review_answered_at,
        reviews_count
    from ranked
    where recency_rank = 1
)

select * from latest
