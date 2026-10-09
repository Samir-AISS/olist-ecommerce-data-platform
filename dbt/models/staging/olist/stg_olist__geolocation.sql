with source as (
    select * from {{ source('olist', 'geolocation') }}
),

renamed as (
    select
        geolocation_zip_code_prefix as zip_code_prefix,
        geolocation_lat::double precision as latitude,
        geolocation_lng::double precision as longitude,
        {{ clean_city_name('geolocation_city') }} as city,
        upper(trim(geolocation_state)) as state
    from source
),

flagged as (
    select
        *,
        -- a few points fall outside Brazil's bounding box (bad geocoding)
        coalesce(
            latitude between -34.0 and 5.5 and longitude between -74.0 and -34.5,
            false
        ) as is_in_brazil
    from renamed
)

select * from flagged
