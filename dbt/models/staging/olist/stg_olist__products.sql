with source as (
    select * from {{ source('olist', 'products') }}
),

renamed as (
    select
        product_id,
        nullif(trim(product_category_name), '') as category_name,
        -- the source misspells "length" as "lenght"
        product_name_lenght::int as product_name_length,
        product_description_lenght::int as product_description_length,
        product_photos_qty::int as photos_count,
        product_weight_g::int as weight_g,
        product_length_cm::int as length_cm,
        product_height_cm::int as height_cm,
        product_width_cm::int as width_cm
    from source
)

select * from renamed
