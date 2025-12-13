# Makefile for the 'schedule' example

.DEFAULT_GOAL := help

PROJECT_NAME := $(shell basename $(CURDIR))
.EXPORT_ALL_VARIABLES: # Export PROJECT_NAME to sub-processes

##@ General
.PHONY: help
help: ##@ Show this help message
	@echo "Usage: make <target>"
	@echo ""
	@awk 'BEGIN {FS = ":.*?##@ "} /^[a-zA-Z_-]+:.*?##@ / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Docker Lifecycle
.PHONY: compose-up compose-down compose-build compose-clean
compose-up: ##@ Start services via 'compose up', building the scheduler image
	@echo "Starting Docker Compose services for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml up -d --build --remove-orphans
	@echo "Services started. The 'task-runner' will be executed on its schedule."
	@echo "Monitor scheduler logs with: make schedule-logs"

compose-down: ##@ Stop and remove services via 'compose down'
	@echo "Stopping Docker Compose services for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml down

compose-build: ##@ Build the scheduler image via 'compose build'
	@echo "Building scheduler image for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml build scheduler

compose-clean: ##@ Stop services and clean up the system
	@$(MAKE) compose-down
	@echo "Cleaning up stopped containers and dangling images..."
	@docker system prune -f

##@ Interaction
.PHONY: logs ps stats
logs: ##@ Follow the logs for the 'scheduler' service
	@echo "Following logs for the 'scheduler' service... (Press Ctrl+C to stop)"
	@docker compose -p ${PROJECT_NAME} -f docker-compose.yml logs -f scheduler

ps: ##@ List the running container instances
	@echo "Listing running container instances..."
	@docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.State}}"

stats: ##@ Show live resource usage for project containers
	@echo "Showing live resource usage for project containers... (Press Ctrl+C to stop)"
	@watch --color "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \$$(docker ps --filter 'label=com.docker.compose.project=${PROJECT_NAME}' -q)"
