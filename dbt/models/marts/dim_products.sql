-- One row per product, with an English category for every product.
with products as (
    select * from {{ ref('stg_olist__products') }}
),

translations as (
    select * from {{ ref('stg_olist__product_category_translation') }}
),

overrides as (
    select * from {{ ref('category_translation_overrides') }}
),

final as (
    select
        products.product_id,
        coalesce(products.category_name, 'unknown') as category_name,
        coalesce(
            translations.category_name_en,
            overrides.category_name_en,
            case when products.category_name is null then 'unknown' end
        ) as category_name_en,
        products.photos_count,
        products.weight_g,
        products.length_cm,
        products.height_cm,
        products.width_cm,
        products.length_cm * products.height_cm * products.width_cm as volume_cm3
    from products
    left join translations on products.category_name = translations.category_name
    left join overrides on products.category_name = overrides.category_name
)

select * from final
