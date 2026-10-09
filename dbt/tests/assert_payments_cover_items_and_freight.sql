-- Amount paid should cover items + freight (paying more is normal: instalment interest).
-- 17 orders in the source are underpaid by more than 1 BRL: warn on any,
-- fail if the anomaly grows past 100 orders.
{{ config(warn_if='>0', error_if='>100') }}

select
    order_id,
    items_amount + freight_amount as amount_due,
    payment_amount
from {{ ref('fct_orders') }}
where
    payments_count is not null
    and payment_amount < items_amount + freight_amount - 1
