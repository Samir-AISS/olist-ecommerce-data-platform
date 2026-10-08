from pathlib import Path

import pytest

from ingestion.config import SAMPLE_DATA_DIR, SOURCE_FILES
from ingestion.load_raw import check_source_files, read_header


def test_every_source_file_maps_to_a_unique_table() -> None:
    assert len(SOURCE_FILES) == 9
    assert len(set(SOURCE_FILES.values())) == len(SOURCE_FILES)


def test_read_header_strips_utf8_bom(tmp_path: Path) -> None:
    path = tmp_path / "with_bom.csv"
    path.write_bytes("﻿product_category_name,product_category_name_english\na,b\n".encode())
    assert read_header(path) == ["product_category_name", "product_category_name_english"]


def test_read_header_rejects_unsafe_column_names(tmp_path: Path) -> None:
    path = tmp_path / "bad.csv"
    path.write_text('order_id,"drop table; --"\n1,2\n')
    with pytest.raises(ValueError, match="unexpected column names"):
        read_header(path)


def test_read_header_rejects_empty_file(tmp_path: Path) -> None:
    path = tmp_path / "empty.csv"
    path.write_text("")
    with pytest.raises(ValueError, match="empty"):
        read_header(path)


def test_check_source_files_lists_every_missing_file(tmp_path: Path) -> None:
    (tmp_path / "olist_orders_dataset.csv").write_text("order_id\n")
    with pytest.raises(FileNotFoundError) as excinfo:
        check_source_files(tmp_path)
    message = str(excinfo.value)
    assert "olist_customers_dataset.csv" in message
    assert "olist_orders_dataset.csv" not in message


def test_sample_contains_every_source_file() -> None:
    assert len(check_source_files(SAMPLE_DATA_DIR)) == len(SOURCE_FILES)
