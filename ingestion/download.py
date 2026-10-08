"""Download the Olist dataset from Kaggle into data/raw.

Skips the download when all expected files are already present.
Usage: python -m ingestion.download [--force]
"""

import argparse
import shutil
import sys
from pathlib import Path

from ingestion.config import KAGGLE_DATASET, RAW_DATA_DIR, SOURCE_FILES

MANUAL_STEPS = f"""
Automatic download failed. Download the dataset manually:
  1. Open https://www.kaggle.com/datasets/{KAGGLE_DATASET}
  2. Click "Download" and unzip the archive
  3. Copy the 9 CSV files into {RAW_DATA_DIR}
Or create a Kaggle API token (Kaggle > Settings > API) and save it to ~/.kaggle/kaggle.json.
"""


def missing_files(data_dir: Path) -> list[str]:
    return [name for name in SOURCE_FILES if not (data_dir / name).is_file()]


def download(data_dir: Path, force: bool = False) -> None:
    if not force and not missing_files(data_dir):
        print(f"All {len(SOURCE_FILES)} files already in {data_dir}, skipping download.")
        return

    import kagglehub  # imported lazily: only needed when downloading

    source_dir = Path(kagglehub.dataset_download(KAGGLE_DATASET))
    data_dir.mkdir(parents=True, exist_ok=True)
    for name in SOURCE_FILES:
        shutil.copy2(source_dir / name, data_dir / name)

    still_missing = missing_files(data_dir)
    if still_missing:
        raise FileNotFoundError(f"Not found in the Kaggle archive: {', '.join(still_missing)}")
    print(f"Downloaded {len(SOURCE_FILES)} files into {data_dir}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="download even if files exist")
    args = parser.parse_args(argv)
    try:
        download(RAW_DATA_DIR, force=args.force)
    except Exception as exc:
        print(f"Error: {exc}\n{MANUAL_STEPS}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
