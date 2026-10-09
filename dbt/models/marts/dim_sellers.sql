-- One row per seller, with coordinates for maps.
with sellers as (
    select * from {{ ref('stg_olist__sellers') }}
),

locations as (
    select * from {{ ref('int_zip_code_locations') }}
)

select
    sellers.seller_id,
    sellers.zip_code_prefix,
    sellers.city,
    sellers.state,
    locations.latitude,
    locations.longitude
from sellers
left join locations on sellers.zip_code_prefix = locations.zip_code_prefix
