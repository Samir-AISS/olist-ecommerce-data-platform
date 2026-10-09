FROM apache/airflow:3.3.2-python3.11

# dbt and the ingestion code run in their own virtualenv, so their dependencies
# never conflict with Airflow's pinned constraints.
COPY docker/airflow/requirements-pipeline.txt /tmp/requirements-pipeline.txt
RUN python -m venv /opt/pipeline-venv \
    && /opt/pipeline-venv/bin/pip install --no-cache-dir -r /tmp/requirements-pipeline.txt
