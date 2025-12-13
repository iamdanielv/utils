# Makefile for the 'scale' example

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
compose-up: ##@ Start services via 'compose up', building the autoscaler image
	@echo "Starting Docker Compose services for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml up -d --build --remove-orphans --scale webapp=1
	@echo "Services started. Webapp available at http://localhost:8080"
	@echo "Monitor autoscaler logs with: make scale-logs"
	@echo "Monitor webapp instances with: make scale-ps"

compose-down: ##@ Stop and remove services via 'compose down'
	@echo "Stopping Docker Compose services for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml down

compose-build: ##@ Build the autoscaler image via 'compose build'
	@echo "Building autoscaler image for project: ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} -f docker-compose.yml build autoscaler

compose-clean: ##@ Stop services and clean up the system
	@$(MAKE) compose-down
	@echo "Cleaning up stopped containers and dangling images..."
	@docker system prune -f

##@ Interaction & Testing
.PHONY: load test logs ps stats
load: ##@ Generate HTTP load on the webapp service
	@echo "Generating load on http://localhost:8080..."
	hey -n 100000 -c 50 "http://localhost:8080"
	@echo "Load generation complete."

logs: ##@ Follow the logs for the 'autoscaler' service
	@echo "Following logs for the 'autoscaler' service... (Press Ctrl+C to stop)"
	@docker compose -p ${PROJECT_NAME} -f docker-compose.yml logs -f autoscaler

stats: ##@ Show live resource usage for project containers
	@echo "Showing live resource usage for project containers... (Press Ctrl+C to stop)"
	@watch --color "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \$$(docker ps --filter 'label=com.docker.compose.project=${PROJECT_NAME}' -q)"

ps: ##@ List the running webapp container instances
	@echo "Listing running webapp container instances..."
	@docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "label=com.docker.compose.service=webapp" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"
