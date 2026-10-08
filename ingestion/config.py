"""Shared settings: database connection and the list of expected source files."""

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv
from psycopg.conninfo import make_conninfo

PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"
SAMPLE_DATA_DIR = PROJECT_ROOT / "data" / "sample"

KAGGLE_DATASET = "olistbr/brazilian-ecommerce"

# Source CSV file -> table name in the raw schema.
SOURCE_FILES: dict[str, str] = {
    "olist_customers_dataset.csv": "customers",
    "olist_geolocation_dataset.csv": "geolocation",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_orders_dataset.csv": "orders",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "product_category_name_translation.csv": "product_category_name_translation",
}


@dataclass(frozen=True)
class DatabaseSettings:
    host: str
    port: int
    user: str
    password: str
    dbname: str

    @classmethod
    def from_env(cls) -> "DatabaseSettings":
        load_dotenv(PROJECT_ROOT / ".env")
        missing = [
            name
            for name in ("POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB")
            if not os.getenv(name)
        ]
        if missing:
            raise RuntimeError(
                f"Missing environment variables: {', '.join(missing)}. "
                "Copy .env.example to .env (make setup does it for you)."
            )
        return cls(
            host=os.getenv("POSTGRES_HOST", "localhost"),
            port=int(os.getenv("POSTGRES_PORT", "5432")),
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"],
            dbname=os.environ["POSTGRES_DB"],
        )

    def conninfo(self) -> str:
        # make_conninfo quotes values, so passwords with spaces or quotes work.
        return make_conninfo(
            host=self.host,
            port=self.port,
            user=self.user,
            password=self.password,
            dbname=self.dbname,
        )
