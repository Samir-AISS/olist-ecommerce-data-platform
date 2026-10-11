# Olist E-Commerce Data Platform

**Analytics Engineering & BI on 99,000+ real orders from a Brazilian marketplace.**
Raw CSVs in, tested star schema and business answers out — every KPI defined once, tested, and documented.

![Status](https://img.shields.io/badge/status-work%20in%20progress-orange)
[![CI](https://github.com/Samir-AISS/olist-ecommerce-data-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/Samir-AISS/olist-ecommerce-data-platform/actions/workflows/ci.yml)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![dbt](https://img.shields.io/badge/dbt-Core-FF694B?logo=dbt&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Docker-4169E1?logo=postgresql&logoColor=white)
![Airflow](https://img.shields.io/badge/Airflow-orchestration-017CEE?logo=apacheairflow&logoColor=white)
![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?logo=tableau&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

**[dbt documentation & lineage →](https://samir-aiss.github.io/olist-ecommerce-data-platform/)** · [KPI dictionary](docs/kpi_dictionary.md) · [Findings](docs/findings.md) · [Design decisions](docs/decisions.md)

> [!NOTE]
> No number in this README is typed by hand: every figure is produced by a query in [`dbt/analyses/`](dbt/analyses/) and collected in [docs/findings.md](docs/findings.md) by `make findings`.

---

## Table of contents

- [The business problem](#the-business-problem)
- [Architecture](#architecture)
- [Data model](#data-model)
- [KPI definitions](#kpi-definitions)
- [Advanced SQL analyses](#advanced-sql-analyses)
- [Data quality](#data-quality)
- [Key findings](#key-findings)
- [Dashboard](#dashboard)
- [Quick start](#quick-start)
- [Tech stack](#tech-stack)
- [Repository structure](#repository-structure)
- [Roadmap](#roadmap)
- [Data source & license](#data-source--license)

---

## The business problem

A sales leadership team at Olist wants to steer the business, but the data is spread across **9 CSV files with multiple keys**. Different people compute "revenue" in different ways, and nobody trusts the numbers.

This project answers four questions with one shared, tested definition per metric:

| # | Business question | Where it is answered |
|---|---|---|
| 1 | **Why does revenue vary by region**, and what drove a decline in a given state? | `fct_order_items` × `dim_customers` · dashboard page *Sales* |
| 2 | **Do late deliveries hurt review scores**, and by how much? | `fct_orders` · `dbt/analyses/late_delivery_vs_reviews.sql` |
| 3 | **Which customers are worth retaining**, and how many ever come back? | `dim_customers` (RFM) · `dbt/analyses/monthly_cohorts.sql` |
| 4 | **Which categories and sellers drive revenue**, and which drive complaints? | `fct_order_items` × `dim_products` / `dim_sellers` |

**Success criterion:** the dashboard explains *"why did revenue drop in this region?"* in three clicks.

---

## Architecture

```mermaid
flowchart LR
  subgraph SRC["① Source"]
    kaggle[("Olist dataset<br/>9 CSV files · Kaggle")]
  end

  subgraph ING["② Ingestion"]
    loader["Python loader<br/>CSV → raw schema"]
    airflow{{"Airflow<br/>daily DAG"}}
  end

  subgraph WH["③ Warehouse · PostgreSQL + dbt"]
    raw[("raw<br/>as-loaded copies")]
    stg["staging<br/>typing · renaming · cleaning"]
    int["intermediate<br/>joins · business rules"]
    marts["marts<br/>star schema"]
    snap["snapshot<br/>order status history · SCD2"]
    tests["dbt tests<br/>generic + business rules"]
  end

  subgraph OUT["④ Consumption"]
    analyses["analyses/<br/>cohorts · window functions"]
    exports["CSV exports"]
    tableau["Tableau Public<br/>3-page dashboard"]
    agent["Analyst agent<br/>future extension"]
  end

  kaggle --> loader --> raw --> stg --> int --> marts
  raw --> snap
  marts --> analyses
  marts --> exports --> tableau
  marts -.-> agent
  airflow -. orchestrates .-> loader
  airflow -. dbt build .-> stg
  tests -. guards .-> marts

  classDef source fill:#EEF2F6,stroke:#5B6675,color:#1A202C
  classDef process fill:#E6F3F6,stroke:#0E7490,color:#1A202C
  classDef store fill:#E8EDF6,stroke:#1C3A5E,color:#1A202C
  classDef serve fill:#FFF4E0,stroke:#B7791F,color:#1A202C
  classDef quality fill:#FDECEC,stroke:#C53030,color:#1A202C
  classDef future fill:#EFEAFB,stroke:#6B46C1,color:#1A202C,stroke-dasharray:4 3
  class kaggle source
  class loader,airflow process
  class raw,stg,int,marts,snap store
  class analyses,exports,tableau serve
  class tests quality
  class agent future
```

| Layer | Responsibility | Materialization |
|---|---|---|
| **raw** | Exact copy of the CSV files: every column is `TEXT`, streamed with `COPY` in one transaction, each load audited in `raw._load_audit`. | tables |
| **staging** (`stg_`) | One model per source table: cast types, rename to `snake_case`, trim and standardize values. No joins. | views |
| **intermediate** (`int_`) | Joins and business rules: aggregate payments and reviews per order, compute delivery delays. | views |
| **marts** (`fct_`, `dim_`) | Star schema consumed by BI and analyses. Explicit grain, fully tested. | tables · `fct_order_items` is **incremental** |
| **snapshots** | History of `order_status` changes (slowly changing dimension, type 2). | snapshot |

### dbt lineage

```mermaid
flowchart LR
  subgraph S["staging · 9 views"]
    s_ord["stg_olist__orders"]
    s_itm["stg_olist__order_items"]
    s_pay["stg_olist__order_payments"]
    s_rev["stg_olist__order_reviews"]
    s_cus["stg_olist__customers"]
    s_prd["stg_olist__products"]
    s_sel["stg_olist__sellers"]
    s_cat["stg_olist__product_category_translation"]
    s_geo["stg_olist__geolocation"]
  end

  subgraph I["intermediate · 6 views"]
    i_itm["int_items_per_order"]
    i_pay["int_payments_per_order"]
    i_rev["int_reviews_per_order"]
    i_ord["int_orders_enriched"]
    i_cus["int_customer_orders"]
    i_zip["int_zip_code_locations"]
  end

  subgraph M["marts · 6 tables"]
    f_itm["fct_order_items<br/>incremental"]
    f_ord["fct_orders"]
    d_cus["dim_customers"]
    d_prd["dim_products"]
    d_sel["dim_sellers"]
    d_dat["dim_date"]
  end

  seeds[("seeds<br/>holidays · translations")]

  s_itm --> i_itm --> i_ord
  s_pay --> i_pay --> i_ord
  s_rev --> i_rev --> i_ord
  s_ord --> i_ord
  s_cus --> i_ord
  i_ord --> f_ord
  i_ord --> f_itm
  s_itm --> f_itm
  i_ord --> i_cus --> d_cus
  s_geo --> i_zip
  i_zip --> d_cus
  i_zip --> d_sel
  s_prd --> d_prd
  s_cat --> d_prd
  s_sel --> d_sel
  seeds --> d_prd
  seeds --> d_dat

  classDef stg fill:#E6F3F6,stroke:#0E7490,color:#1A202C
  classDef int fill:#E8EDF6,stroke:#1C3A5E,color:#1A202C
  classDef mart fill:#FFF4E0,stroke:#B7791F,color:#1A202C
  classDef seed fill:#EEF2F6,stroke:#5B6675,color:#1A202C
  class s_ord,s_itm,s_pay,s_rev,s_cus,s_prd,s_sel,s_cat,s_geo stg
  class i_itm,i_pay,i_rev,i_ord,i_cus,i_zip int
  class f_itm,f_ord,d_cus,d_prd,d_sel,d_dat mart
  class seeds seed
```

*The full, clickable lineage graph is generated by `make docs`.*

---

### Orchestration

`dags/olist_daily.py` runs every day at 06:00: one task per step, so a failing test points to the layer that broke. Retries: 2, five minutes apart.

```mermaid
flowchart LR
  download_csv --> load_raw --> dbt_deps
  dbt_deps --> dbt_seed
  dbt_deps --> dbt_staging
  dbt_staging --> dbt_snapshot
  dbt_staging --> dbt_intermediate
  dbt_seed --> dbt_marts
  dbt_intermediate --> dbt_marts
  dbt_marts --> export_for_tableau

  classDef task fill:#E6F3F6,stroke:#0E7490,color:#1A202C
  class download_csv,load_raw,dbt_deps,dbt_seed,dbt_staging,dbt_snapshot,dbt_intermediate,dbt_marts,export_for_tableau task
```

A full run on the complete dataset (Airflow 3.3.2, `airflow dags test olist_daily`) succeeds in about 4 min 40 s. In Docker, dbt and the ingestion code live in their own virtualenv inside the Airflow image, so their dependencies never clash with Airflow's.

---

## Data model

```mermaid
erDiagram
  dim_customers ||--o{ fct_orders : places
  dim_customers ||--o{ fct_order_items : buys
  fct_orders ||--o{ fct_order_items : contains
  dim_products ||--o{ fct_order_items : "sold as"
  dim_sellers ||--o{ fct_order_items : fulfils
  dim_date ||--o{ fct_order_items : "purchased on"
  dim_date ||--o{ fct_orders : "purchased on"

  fct_order_items {
    text order_item_sk PK "hash of order_id + order_item_id"
    text order_id FK
    int order_item_id
    text customer_unique_id FK
    text customer_state "at the time of the order"
    text product_id FK
    text seller_id FK
    date purchase_date FK
    text order_status
    boolean is_delivered
    numeric price "excludes freight"
    numeric freight_value
    numeric revenue "price if delivered, else 0"
  }

  fct_orders {
    text order_id PK
    text customer_unique_id FK
    text customer_state
    date purchase_date FK
    text order_status
    boolean is_delivered
    int items_count
    numeric items_amount
    numeric freight_amount
    numeric payment_amount
    numeric revenue
    text main_payment_type
    int review_score "latest review"
    int delivery_days
    int delivery_delay_days "actual minus promised"
    boolean is_late
  }

  dim_customers {
    text customer_unique_id PK "the real person"
    text city
    text state "latest address"
    float latitude
    float longitude
    int delivered_orders
    boolean is_repeat_customer
    numeric lifetime_revenue
    int r_score
    int f_score
    int m_score
    text rfm_segment
  }

  dim_products {
    text product_id PK
    text category_name_en
    int weight_g
    int volume_cm3
  }

  dim_sellers {
    text seller_id PK
    text city
    text state
    float latitude
    float longitude
  }

  dim_date {
    date date_day PK
    int year
    int month
    text year_month
    int day_of_week
    boolean is_weekend
    boolean is_br_holiday
    boolean is_black_friday
  }
```

| Table | Grain (one row per…) | Rows | Notes |
|---|---|---:|---|
| `fct_order_items` | **ordered item** (`order_id` + `order_item_id`) | 112,650 | Main fact table. **Incremental** (`delete+insert`), re-processes the last 30 days of purchases on each run. |
| `fct_orders` | **order** | 99,441 | Payment, latest review, delivery delay. |
| `dim_customers` | **customer** (`customer_unique_id`) | 96,096 | `customer_id` is regenerated **for every order**; `customer_unique_id` identifies the person. Using the wrong key would make every customer look like a one-time buyer. |
| `dim_products` | product | 32,951 | English category for every product (2 missing translations added by a seed, `unknown` when the source has none). |
| `dim_sellers` | seller | 3,095 | Coordinates for maps. |
| `dim_date` | calendar day | 1,096 | Brazilian national holidays (seed) and Black Friday. |

Row counts from `make run` on the full dataset.

**Two notions of "customer state".** Facts carry `customer_state` *at the time of the order*; `dim_customers.state` is the *latest* address. Revenue by region uses the first, so a customer who moves does not move past revenue with them.

### Order status history (SCD type 2)

`dbt/snapshots/snap_orders_status.yml` keeps one version of an order per status change, with `dbt_valid_from` / `dbt_valid_to`. Verified by simulating a delivery on a shipped order:

| order_status | order_delivered_customer_date | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| shipped | | 2026-10-09 00:08 | 2026-10-09 00:11 |
| delivered | 2018-09-01 10:00 | 2026-10-09 00:11 | |

Design choices are recorded as short ADRs in [docs/decisions.md](docs/decisions.md).

---

## KPI definitions

Each KPI is computed **in exactly one dbt model** and documented in [docs/kpi_dictionary.md](docs/kpi_dictionary.md): definition, SQL formula, exclusions, and the tests that guard it.

| KPI | Definition | Computed in | Value |
|---|---|---|---:|
| **Revenue** | Sum of item `price` for **delivered** orders. **Excludes freight** and undelivered orders. | `fct_order_items.revenue` | 13,221,498.11 BRL |
| **Average order value** | Revenue ÷ delivered orders. | `fct_orders` | 137.04 BRL |
| **Late delivery rate** | Delivered after the promised date ÷ delivered orders with a delivery date. | `fct_orders.is_late` | 6.77 % |
| **Average review score** | Mean score (1–5) of reviewed orders; latest review wins. | `fct_orders.review_score` | 4.09 |
| **Repeat purchase rate** | Customers (`customer_unique_id`) with ≥ 2 delivered orders ÷ customers with ≥ 1. | `dim_customers.is_repeat_customer` | 3.00 % |
| **RFM segment** | Recency and monetary quintiles (`NTILE`), frequency bands, combined into 7 named segments. | `dim_customers.rfm_segment` | [see findings](docs/findings.md) |

Values computed by [`dbt/analyses/01_kpi_summary.sql`](dbt/analyses/01_kpi_summary.sql) on the full dataset.

## Advanced SQL analyses

Nine versioned queries in [`dbt/analyses/`](dbt/analyses/), compiled by dbt (so they use `ref()` and the same models as the dashboard) and executed by `make findings`, which regenerates [docs/findings.md](docs/findings.md).

| Query | SQL techniques |
|---|---|
| `02_revenue_by_state` | `rank()`, share of total with `sum() over ()` |
| `03_revenue_by_state_monthly` | month-over-month change with `lag()` |
| `04_late_delivery_vs_reviews` | bucketing with `case`, conditional averages |
| `05_monthly_cohorts` | cohort retention, `count(*) filter (where …)` pivots |
| `06_category_pareto` | running total `sum() over (order by … rows between unbounded preceding and current row)` |
| `07_seller_concentration` | `ntile(10)` deciles |
| `08_rfm_segments` | segment sizing with window shares |
| `09_black_friday` | join to the date dimension |

---|---|---|
| **Revenue** | Sum of item `price` for **delivered** orders. **Excludes freight** and cancelled or unavailable orders. | `fct_order_items` |
| **Average order value** | Revenue ÷ number of distinct delivered orders. | `fct_orders` |
| **Late delivery rate** | Delivered orders where the actual delivery date is after the estimated date ÷ delivered orders. | `fct_orders` |
| **Average review score** | Mean of the order's review score (1–5). Orders with several reviews keep the most recent one. | `fct_orders` |
| **Repeat purchase rate** | Customers (`customer_unique_id`) with ≥ 2 delivered orders ÷ customers with ≥ 1. | `dim_customers` |
| **RFM segment** | Recency, frequency and monetary scores (`NTILE`) combined into named segments. | `dim_customers` |

---

## Data quality

Tests run on every `dbt build`, locally and in CI. A failing test blocks the build. Current result on the full dataset: **127 nodes, PASS=125, WARN=2, ERROR=0**.

| Type | What it guarantees | Examples |
|---|---|---|
| **Generic tests** | Keys are sound | `unique` + `not_null` on every primary key · `relationships` from each fact to its dimensions · `accepted_values` on `order_status` |
| **Grain test** | No duplicated facts | Fails if an `order_id` + `order_item_id` pair appears twice in `fct_order_items` |
| **Business rules** | Numbers reconcile | Revenue identical from `fct_order_items` and `fct_orders` · no revenue from undelivered orders · every staging item reaches the fact table · amount paid covers items + freight |
| **Code quality** | Readable, consistent code | `ruff` (Python) · `sqlfluff` (SQL) · `pre-commit` hooks |

### What the tests found in the source data

Measured on the full dataset by `make run` (staging: 9 models, 48 tests). Source anomalies are **flagged, not deleted**, so no order silently disappears.

| Finding | Count | How it is handled |
|---|---:|---|
| Zip codes starting with `0` | 23,995 customers | Kept as text in `raw` and staging (a numeric cast would drop the zero) |
| `review_id` values shared by several orders | 814 | Key is `review_id` + `order_id`, tested with `unique_combination_of_columns` |
| Orders handed to the carrier **before** they were placed | 166 | Test with `severity: warn`: visible in every build, does not block it |
| Geolocation points outside Brazil | 42 | Flagged with `is_in_brazil = false` |
| Seller city spellings (`"sao paulo / sao paulo"`, `"lages - sc"`) | 611 → 593 distinct | Normalized by the `clean_city_name` macro |
| Products without a category | 610 | Kept; `category_name_en = 'unknown'` in `dim_products` |
| Orders paid **less** than items + freight (by > 1 BRL) | 17 | Test warns on any, fails above 100 (`warn_if` / `error_if`) |

Payments match items + freight to the cent for 98,362 of the 98,665 orders that have both; most of the remaining overpayments (229 of 232) are instalment plans, where interest is added.

---

## Key findings

Full results and queries: [docs/findings.md](docs/findings.md).

### 1. Late deliveries destroy satisfaction, and the damage starts at day one

| Delivered vs promised date | Orders | Avg review | 1–2 star reviews |
|---|---:|---:|---:|
| 10+ days early | 61,523 | 4.32 | 8.9 % |
| 0–9 days early | 27,920 | 4.22 | 10.1 % |
| 1–3 days late | 1,852 | 3.29 | 32.1 % |
| 4–7 days late | 1,748 | 2.10 | 67.7 % |
| 8–14 days late | 1,446 | 1.67 | 80.2 % |

Only 6.6 % of reviewed orders arrive late, but a delay of 4 days or more turns two thirds of them into 1–2 star reviews. **Action:** promise dates are a lever as strong as speed: most orders already arrive 10+ days early, so the buffer could be reallocated to the routes that miss it. *([query](dbt/analyses/04_late_delivery_vs_reviews.sql))*

### 2. Revenue is concentrated in the South-East; distance costs freight, time and stars

São Paulo alone makes **38.3 %** of revenue, with an 8.7-day average delivery and a 4.5 % late rate (review 4.25). In the North-East, freight weighs far more and customers wait 2–3× longer: Maranhão pays **26.3 %** of the item value in freight with a 17.4 % late rate (review 3.83); Alagoas waits **24.5 days** on average with a **21.4 %** late rate (review 3.85). Rio de Janeiro is the outlier among large states: **12.1 %** late vs 4.5 % for São Paulo, and a 3.97 review. *([query](dbt/analyses/02_revenue_by_state.sql))*

### 3. Almost nobody comes back

The repeat purchase rate is **3.00 %** (customers counted with `customer_unique_id`). No 2017 monthly cohort exceeds **3.75 %** of customers buying again within 12 months, and fewer than 1 % return the following month. Growth comes from acquisition; retention is the untapped lever. *([cohorts](dbt/analyses/05_monthly_cohorts.sql))*

### 4. Revenue depends on a few sellers and categories, and on the RFM segments to protect

- The top 10 % of sellers make **67.1 %** of revenue; the bottom half makes 3.3 %. *([query](dbt/analyses/07_seller_concentration.sql))*
- The top 7 of 74 categories make **49.9 %** of revenue (health & beauty first, 9.3 %). *([query](dbt/analyses/06_category_pareto.sql))*
- `big_spenders` (10.9 % of customers) hold **30.5 %** of revenue, and `at_risk` customers (14.8 %, last order ~443 days ago) another **28.9 %**: the first target for a win-back campaign. *([query](dbt/analyses/08_rfm_segments.sql))*

### 5. Black Friday multiplies orders by five

On Black Friday 2017 the marketplace received **1,166 orders**, against **217 per day** on the other days of November (5.4×), for 149,916.58 BRL of revenue in a single day. *([query](dbt/analyses/09_black_friday.sql))*

---

## Dashboard

Tableau Public, three pages built on CSV exports of the star schema (`make export`). The build guide, with every calculated field mapped to the KPI dictionary, is in [dashboard/README.md](dashboard/README.md).

| Page | Audience | Answers |
|---|---|---|
| **Executive** | Leadership | Revenue, orders, AOV, late-delivery and satisfaction trends at a glance |
| **Sales** | Sales managers | "Why did revenue drop in this region?" in three clicks: state → month → category and sellers |
| **Customers** | CRM team | RFM segments, monthly cohort retention, repeat purchase rate |

**Public link:** [Olist - Ecommerce-Plateforme on Tableau Public](https://public.tableau.com/app/profile/samir.el.aissa/viz/Olist-Ecommerce-Plateforme/Executive).

![Executive page](dashboard/screenshots/executive.png)

![Sales page](dashboard/screenshots/sales.png)

![Customers page](dashboard/screenshots/customers.png)

---

## Quick start

**Prerequisites:** Docker Desktop, [uv](https://docs.astral.sh/uv/) and GNU Make. No Kaggle account needed: the public dataset is downloaded automatically.

```bash
git clone https://github.com/Samir-AISS/olist-ecommerce-data-platform.git
cd olist-ecommerce-data-platform

make setup              # Python env (uv) + pre-commit hooks + .env from .env.example
make up                 # start PostgreSQL in Docker and wait until healthy
make run                # download the 9 CSV files → load raw → dbt build (models + tests)
make findings           # run the SQL analyses → docs/findings.md
make export             # star schema → data/exports/*.csv for Tableau
make airflow-up         # optional: Airflow UI on localhost:8080 with the daily DAG
make docs               # browse the dbt documentation and lineage graph on localhost:8081
```

| Command | What it does |
|---|---|
| `make test` | Unit tests + integration tests against PostgreSQL (`pytest`) |
| `make lint` / `make format` | `ruff` + `sqlfluff` checks / fixes |
| `make build` | `dbt build` only: run every model and its tests |
| `make sample` | Rebuild the 500-order CI sample in `data/sample/` |
| `make down` / `make reset-db` | Stop containers / also delete the database volume |
| `make airflow-up` / `make airflow-down` | Start / stop Airflow (Docker profile `airflow`) |
| `make help` | List every command |

### Raw layer after `make run`

Row counts printed by `ingestion/load_raw.py` on the full dataset:

| Table | Rows |
|---|---:|
| `raw.geolocation` | 1,000,163 |
| `raw.order_items` | 112,650 |
| `raw.order_payments` | 103,886 |
| `raw.customers` | 99,441 |
| `raw.orders` | 99,441 |
| `raw.order_reviews` | 99,224 |
| `raw.products` | 32,951 |
| `raw.sellers` | 3,095 |
| `raw.product_category_name_translation` | 71 |
| **Total** | **1,550,922** |

> `wc -l` reports 104,719 lines for the reviews file: some review comments span several lines. Loading with a real CSV parser (`COPY`) gives the correct 99,224 reviews.

---

## Tech stack

| Tool | Role | Why this choice |
|---|---|---|
| **PostgreSQL** (Docker) | Warehouse | Free, standard SQL, runs anywhere |
| **dbt Core** | Transformations, tests, docs, lineage | The core Analytics Engineering tool: SQL with versioning, tests and documentation |
| **Python + uv** | CSV ingestion, tooling | Fast, reproducible environments |
| **Airflow** | Daily orchestration | Shows how the pipeline is scheduled and monitored in production |
| **Tableau Public** | BI dashboard | Free, shareable public link |
| **ruff · sqlfluff · pytest · pre-commit** | Code quality | Consistent style and safety net before every commit |
| **GitHub Actions** | CI | Lint, tests, load of a 500-order sample, `dbt build` and every analysis on every pull request |

---

## Repository structure

```text
olist-ecommerce-data-platform/
├── ingestion/                  # load the CSV files into the raw schema
├── dbt/
│   ├── models/staging/         # stg_olist__*: one model per source table
│   ├── models/intermediate/    # int_*: joins and business rules
│   ├── models/marts/           # fct_* and dim_*: the star schema
│   ├── snapshots/              # order status history (SCD2)
│   ├── analyses/               # advanced SQL: cohorts, window functions, findings
│   ├── seeds/                  # Brazilian holidays, missing category translations
│   ├── macros/                 # clean_city_name, schema naming
│   └── tests/                  # singular business-rule tests
├── dags/                       # Airflow daily DAG (olist_daily)
├── docker/airflow/             # Airflow image with an isolated pipeline virtualenv
├── dashboard/                  # Tableau build guide, screenshots, public link
├── scripts/                    # CI sample, findings and Tableau export scripts
├── data/sample/                # 500-order sample committed for CI
├── tests/                      # Python tests
├── docs/
│   ├── decisions.md            # architecture decision records
│   ├── findings.md             # generated by make findings
│   └── kpi_dictionary.md       # one definition per KPI
├── docker-compose.yml · Makefile · pyproject.toml
└── README.md
```

---

## Roadmap

| Phase | Scope | Verifiable deliverable | Status |
|---|---|---|---|
| 1 | Project skeleton: Docker, ingestion, tooling, CI | `make setup && make up && make run` loads the raw schema | ✅ |
| 2 | dbt sources + staging layer, naming conventions | `dbt build` green on staging | ✅ |
| 3 | Intermediate + star schema, incremental model, snapshot, tests | Documented star schema, grain test passing | ✅ |
| 4 | KPI dictionary + advanced SQL analyses | `docs/kpi_dictionary.md`, `dbt/analyses/` | ✅ |
| 5 | Findings, Tableau exports, dashboard guide, dbt docs on GitHub Pages | Findings in this README, public dbt docs | ✅ |
| 6 | Airflow daily DAG | Full DAG run green; DAG import checked in CI | ✅ |
| 7 | Tableau Public dashboard | Public link + screenshots in this README | ✅ |


---

## Data source & license

- **Data:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (2016–2018), published under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The data is **not** stored in this repository; it is downloaded at setup.
- **Code:** [MIT](LICENSE).

---

## Author

**Samir EL AISSAOUY** · Data Engineer · Analytics Engineer

[![LinkedIn](https://img.shields.io/badge/LinkedIn-samir--el--aissaouy-0A66C2?logo=linkedin)](https://www.linkedin.com/in/samir-el-aissaouy)
[![Email](https://img.shields.io/badge/Email-elaissaouy.samir12%40gmail.com-EA4335?logo=gmail&logoColor=white)](mailto:elaissaouy.samir12@gmail.com)
