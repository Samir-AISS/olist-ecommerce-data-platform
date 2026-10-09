"""Daily Olist pipeline: download → load raw → dbt layer by layer → Tableau export.

Each dbt layer is its own task, so a failing test points to the layer that broke.
Tasks call the same commands as the Makefile, inside the pipeline virtualenv.
"""

import os
from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

# Defaults match the Docker image; override them to run the DAG elsewhere.
PROJECT_DIR = os.getenv("OLIST_PROJECT_DIR", "/opt/project")
PIPELINE_BIN = os.getenv("OLIST_PIPELINE_BIN", "/opt/pipeline-venv/bin")
PYTHON = f"{PIPELINE_BIN}/python"
DBT = f"{PIPELINE_BIN}/dbt"

with DAG(
    dag_id="olist_daily",
    description="Olist e-commerce: raw load, dbt build, Tableau export",
    schedule="0 6 * * *",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 2, "retry_delay": timedelta(minutes=5)},
    doc_md=__doc__,
    tags=["olist", "dbt"],
) as dag:

    def bash(task_id: str, command: str) -> BashOperator:
        return BashOperator(task_id=task_id, bash_command=f"cd {PROJECT_DIR} && {command}")

    download = bash("download_csv", f"{PYTHON} -m ingestion.download")
    load_raw = bash("load_raw", f"{PYTHON} -m ingestion.load_raw")
    dbt_deps = bash("dbt_deps", f"{DBT} deps")
    dbt_seed = bash("dbt_seed", f"{DBT} seed")
    dbt_staging = bash("dbt_staging", f"{DBT} build --select path:models/staging")
    dbt_snapshot = bash("dbt_snapshot", f"{DBT} snapshot")
    dbt_intermediate = bash("dbt_intermediate", f"{DBT} build --select path:models/intermediate")
    dbt_marts = bash("dbt_marts", f"{DBT} build --select path:models/marts")
    export = bash("export_for_tableau", f"{PYTHON} scripts/export_marts.py")

    download >> load_raw >> dbt_deps >> [dbt_seed, dbt_staging]
    dbt_staging >> [dbt_snapshot, dbt_intermediate]
    [dbt_seed, dbt_intermediate] >> dbt_marts >> export
