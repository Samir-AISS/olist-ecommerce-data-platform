"""Load the Olist CSV files into the raw schema of PostgreSQL.

The raw schema is an exact copy of the source files:
- every column is TEXT (typing happens in dbt staging, where it is tested);
- files are streamed with COPY, which keeps multi-line review comments intact;
- all tables are truncated and reloaded in one transaction, so a run either
  fully succeeds or leaves the previous load untouched;
- each load is recorded in raw._load_audit (row count and SHA-256 of the file).

Usage: python -m ingestion.load_raw [--data-dir data/sample] [--schema raw]
"""

import argparse
import csv
import hashlib
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import psycopg
from psycopg import sql

from ingestion.config import RAW_DATA_DIR, SOURCE_FILES, DatabaseSettings

AUDIT_TABLE = "_load_audit"
CHUNK_SIZE = 1 << 20  # 1 MiB
_IDENTIFIER = re.compile(r"^[a-z_][a-z0-9_]*$")


@dataclass(frozen=True)
class LoadResult:
    file_name: str
    table: str
    row_count: int
    sha256: str


def read_header(path: Path) -> list[str]:
    """Return the column names of a CSV file, without the UTF-8 BOM some files carry."""
    with path.open(encoding="utf-8-sig", newline="") as f:
        header = next(csv.reader(f), None)
    if not header:
        raise ValueError(f"{path.name} is empty")
    columns = [column.strip() for column in header]
    invalid = [column for column in columns if not _IDENTIFIER.match(column)]
    if invalid:
        raise ValueError(f"{path.name} has unexpected column names: {invalid}")
    return columns


def check_source_files(data_dir: Path) -> list[Path]:
    """Return the expected CSV paths, or fail listing every missing file."""
    paths = [data_dir / name for name in SOURCE_FILES]
    missing = [path.name for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            f"Missing files in {data_dir}: {', '.join(missing)}. Run `make download` first."
        )
    return paths


def _ensure_table(cur: psycopg.Cursor, schema: str, table: str, columns: list[str]) -> None:
    cur.execute(
        sql.SQL("CREATE TABLE IF NOT EXISTS {} ({})").format(
            sql.Identifier(schema, table),
            sql.SQL(", ").join(sql.SQL("{} text").format(sql.Identifier(c)) for c in columns),
        )
    )
    cur.execute(
        "SELECT column_name FROM information_schema.columns "
        "WHERE table_schema = %s AND table_name = %s ORDER BY ordinal_position",
        (schema, table),
    )
    existing = [row[0] for row in cur.fetchall()]
    if existing != columns:
        raise RuntimeError(
            f"{schema}.{table} columns {existing} do not match the file header {columns}. "
            "Drop the table (make reset-db) if the source format changed on purpose."
        )


def _copy_file(cur: psycopg.Cursor, path: Path, schema: str, table: str) -> tuple[int, str]:
    digest = hashlib.sha256()
    copy_sql = sql.SQL("COPY {} FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')").format(
        sql.Identifier(schema, table)
    )
    with path.open("rb") as f, cur.copy(copy_sql) as copy:
        while chunk := f.read(CHUNK_SIZE):
            digest.update(chunk)
            copy.write(chunk)
    return cur.rowcount, digest.hexdigest()


def load_raw(conn: psycopg.Connection, data_dir: Path, schema: str = "raw") -> list[LoadResult]:
    """Truncate and reload every source table in a single transaction."""
    paths = check_source_files(data_dir)
    results: list[LoadResult] = []
    with conn.transaction(), conn.cursor() as cur:
        cur.execute(sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(schema)))
        cur.execute(
            sql.SQL(
                "CREATE TABLE IF NOT EXISTS {} ("
                "file_name text NOT NULL, table_name text NOT NULL, row_count bigint NOT NULL, "
                "sha256 char(64) NOT NULL, loaded_at timestamptz NOT NULL DEFAULT now())"
            ).format(sql.Identifier(schema, AUDIT_TABLE))
        )
        for path in paths:
            table = SOURCE_FILES[path.name]
            _ensure_table(cur, schema, table, read_header(path))
            cur.execute(sql.SQL("TRUNCATE {}").format(sql.Identifier(schema, table)))
            row_count, sha256 = _copy_file(cur, path, schema, table)
            cur.execute(
                sql.SQL(
                    "INSERT INTO {} (file_name, table_name, row_count, sha256) "
                    "VALUES (%s, %s, %s, %s)"
                ).format(sql.Identifier(schema, AUDIT_TABLE)),
                (path.name, table, row_count, sha256),
            )
            results.append(LoadResult(path.name, table, row_count, sha256))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-dir", type=Path, default=RAW_DATA_DIR)
    parser.add_argument("--schema", default="raw")
    args = parser.parse_args(argv)

    started = time.perf_counter()
    with psycopg.connect(DatabaseSettings.from_env().conninfo()) as conn:
        results = load_raw(conn, args.data_dir, args.schema)

    for r in results:
        print(f"  {args.schema}.{r.table:<36} {r.row_count:>10,} rows")
    total = sum(r.row_count for r in results)
    elapsed = time.perf_counter() - started
    print(f"Loaded {total:,} rows from {len(results)} files in {elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
