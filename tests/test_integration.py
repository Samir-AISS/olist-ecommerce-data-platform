"""Load the sample into a throwaway schema and check row counts and idempotency."""

import csv
import os
from collections.abc import Iterator

import psycopg
import pytest
from psycopg import sql

from ingestion.config import SAMPLE_DATA_DIR, SOURCE_FILES, DatabaseSettings
from ingestion.load_raw import load_raw

pytestmark = pytest.mark.integration
TEST_SCHEMA = "raw_pytest"


@pytest.fixture
def conn() -> Iterator[psycopg.Connection]:
    try:
        connection = psycopg.connect(DatabaseSettings.from_env().conninfo(), connect_timeout=3)
    except (psycopg.OperationalError, RuntimeError) as exc:
        if os.getenv("REQUIRE_DB") == "1":  # set in CI: never skip silently there
            raise
        pytest.skip(f"PostgreSQL not reachable ({exc}); run `make up`")
    with connection:
        yield connection
        connection.execute(
            sql.SQL("DROP SCHEMA IF EXISTS {} CASCADE").format(sql.Identifier(TEST_SCHEMA))
        )


def csv_row_count(file_name: str) -> int:
    with (SAMPLE_DATA_DIR / file_name).open(encoding="utf-8-sig", newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def table_count(conn: psycopg.Connection, table: str) -> int:
    query = sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(TEST_SCHEMA, table))
    return conn.execute(query).fetchone()[0]


def test_load_matches_csv_row_counts(conn: psycopg.Connection) -> None:
    results = load_raw(conn, SAMPLE_DATA_DIR, TEST_SCHEMA)

    assert {r.file_name for r in results} == set(SOURCE_FILES)
    for r in results:
        expected = csv_row_count(r.file_name)
        assert r.row_count == expected, r.file_name
        assert table_count(conn, r.table) == expected, r.table


def test_reload_is_idempotent_and_audited(conn: psycopg.Connection) -> None:
    load_raw(conn, SAMPLE_DATA_DIR, TEST_SCHEMA)
    first = {table: table_count(conn, table) for table in SOURCE_FILES.values()}
    load_raw(conn, SAMPLE_DATA_DIR, TEST_SCHEMA)
    second = {table: table_count(conn, table) for table in SOURCE_FILES.values()}

    assert first == second
    assert table_count(conn, "_load_audit") == 2 * len(SOURCE_FILES)
