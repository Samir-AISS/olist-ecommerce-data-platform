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
