"""Export the star schema to CSV files for Tableau Public (which cannot read PostgreSQL).

Usage: python scripts/export_marts.py [--output-dir data/exports]
"""

import argparse
import sys
from pathlib import Path

import psycopg
from psycopg import sql

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ingestion.config import PROJECT_ROOT, DatabaseSettings

MARTS = [
    "fct_order_items",
    "fct_orders",
    "dim_customers",
    "dim_products",
    "dim_sellers",
    "dim_date",
]


def select_list(cur: psycopg.Cursor, schema: str, table: str) -> sql.Composed:
    """Columns of the table, with booleans cast to text: COPY would write them as t/f."""
    cur.execute(
        "SELECT column_name, data_type FROM information_schema.columns "
        "WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
        (schema, table),
    )
    columns = [
        sql.SQL("{}::text AS {}").format(sql.Identifier(name), sql.Identifier(name))
        if data_type == "boolean"
        else sql.Identifier(name)
        for name, data_type in cur.fetchall()
    ]
    return sql.SQL(", ").join(columns)


def export(conn: psycopg.Connection, output_dir: Path, schema: str = "marts") -> dict[str, int]:
    output_dir.mkdir(parents=True, exist_ok=True)
    row_counts: dict[str, int] = {}
    with conn.cursor() as cur:
        for table in MARTS:
            query = sql.SQL("COPY (SELECT {} FROM {}) TO STDOUT WITH (FORMAT csv, HEADER true)")
            query = query.format(select_list(cur, schema, table), sql.Identifier(schema, table))
            with (
                (output_dir / f"{table}.csv").open("wb") as f,
                cur.copy(query) as copy,
            ):
                for chunk in copy:
                    f.write(chunk)
            row_counts[table] = cur.rowcount
    return row_counts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output-dir", type=Path, default=PROJECT_ROOT / "data" / "exports")
    args = parser.parse_args(argv)

    with psycopg.connect(DatabaseSettings.from_env().conninfo()) as conn:
        row_counts = export(conn, args.output_dir)
    for table, rows in row_counts.items():
        print(f"  {table + '.csv':<24} {rows:>9,} rows")
    print(f"Exported {len(row_counts)} files to {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
