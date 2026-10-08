"""Build a small, referentially consistent sample of the Olist dataset for CI.

Picks orders deterministically (lowest MD5 of order_id), then keeps every related
row: items, payments, reviews, customers, products, sellers, and a few
geolocation rows per zip prefix. The sample is committed in data/sample so CI
can run the pipeline without a Kaggle account.

Usage: python scripts/make_sample.py [--orders 500]
"""

import argparse
import csv
import hashlib
import sys
from collections import defaultdict
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingestion.config import RAW_DATA_DIR, SAMPLE_DATA_DIR

GEO_ROWS_PER_PREFIX = 3

Row = dict[str, str]


def read_rows(name: str) -> tuple[list[str], list[Row]]:
    with (RAW_DATA_DIR / name).open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader.fieldnames or []), list(reader)


def write_rows(name: str, header: list[str], rows: list[Row]) -> None:
    with (SAMPLE_DATA_DIR / name).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"  {name:<45} {len(rows):>6} rows")


def keep(name: str, predicate: Callable[[Row], bool]) -> list[Row]:
    header, rows = read_rows(name)
    kept = [row for row in rows if predicate(row)]
    write_rows(name, header, kept)
    return kept


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--orders", type=int, default=500)
    args = parser.parse_args(argv)
    SAMPLE_DATA_DIR.mkdir(parents=True, exist_ok=True)

    header, orders = read_rows("olist_orders_dataset.csv")
    orders.sort(key=lambda row: hashlib.md5(row["order_id"].encode()).hexdigest())
    orders = orders[: args.orders]
    write_rows("olist_orders_dataset.csv", header, orders)

    order_ids = {row["order_id"] for row in orders}
    customer_ids = {row["customer_id"] for row in orders}

    items = keep("olist_order_items_dataset.csv", lambda r: r["order_id"] in order_ids)
    keep("olist_order_payments_dataset.csv", lambda r: r["order_id"] in order_ids)
    keep("olist_order_reviews_dataset.csv", lambda r: r["order_id"] in order_ids)
    customers = keep("olist_customers_dataset.csv", lambda r: r["customer_id"] in customer_ids)

    product_ids = {row["product_id"] for row in items}
    seller_ids = {row["seller_id"] for row in items}
    keep("olist_products_dataset.csv", lambda r: r["product_id"] in product_ids)
    sellers = keep("olist_sellers_dataset.csv", lambda r: r["seller_id"] in seller_ids)

    prefixes = {row["customer_zip_code_prefix"] for row in customers}
    prefixes |= {row["seller_zip_code_prefix"] for row in sellers}
    seen: defaultdict[str, int] = defaultdict(int)

    def first_rows_per_prefix(row: Row) -> bool:
        prefix = row["geolocation_zip_code_prefix"]
        if prefix not in prefixes or seen[prefix] >= GEO_ROWS_PER_PREFIX:
            return False
        seen[prefix] += 1
        return True

    keep("olist_geolocation_dataset.csv", first_rows_per_prefix)
    keep("product_category_name_translation.csv", lambda r: True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
