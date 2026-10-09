-- Completeness: no item is lost by the joins between staging and the fact table.
select
    order_id,
    order_item_id
from {{ ref('stg_olist__order_items') }}
except
select
    order_id,
    order_item_id
from {{ ref('fct_order_items') }}
