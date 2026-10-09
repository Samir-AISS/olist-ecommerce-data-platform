.DEFAULT_GOAL := help
.PHONY: help setup up down reset-db download load deps build run findings docs sample test lint format

# Database credentials for dbt and Python (dbt does not read .env on its own)
-include .env
export

export DBT_PROJECT_DIR := dbt
export DBT_PROFILES_DIR := dbt
DBT := uv run dbt

help: ## Show available commands
	@grep -E '^[a-z-]+:.*## ' Makefile | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

setup: ## Install Python env and git hooks, create .env
	uv sync
	uv run pre-commit install
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")

up: ## Start PostgreSQL and wait until it is healthy
	docker compose up -d --wait

down: ## Stop containers (data is kept)
	docker compose down

reset-db: ## Stop containers and delete the database volume
	docker compose down -v

download: ## Download the Olist CSV files into data/raw
	uv run python -m ingestion.download

load: ## Load data/raw into the raw schema
	uv run python -m ingestion.load_raw

deps: ## Install dbt packages
	$(DBT) deps

build: deps ## Build and test every dbt model
	$(DBT) build

run: download load build ## Run the pipeline end to end

findings: deps ## Run the SQL analyses and regenerate docs/findings.md
	$(DBT) compile --select "resource_type:analysis" --quiet
	uv run python scripts/run_analyses.py

docs: deps ## Generate and serve the dbt documentation (lineage graph)
	$(DBT) docs generate
	$(DBT) docs serve --port 8081

sample: ## Rebuild the CI sample in data/sample from data/raw
	uv run python scripts/make_sample.py

test: ## Run unit and integration tests
	uv run pytest

lint: ## Check Python and SQL style
	uv run ruff check .
	uv run ruff format --check .
	uv run sqlfluff lint dbt/models dbt/macros dbt/tests dbt/analyses

format: ## Fix Python and SQL style
	uv run ruff check --fix .
	uv run ruff format .
	uv run sqlfluff fix dbt/models dbt/macros dbt/tests dbt/analyses
