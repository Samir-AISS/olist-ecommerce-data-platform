"""The CI sample must stay referentially consistent, like the full dataset."""

import csv

from ingestion.config import SAMPLE_DATA_DIR


def column(file_name: str, name: str) -> set[str]:
    with (SAMPLE_DATA_DIR / file_name).open(encoding="utf-8-sig", newline="") as f:
        return {row[name] for row in csv.DictReader(f)}


def test_every_item_belongs_to_a_sampled_order() -> None:
    orders = column("olist_orders_dataset.csv", "order_id")
    assert column("olist_order_items_dataset.csv", "order_id") <= orders
    assert column("olist_order_payments_dataset.csv", "order_id") <= orders
    assert column("olist_order_reviews_dataset.csv", "order_id") <= orders


def test_every_order_has_its_customer() -> None:
    customers = column("olist_customers_dataset.csv", "customer_id")
    assert column("olist_orders_dataset.csv", "customer_id") <= customers


def test_every_item_has_its_product_and_seller() -> None:
    items = "olist_order_items_dataset.csv"
    assert column(items, "product_id") <= column("olist_products_dataset.csv", "product_id")
    assert column(items, "seller_id") <= column("olist_sellers_dataset.csv", "seller_id")
