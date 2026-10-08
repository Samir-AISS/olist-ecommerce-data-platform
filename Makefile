.DEFAULT_GOAL := help
.PHONY: help setup up down reset-db download load run sample test lint format

help: ## Show available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

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

run: download load ## Run the pipeline end to end

sample: ## Rebuild the CI sample in data/sample from data/raw
	uv run python scripts/make_sample.py

test: ## Run unit and integration tests
	uv run pytest

lint: ## Check code style
	uv run ruff check .
	uv run ruff format --check .

format: ## Fix code style
	uv run ruff check --fix .
	uv run ruff format .
