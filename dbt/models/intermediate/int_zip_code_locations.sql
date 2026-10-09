-- One row per zip code prefix: average coordinates of the points inside Brazil.
with geolocation as (
    select * from {{ ref('stg_olist__geolocation') }}
)

select
    zip_code_prefix,
    avg(latitude) as latitude,
    avg(longitude) as longitude
from geolocation
where is_in_brazil
group by zip_code_prefix
