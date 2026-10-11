# Tableau Public dashboard

Three pages built on the star schema. Every measure re-uses a definition from [docs/kpi_dictionary.md](../docs/kpi_dictionary.md), so the dashboard shows the same numbers as [docs/findings.md](../docs/findings.md).

**Public link:** [Olist - Ecommerce-Plateforme](https://public.tableau.com/app/profile/samir.el.aissa/viz/Olist-Ecommerce-Plateforme/Executive)

Screenshots: [Executive](screenshots/executive.png) · [Sales](screenshots/sales.png) · [Customers](screenshots/customers.png)

| Page | Audience | Question it answers |
|---|---|---|
| **Executive** | Leadership | How are revenue, delivery and satisfaction trending? |
| **Sales** | Sales managers | Why did revenue drop in this region? (answer in three clicks) |
| **Customers** | CRM team | Who should we retain, and do customers come back? |

---

## 1. Get the data

```bash
make run      # build the warehouse (skip if already done)
make export   # writes the 6 tables to data/exports/*.csv
```

Tableau Public cannot connect to PostgreSQL, so it reads these CSV files (64 MB in total). Booleans are exported as `true` / `false`.

## 2. Data source: relationships

In Tableau Public: **Connect → Text file → `fct_order_items.csv`**, then drag the other files next to it and set these relationships (Tableau's "noodles", not joins, so each table keeps its own grain):

| From `fct_order_items` | To | On |
|---|---|---|
| `order_id` | `fct_orders.csv` | `order_id` |
| `product_id` | `dim_products.csv` | `product_id` |
| `seller_id` | `dim_sellers.csv` | `seller_id` |
| `customer_unique_id` | `dim_customers.csv` | `customer_unique_id` |
| `purchase_date` | `dim_date.csv` | `date_day` |

Then set the geographic roles: `customer_state` and `dim_sellers.state` → **State/Province** (country: Brazil); `latitude` / `longitude` → Latitude / Longitude.

## 3. Calculated fields

Create these once and use them everywhere. They match the KPI dictionary exactly.

| Name | Formula | Table it reads |
|---|---|---|
| `Revenue` | `SUM([Revenue])` | `fct_order_items` |
| `Delivered Orders` | `SUM(IF [Is Delivered] THEN 1 ELSE 0 END)` | `fct_orders` |
| `AOV` | `SUM([Revenue (fct_orders)]) / [Delivered Orders]` | `fct_orders` |
| `Late Delivery Rate` | `SUM(IF [Is Late] THEN 1 ELSE 0 END) / SUM(IF NOT ISNULL([Is Late]) THEN 1 ELSE 0 END)` | `fct_orders` |
| `Avg Review Score` | `AVG([Review Score])` | `fct_orders` |
| `Repeat Purchase Rate` | `SUM(IF [Is Repeat Customer] THEN 1 ELSE 0 END) / SUM(IF [Delivered Orders (dim_customers)] > 0 THEN 1 ELSE 0 END)` | `dim_customers` |
| `Delay Bucket` | see below | `fct_orders` |
| `Cohort Month` | `{FIXED [Customer Unique Id] : MIN(IF [Is Delivered] THEN DATETRUNC('month', [Purchase Date]) END)}` | `fct_orders` |
| `Months Since First Order` | `DATEDIFF('month', [Cohort Month], DATETRUNC('month', [Purchase Date]))` (convert to a discrete dimension) | `fct_orders` |
| `Retention %` | `COUNTD([Customer Unique Id]) / LOOKUP(COUNTD([Customer Unique Id]), FIRST())`, computed along `Months Since First Order` | `fct_orders` |

```text
// Delay Bucket: same buckets as dbt/analyses/04_late_delivery_vs_reviews.sql
IF ISNULL([Delivery Delay Days]) THEN NULL
ELSEIF [Delivery Delay Days] <= -10 THEN "1. 10+ days early"
ELSEIF [Delivery Delay Days] <= 0 THEN "2. 0-9 days early"
ELSEIF [Delivery Delay Days] <= 3 THEN "3. 1-3 days late"
ELSEIF [Delivery Delay Days] <= 7 THEN "4. 4-7 days late"
ELSEIF [Delivery Delay Days] <= 14 THEN "5. 8-14 days late"
ELSE "6. 15+ days late"
END
```

**Check before building:** a text table with `Revenue`, `Delivered Orders`, `AOV`, `Late Delivery Rate`, `Avg Review Score` and `Repeat Purchase Rate` must show the values of [findings.md](../docs/findings.md) (13,221,498.11 · 96,478 · 137.04 · 6.77 % · 4.09 · 3.00 %). If one differs, a relationship or a filter is wrong.

## 4. Pages

### Executive

- KPI row: the six measures above as text tiles.
- **Monthly revenue** (line, `purchase_date` by month, 2017-01 to 2018-08): annotate Black Friday 2017.
- **Revenue by state** (filled map on `customer_state`).
- **Late delivery vs review** (bars: `Avg Review Score` by `Delay Bucket`, colour by bucket).
- Filter: year.

### Sales: "why did revenue drop in this region?" in three clicks

1. **Revenue by state** (sorted bars). *Click a state* → filters the rest of the page (dashboard action: filter).
2. **Monthly revenue of the selected state** (line + month-over-month % as a table calculation: *Percent difference from previous*). *Click the month that dropped* → filters the two views below.
3. **Revenue by category** and **top 10 sellers** for that state and month, each with its revenue change. *Click a category* to see which sellers it comes from.

Also show `Late Delivery Rate` and `Avg Review Score` for the selection: a drop often comes with late deliveries.

### Customers

- **RFM segments** (treemap: size = customers, colour = revenue share, label = `rfm_segment`).
- **Cohort retention** (heatmap: rows `Cohort Month`, columns `Months Since First Order`, colour = `Retention %`, i.e. distinct customers as a percent of month 0, restricted to 2017 cohorts; fix the colour range to 0-0.8 % so month 0 does not flatten it).
- KPI row: customers, `Repeat Purchase Rate`, `Avg Review Score`.
- **Repeat purchase rate by state** (filled map on `dim_customers.state`, the customer's state, not the seller's).
- Filter action: clicking an RFM segment filters the KPI row and the map.

## 5. Publish

1. **File → Save to Tableau Public** (free account).
2. Paste the public link at the top of this file and in the main README (Dashboard section).
3. Save one screenshot per page as `dashboard/screenshots/executive.png`, `sales.png` and `customers.png` (1600 px wide is enough) and add them to the Dashboard section of the main README.
