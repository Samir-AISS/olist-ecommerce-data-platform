# Architecture Decision Records

Short records of the technical choices made in this project: context, decision, alternatives, consequences.

---

## ADR-001 · Start from a clean repository

- **Context:** a first version of this platform exists in another repository. Its Git history contains a committed `.env` file with database credentials, and its dbt models follow a bronze / silver / gold layout.
- **Decision:** rebuild in a new repository with a clean history. Reuse ideas, not files.
- **Alternatives:** rewrite the old history (`git filter-repo`) and keep the repository — rejected: forks and clones may still hold the secret, and the layout changes anyway.
- **Consequences:** no secret in history; the old repository will be archived once this one is published.

## ADR-002 · staging / intermediate / marts instead of bronze / silver / gold

- **Context:** bronze / silver / gold ("medallion") is a lakehouse convention. This project is a dbt + PostgreSQL warehouse.
- **Decision:** follow dbt's recommended layers: `stg_` (one model per source, no joins), `int_` (joins and business rules), `fct_` / `dim_` (star schema).
- **Alternatives:** keep medallion names — rejected: misleading for a warehouse and not the dbt standard.
- **Consequences:** model names state their role; lineage reads left to right.

## ADR-003 · Customers keyed by `customer_unique_id`

- **Context:** in the Olist dataset, `customer_id` is generated **for every order**. `customer_unique_id` identifies the actual person.
- **Decision:** `dim_customers` has one row per `customer_unique_id`; facts carry that key.
- **Alternatives:** key by `customer_id` — rejected: every customer would appear to buy only once, making repeat purchase rate and RFM meaningless.
- **Consequences:** staging maps `customer_id` → `customer_unique_id` before facts are built.

## ADR-004 · Revenue = item price of delivered orders, excluding freight

- **Context:** "revenue" can include or exclude freight, cancelled orders, or use payment amounts (which include instalment interest).
- **Decision:** revenue = sum of item `price` for orders with status `delivered`, freight excluded. Defined once in `fct_order_items` and documented in `docs/kpi_dictionary.md`.
- **Alternatives:** sum of `payment_value` — rejected: mixes freight and payment terms with sales.
- **Consequences:** a business-rule test checks that no cancelled order contributes to revenue.

## ADR-005 · Raw layer: all TEXT, loaded with COPY in one transaction

- **Context:** the raw layer must be a faithful copy of the source. Review comments contain line breaks, and one file starts with a UTF-8 BOM.
- **Decision:** every raw column is `TEXT`; files are streamed with PostgreSQL `COPY ... (FORMAT csv)`; all tables are truncated and reloaded in a single transaction; each load is logged in `raw._load_audit` with its row count and SHA-256.
- **Alternatives:** `pandas.to_sql` — rejected: slower, infers types silently (zip codes lose leading zeros), and the old pipeline needed workarounds for it.
- **Consequences:** typing and cleaning happen in dbt staging, where they are tested. A failed load leaves the previous data untouched. Tables are truncated, not dropped, so dbt views built on them survive reloads.

## ADR-006 · Airflow deferred until there is something to orchestrate

- **Context:** the brief includes a daily Airflow DAG. In phase 1 the pipeline is a single load step.
- **Decision:** start with PostgreSQL only in Docker Compose; add Airflow once dbt models exist.
- **Alternatives:** ship the full Airflow stack from day one — rejected: heavier setup for no benefit yet.
- **Consequences:** `make up` starts in seconds and uses little memory.

## ADR-007 · A committed 500-order sample for CI

- **Context:** CI must run the real pipeline, not just check that files exist, but it cannot depend on a Kaggle download.
- **Decision:** `scripts/make_sample.py` picks 500 orders deterministically and keeps every related row (items, payments, reviews, customers, products, sellers, geolocation). The 500 KB sample is committed in `data/sample/` (dataset license CC BY-NC-SA 4.0, attributed in the README).
- **Alternatives:** download the full dataset in CI — rejected: slow and needs network access to Kaggle; random sampling — rejected: not reproducible and breaks foreign keys.
- **Consequences:** CI loads a referentially consistent dataset in seconds; a test guards that consistency.

## ADR-008 · Source anomalies are flagged, not deleted

- **Context:** profiling found orders handed to the carrier before purchase (166), geolocation points outside Brazil (42) and shared `review_id` values (814).
- **Decision:** staging keeps every row. Anomalies get a flag column (`is_in_brazil`) or a test with `severity: warn`; keys are adapted to the real grain (`review_id` + `order_id`).
- **Alternatives:** filter bad rows in staging — rejected: revenue and order counts would silently drift from the source, and nobody would know why.
- **Consequences:** every `dbt build` shows the anomaly count; downstream models decide explicitly what to exclude.

## ADR-009 · One PostgreSQL schema per dbt layer

- **Context:** by default dbt names custom schemas `<target>_<custom>` (e.g. `analytics_staging`).
- **Decision:** override `generate_schema_name` so models land in `staging`, `intermediate` and `marts`, next to `raw`.
- **Alternatives:** keep dbt's default — rejected: longer names, harder to read in BI tools.
- **Consequences:** the database mirrors the architecture diagram. A shared multi-developer setup would need per-developer schemas again.

## ADR-010 · Business rules defined once, in the intermediate layer

- **Context:** "delivered" and "late" are used by several marts and KPIs. Defining them in each model invites drift.
- **Decision:** `int_orders_enriched` defines `is_delivered` (`order_status = 'delivered'`) and `is_late` (delivered after the promised date). Marts reuse these columns; `revenue` = price (or items amount) when `is_delivered`, else 0.
- **Alternatives:** compute KPIs in the BI tool — rejected: each dashboard would re-implement the rule.
- **Consequences:** a singular test checks that revenue is identical from `fct_order_items` and `fct_orders`, and another that no undelivered order carries revenue.

## ADR-011 · Incremental fact table with a look-back window

- **Context:** `fct_order_items` is the largest mart. Olist has no `updated_at` column, and an order's status can change after purchase.
- **Decision:** `incremental` with `delete+insert` on `order_item_sk`; each run re-processes orders purchased in the last `incremental_lookback_days` (30) before the latest loaded purchase.
- **Alternatives:** full rebuild each time — simpler but does not scale; `append` — rejected: duplicates when a status changes.
- **Consequences:** changes older than 30 days need `dbt build --full-refresh`. The status history itself is kept by the snapshot.

## ADR-012 · RFM: quintiles for recency and monetary, fixed bands for frequency

- **Context:** 97% of customers placed a single delivered order. `NTILE(5)` on frequency would split identical values arbitrarily.
- **Decision:** R and M are `NTILE(5)` quintiles (ties broken by `customer_unique_id`, so results are deterministic); F uses bands (1 order = 1, 2 = 3, 3+ = 5). Recency is measured from the last purchase in the dataset, not from today.
- **Alternatives:** classic 5×5×5 quintiles — rejected for the reason above.
- **Consequences:** segments (champions, loyal, big_spenders, recent, need_attention, at_risk, lost) are reproducible and documented in `dim_customers`.

## ADR-013 · Customer state at order time on the facts

- **Context:** a customer (`customer_unique_id`) can order from different addresses.
- **Decision:** facts carry `customer_state` from the order's own `customer_id`; `dim_customers` keeps the latest address.
- **Alternatives:** join facts to `dim_customers.state` — rejected: past revenue would move to the region the customer lives in today.
- **Consequences:** regional revenue is historically correct; the dimension stays one row per person.

## ADR-014 · Findings generated from versioned queries

- **Context:** a portfolio README often quotes numbers that nobody can reproduce.
- **Decision:** every analysis is a dbt analysis in `dbt/analyses/` (so it uses `ref()` and the tested marts). `make findings` compiles and runs them and rewrites `docs/findings.md`. The README only quotes numbers from that file.
- **Alternatives:** notebooks — rejected: hidden state, hard to review in a pull request.
- **Consequences:** CI runs every analysis on the sample, so a query broken by a model change fails the build.

## ADR-015 · Tableau Public fed by CSV exports; dbt docs on GitHub Pages

- **Context:** Tableau Public (free) cannot connect to a database. Recruiters should be able to browse the models without running anything.
- **Decision:** `make export` writes the six star-schema tables to CSV with `COPY` (booleans as `true`/`false`); Tableau relates them on their keys, keeping each table's grain. A GitHub Actions workflow builds the warehouse on the sample and publishes `dbt docs` to GitHub Pages on every merge.
- **Alternatives:** one wide denormalized export — rejected: order-level measures would be duplicated per item; Metabase or Superset — possible, but Tableau Public gives a shareable public link.
- **Consequences:** the dashboard must be refreshed by re-exporting; the public docs show the sample's catalog statistics but the full lineage and every test.
