# Antops — convenience targets for the self-hosted Docker stack.
# Run `make help` for the list. Targets are deliberately thin wrappers around
# `docker compose` so you never have to guess the command.

SHELL := /bin/bash
COMPOSE ?= docker compose

.DEFAULT_GOAL := help

.PHONY: help up down restart logs ps build pull shell psql migrate health clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Start the stack in the background (builds if needed)
	@test -f .env || (echo "✖  .env not found. Run: cp .env.selfhosted.example .env" && exit 1)
	$(COMPOSE) up -d --build

down: ## Stop and remove containers (keeps volumes)
	$(COMPOSE) down

restart: ## Restart the app container only
	$(COMPOSE) restart app

logs: ## Tail logs from the app container
	$(COMPOSE) logs -f app

ps: ## Show container status
	$(COMPOSE) ps

build: ## Rebuild images without starting
	$(COMPOSE) build --pull

pull: ## Pull latest base images
	$(COMPOSE) pull

shell: ## Open a shell in the app container
	$(COMPOSE) exec app sh

psql: ## Open a psql prompt against the app database
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-antops} -d $${POSTGRES_DB:-antops}

migrate: ## (Re)apply the bundled schema — destructive on an existing DB
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-antops} -d $${POSTGRES_DB:-antops} \
	  -f /docker-entrypoint-initdb.d/02-schema.sql

health: ## Hit the app's health endpoint
	curl -fsS http://localhost:3000/api/health && echo

clean: ## Stop, remove containers AND delete volumes (wipes data)
	@read -p "This will delete postgres/minio/redis data. Continue? [y/N] " ok && [ "$$ok" = "y" ]
	$(COMPOSE) down -v
