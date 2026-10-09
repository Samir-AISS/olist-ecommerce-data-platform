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

> [!NOTE]
> This project is being built in public, phase by phase. Sections marked 🚧 are filled in as each phase lands — see the [roadmap](#roadmap). No number in this README is typed by hand: every figure is produced by a query in this repository.

---

## Table of contents

- [The business problem](#the-business-problem)
- [Architecture](#architecture)
- [Data model](#data-model)
- [KPI definitions](#kpi-definitions)
- [Data quality](#data-quality)
- [Key findings](#key-findings) 🚧
- [Dashboard](#dashboard) 🚧
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
  subgraph S["staging"]
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

  subgraph I["intermediate"]
    i_pay["int_payments_per_order"]
    i_rev["int_reviews_per_order"]
    i_ord["int_orders_enriched"]
    i_cus["int_customer_orders"]
  end

  subgraph M["marts"]
    f_itm["fct_order_items"]
    f_ord["fct_orders"]
    d_cus["dim_customers"]
    d_prd["dim_products"]
    d_sel["dim_sellers"]
    d_dat["dim_date"]
  end

  s_pay --> i_pay --> i_ord
  s_rev --> i_rev --> i_ord
  s_ord --> i_ord
  s_cus --> i_ord
  i_ord --> f_ord
  i_ord --> f_itm
  s_itm --> f_itm
  i_ord --> i_cus --> d_cus
  s_cus --> d_cus
  s_prd --> d_prd
  s_cat --> d_prd
  s_sel --> d_sel

  classDef stg fill:#E6F3F6,stroke:#0E7490,color:#1A202C
  classDef int fill:#E8EDF6,stroke:#1C3A5E,color:#1A202C
  classDef mart fill:#FFF4E0,stroke:#B7791F,color:#1A202C
  class s_ord,s_itm,s_pay,s_rev,s_cus,s_prd,s_sel,s_cat,s_geo stg
  class i_pay,i_rev,i_ord,i_cus int
  class f_itm,f_ord,d_cus,d_prd,d_sel,d_dat mart
```

*The full, clickable lineage graph is generated by `dbt docs` (published in phase 5).*

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
    string order_item_sk PK "hash of order_id + order_item_id"
    string order_id FK
    string customer_unique_id FK
    string product_id FK
    string seller_id FK
    date purchase_date FK
    numeric price "excludes freight"
    numeric freight_value
    string order_status
  }

  fct_orders {
    string order_id PK
    string customer_unique_id FK
    date purchase_date FK
    string order_status
    numeric items_amount
    numeric freight_amount
    numeric payment_amount
    int review_score
    int delivery_delay_days "actual minus estimated"
    boolean is_late
  }

  dim_customers {
    string customer_unique_id PK "the real person"
    string city
    string state
    date first_order_date
    int delivered_orders
    string rfm_segment
  }

  dim_products {
    string product_id PK
    string category_name_en
    int weight_g
    int volume_cm3
  }

  dim_sellers {
    string seller_id PK
    string city
    string state
  }

  dim_date {
    date date_day PK
    int year
    int month
    int day_of_week
    boolean is_weekend
    boolean is_br_holiday
  }
```

| Table | Grain (one row per…) | Notes |
|---|---|---|
| `fct_order_items` | **ordered item** (`order_id` + `order_item_id`) | Main fact table. Revenue, category, seller and regional analyses. Incremental on purchase date. |
| `fct_orders` | **order** | Order-level facts: payment, delivery delay, review score. |
| `dim_customers` | **customer** (`customer_unique_id`) | In Olist, `customer_id` is regenerated **for every order**; `customer_unique_id` identifies the real person. Using the wrong key would make every customer look like a one-time buyer. |
| `dim_products` | product | Category names translated to English. |
| `dim_sellers` | seller | |
| `dim_date` | calendar day | Includes Brazilian public holidays. |

Design choices are recorded as short ADRs in [docs/decisions.md](docs/decisions.md).

---

## KPI definitions

Each KPI is computed **in exactly one dbt model** and documented in [docs/kpi_dictionary.md](docs/kpi_dictionary.md) 🚧.

| KPI | Definition | Computed in |
|---|---|---|
| **Revenue** | Sum of item `price` for **delivered** orders. **Excludes freight** and cancelled or unavailable orders. | `fct_order_items` |
| **Average order value** | Revenue ÷ number of distinct delivered orders. | `fct_orders` |
| **Late delivery rate** | Delivered orders where the actual delivery date is after the estimated date ÷ delivered orders. | `fct_orders` |
| **Average review score** | Mean of the order's review score (1–5). Orders with several reviews keep the most recent one. | `fct_orders` |
| **Repeat purchase rate** | Customers (`customer_unique_id`) with ≥ 2 delivered orders ÷ customers with ≥ 1. | `dim_customers` |
| **RFM segment** | Recency, frequency and monetary scores (`NTILE`) combined into named segments. | `dim_customers` |

---

## Data quality

Tests run on every `dbt build`, locally and in CI. A failing test blocks the build.

| Type | What it guarantees | Examples |
|---|---|---|
| **Generic tests** | Keys are sound | `unique` + `not_null` on every primary key · `relationships` from each fact to its dimensions · `accepted_values` on `order_status` |
| **Grain test** | No duplicated facts | Fails if an `order_id` + `order_item_id` pair appears twice in `fct_order_items` |
| **Business rules** | Numbers reconcile | Amount paid ≈ items + freight (within tolerance) · delivery date ≥ purchase date · revenue contains no cancelled orders |
| **Code quality** | Readable, consistent code | `ruff` (Python) · `sqlfluff` (SQL) · `pre-commit` hooks |

### What the staging tests found in the source data

Measured on the full dataset by `make run` (staging: 9 models, 48 tests). Source anomalies are **flagged, not deleted**, so no order silently disappears.

| Finding | Count | How it is handled |
|---|---:|---|
| Zip codes starting with `0` | 23,995 customers | Kept as text in `raw` and staging (a numeric cast would drop the zero) |
| `review_id` values shared by several orders | 814 | Key is `review_id` + `order_id`, tested with `unique_combination_of_columns` |
| Orders handed to the carrier **before** they were placed | 166 | Test with `severity: warn`: visible in every build, does not block it |
| Geolocation points outside Brazil | 42 | Flagged with `is_in_brazil = false` |
| Seller city spellings (`"sao paulo / sao paulo"`, `"lages - sc"`) | 611 → 593 distinct | Normalized by the `clean_city_name` macro |
| Products without a category | 610 | Kept with a null category; handled in `dim_products` |

---

## Key findings

🚧 *Filled in phase 5.* Each finding will link to the query in `dbt/analyses/` that produced it, so anyone can re-run it with one command.

---

## Dashboard

🚧 *Built in Tableau Public in phase 5 — three pages:*

| Page | Audience | Answers |
|---|---|---|
| **Executive** | Leadership | Revenue, orders, AOV and late-delivery trends at a glance |
| **Sales** | Sales managers | Revenue by state, category and seller, with drill-down |
| **Customers** | CRM team | RFM segments, monthly cohorts, repeat purchase rate |

---

## Quick start

**Prerequisites:** Docker Desktop, [uv](https://docs.astral.sh/uv/) and GNU Make. No Kaggle account needed: the public dataset is downloaded automatically.

```bash
git clone https://github.com/Samir-AISS/olist-ecommerce-data-platform.git
cd olist-ecommerce-data-platform

make setup              # Python env (uv) + pre-commit hooks + .env from .env.example
make up                 # start PostgreSQL in Docker and wait until healthy
make run                # download the 9 CSV files → load raw → dbt build (models + tests)
make docs               # browse the dbt documentation and lineage graph on localhost:8081
```

| Command | What it does |
|---|---|
| `make test` | Unit tests + integration tests against PostgreSQL (`pytest`) |
| `make lint` / `make format` | `ruff` + `sqlfluff` checks / fixes |
| `make build` | `dbt build` only: run every model and its tests |
| `make sample` | Rebuild the 500-order CI sample in `data/sample/` |
| `make down` / `make reset-db` | Stop containers / also delete the database volume |
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
| **GitHub Actions** | CI | Lint, tests, load of a 500-order sample and `dbt build` on every pull request |

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
│   ├── macros/                 # clean_city_name, schema naming
│   └── tests/                  # singular business-rule tests
├── dags/                       # Airflow daily DAG
├── dashboard/                  # Tableau exports, screenshots, public link
├── scripts/                    # make_sample.py: builds the CI sample
├── data/sample/                # 500-order sample committed for CI
├── tests/                      # Python tests
├── docs/
│   ├── decisions.md            # architecture decision records
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
| 3 | Intermediate + star schema, incremental model, snapshot, tests | Documented star schema, grain test passing | ⬜ |
| 4 | KPI dictionary + advanced SQL analyses | `docs/kpi_dictionary.md`, `dbt/analyses/` | ⬜ |
| 5 | Tableau exports, dashboard, findings, dbt docs | Public dashboard link + findings in this README | ⬜ |

---

## Data source & license

- **Data:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (2016–2018), published under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). The data is **not** stored in this repository; it is downloaded at setup.
- **Code:** [MIT](LICENSE).

---

## Author

**Samir EL AISSAOUY** · Data Engineer · Analytics Engineer

[![LinkedIn](https://img.shields.io/badge/LinkedIn-samir--el--aissaouy-0A66C2?logo=linkedin)](https://www.linkedin.com/in/samir-el-aissaouy)
[![Email](https://img.shields.io/badge/Email-elaissaouy.samir12%40gmail.com-EA4335?logo=gmail&logoColor=white)](mailto:elaissaouy.samir12@gmail.com)
