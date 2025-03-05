# Use bash for all commands
SHELL := /bin/bash

# Variables
ENV ?= production
DOCKER_COMPOSE = docker compose
COMPOSE_FILE = $(if $(filter local production,$(ENV)),-f docker-compose.yml,-f docker-compose-production.yml)

# Build Docker containers
.PHONY: build build-local
build:
	@echo "Building containers for $(ENV) environment..."
	@if [[ "$(ENV)" == "local" ]]; then \
		$(DOCKER_COMPOSE) -f docker-compose.yml build --parallel; \
	else \
		$(DOCKER_COMPOSE) -f docker-compose-production.yml build --parallel; \
	fi

build-local: ENV=local
build-local: build

# Run Docker Compose Down
.PHONY: down
down:
	@echo "Stopping containers for $(ENV) environment..."
	@if [[ "$(ENV)" == "local" ]]; then \
		$(DOCKER_COMPOSE) -f docker-compose.yml down; \
	else \
		$(DOCKER_COMPOSE) -f docker-compose-production.yml down; \
	fi

.PHONY: up
up:
	@echo "Starting containers for $(ENV) environment..."
	@if [[ "$(ENV)" == "local" ]]; then \
		$(DOCKER_COMPOSE) -f docker-compose.yml up -d; \
	else \
		$(DOCKER_COMPOSE) -f docker-compose-production.yml up -d; \
	fi

# Export and build containers one at a time
.PHONY: export-and-build export-and-build-local
export-and-build: clean-cache
	@echo "Exporting and building containers for $(ENV) environment..."
	@mkdir -p apptainer
	@for pair in \
		"ezbids-api:api" \
		"ezbids-handler:handler" \
		"ezbids-ui:ui" \
		"ezbids-telemetry:telemetry" \
		"mongo:mongo" \
		"nginx:nginx"; do \
		IFS=":"; set -- $$pair; \
		echo "Processing $$1 -> $$2_image.tar..."; \
		if ! docker save -o apptainer/$$2_image.tar $$1; then \
			echo "ERROR: Failed to export $$1"; \
			echo "To retry this step manually, run:"; \
			echo "  docker save -o apptainer/$$2_image.tar $$1"; \
			continue; \
		fi; \
		BUILD_CMD="apptainer build"; \
		if [ "$(REPLACE)" = "replace-existing" ]; then \
			BUILD_CMD="$$BUILD_CMD --force"; \
		fi; \
		if ! eval $$BUILD_CMD apptainer/$$2.sif docker-archive:apptainer/$$2_image.tar; then \
			echo "ERROR: Failed to build $$2.sif"; \
			echo "To retry this step manually, run:"; \
			echo "  $$BUILD_CMD apptainer/$$2.sif docker-archive:apptainer/$$2_image.tar"; \
			continue; \
		fi; \
		rm apptainer/$$2_image.tar; \
		echo "Successfully processed $$1"; \
	done

export-and-build-local: ENV=local
export-and-build-local: export-and-build

# Clean Docker and Singularity caches
.PHONY: clean-cache
clean-cache:
	@echo "Cleaning Docker and Apptainer caches..."
	@echo "Cleaning Docker system..."
	@timeout 120 docker system prune -f || echo "WARNING: Docker system prune timed out after 2 minutes"
	@timeout 60 docker image prune -f || echo "WARNING: Docker image prune timed out after 1 minute"
	@echo "Removing dangling Docker images..."
	@timeout 30 sh -c 'docker images -f "dangling=true" -q | xargs -r docker rmi' || echo "WARNING: Dangling image cleanup timed out"
	@echo "Cleaning Apptainer cache..."
	@if command -v apptainer >/dev/null 2>&1; then \
		timeout 30 apptainer cache clean -f || echo "WARNING: Failed to clean Apptainer cache"; \
	elif command -v singularity >/dev/null 2>&1; then \
		timeout 30 singularity cache clean -f || echo "WARNING: Failed to clean Singularity cache"; \
	else \
		echo "Neither Apptainer nor Singularity found, skipping container cache cleanup"; \
	fi
	@echo "Cache cleanup complete."

# Help target
.PHONY: help
help:
	@echo "Available targets (add -local suffix for development environment):"
	@echo "  build              - Build Docker containers"
	@echo "  export             - Export containers to Singularity"
	@echo ""
	@echo "Examples:"
	@echo "  make build         - Build containers with production configuration"
	@echo "  make build-local   - Build containers with local development configuration"
