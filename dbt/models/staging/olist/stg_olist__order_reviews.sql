with source as (
    select * from {{ source('olist', 'order_reviews') }}
),

renamed as (
    select
        review_id,
        order_id,
        review_score::int as review_score,
        nullif(trim(review_comment_title), '') as comment_title,
        nullif(trim(review_comment_message), '') as comment_message,
        review_creation_date::timestamp as survey_sent_at,
        review_answer_timestamp::timestamp as answered_at
    from source
)

select * from renamed
