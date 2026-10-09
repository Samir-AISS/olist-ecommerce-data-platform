# KPI dictionary

One definition per KPI. Each one is computed from a single column or rule in the marts, guarded by tests, and its current value is produced by [`dbt/analyses/01_kpi_summary.sql`](../dbt/analyses/01_kpi_summary.sql) (see [findings.md](findings.md)).

**Shared rules** (defined once in `int_orders_enriched`):

- **Delivered order**: `order_status = 'delivered'` → column `is_delivered`.
- **Late order**: delivered after the date promised at purchase, compared at day level (`delivered_to_customer_at::date > estimated_delivery_date`) → column `is_late`. Null when the order was never delivered.
- **Customer**: a person, identified by `customer_unique_id`. Never `customer_id`, which changes with every order.
- **Currency**: Brazilian real (BRL), as in the source. No currency conversion.

---

## Revenue

| | |
|---|---|
| **Business question** | How much did we sell? |
| **Definition** | Sum of item prices of **delivered** orders. Freight is excluded. |
| **Formula** | `sum(fct_order_items.revenue)` where `revenue = price if is_delivered else 0` |
| **Grain** | Item (`fct_order_items`); also available per order in `fct_orders.revenue` |
| **Excludes** | Freight; canceled, unavailable, shipped, invoiced, processing, created and approved orders |
| **Why not `payment_value`?** | Payments include freight and instalment interest, so they mix sales with logistics and financing |
| **Guarded by** | `assert_revenue_only_from_delivered_orders`, `assert_revenue_reconciles_between_facts`, `assert_every_item_reaches_the_fact_table` |
| **Current value** | 13,221,498.11 BRL |

## Average order value (AOV)

| | |
|---|---|
| **Business question** | How much does a customer spend per order? |
| **Definition** | Revenue ÷ number of delivered orders |
| **Formula** | `sum(fct_orders.revenue) / count(*) filter (where is_delivered)` |
| **Grain** | Order |
| **Excludes** | Undelivered orders (in both numerator and denominator); freight |
| **Current value** | 137.04 BRL |

## Late delivery rate

| | |
|---|---|
| **Business question** | How often do we break our delivery promise? |
| **Definition** | Delivered orders that arrived after the promised date ÷ delivered orders with a known delivery date |
| **Formula** | `count(*) filter (where is_late) / count(*) filter (where is_late is not null)` on `fct_orders` |
| **Grain** | Order |
| **Excludes** | Orders never delivered; 8 orders marked delivered without a delivery date |
| **Edge case** | Arriving on the promised day counts as on time |
| **Current value** | 6.77 % |

## Average review score

| | |
|---|---|
| **Business question** | How satisfied are customers? |
| **Definition** | Mean score (1 to 5) of reviewed orders. When an order has several reviews, the latest answer counts |
| **Formula** | `avg(fct_orders.review_score)` (nulls ignored) |
| **Grain** | Order |
| **Excludes** | Orders without a review (768) |
| **Guarded by** | `accepted_values` 1-5 on `stg_olist__order_reviews.review_score`; uniqueness of `int_reviews_per_order.order_id` |
| **Current value** | 4.09 / 5 |

## Repeat purchase rate

| | |
|---|---|
| **Business question** | Do customers come back? |
| **Definition** | Customers with 2 or more delivered orders ÷ customers with at least 1 delivered order |
| **Formula** | `count(*) filter (where is_repeat_customer) / count(*) filter (where delivered_orders > 0)` on `dim_customers` |
| **Grain** | Customer (`customer_unique_id`) |
| **Pitfall avoided** | Counted with `customer_id`, this rate would be 0 % because the key changes with every order |
| **Current value** | 3.00 % |

## RFM segment

| | |
|---|---|
| **Business question** | Which customers should the CRM team target, and how? |
| **Definition** | Each customer with a delivered order gets three scores, then a named segment |
| **Recency (R)** | Quintile of the last delivered order date (5 = most recent). Measured from the last purchase in the dataset (2018-10-17), not from today, so results are reproducible |
| **Frequency (F)** | Fixed bands: 1 delivered order = 1, 2 = 3, 3 or more = 5. Quintiles are meaningless when 97 % of customers bought once |
| **Monetary (M)** | Quintile of lifetime revenue (5 = highest) |
| **Segments** (first rule that matches) | `champions`: F ≥ 3 and R ≥ 4 · `loyal`: F ≥ 3 · `big_spenders`: M = 5 and R ≥ 3 · `recent`: R ≥ 4 · `at_risk`: R ≤ 2 and M ≥ 4 · `lost`: R ≤ 2 · `need_attention`: everyone else · `no_delivered_order`: no delivered order |
| **Formula** | `NTILE(5)` window functions in `dim_customers`, ties broken by `customer_unique_id` |
| **Guarded by** | `accepted_values` on `dim_customers.rfm_segment` |
| **Current values** | See [findings.md](findings.md#rfm-segments-size-and-value) |
