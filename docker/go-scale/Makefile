.DEFAULT_GOAL := help

# Get the directory name to use as the project name
PROJECT_NAME := $(shell basename "$(CURDIR)")
.EXPORT_ALL_VARIABLES: # Export PROJECT_NAME to sub-processes

# --- ANSI Color Codes ---
GREEN  := \033[1;32m
YELLOW := \033[1;33m
RED    := \033[1;31m
BLUE   := \033[1;34m
CYAN   := \033[1;36m
RESET  := \033[0m

OK_ICON  := $(GREEN)[✓]$(RESET)
ERR_ICON := $(RED)[✗]$(RESET)

##@ General
.PHONY: help
help: ##@ Show this help message
	@awk 'BEGIN {FS = ":.*?##@ "} /^[a-zA-Z_-]+:.*?##@ / {printf "  \033[1;36m%-20s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Development
.PHONY: build container test tidy
build: ##@ Build the Go binary for the local system
	@echo "$(YELLOW)Building$(RESET) 'go-autoscale' binary..."
	@$(MAKE) --no-print-directory tidy
	@echo -n " $(YELLOW)Compiling$(RESET) 'go-autoscale'... "
	@if output=$$(go build -o go-autoscale . 2>&1); then \
		echo "$(OK_ICON)"; \
	else \
		echo "$(ERR_ICON)"; \
		echo "$$output" | sed 's/^/    /g'; \
		exit 1; \
	fi

container: ##@ Build the Docker container image for the autoscaler
	@echo "$(YELLOW)Building$(RESET) Docker container image for 'autoscaler'..."
	@docker compose build --no-cache autoscaler

test: ##@ Run Go unit tests
	@echo "$(YELLOW)Running$(RESET) Go tests..."
	@go test ./...

tidy: ##@ Tidy Go module dependencies
	@echo -n " Checking and tidying $(BLUE)Go modules$(RESET)... "
	@if output=$$(go mod tidy 2>&1); then \
		echo "$(OK_ICON)"; \
	else \
		echo "$(ERR_ICON)"; \
		echo "$$output" | sed 's/^/    /g'; \
		exit 1; \
	fi

##@ Docker Lifecycle
.PHONY: up down clean
compose-up: ##@ Start services, building images if necessary
	@echo "$(YELLOW)Starting$(RESET) Docker services for project: $(CYAN)${PROJECT_NAME}$(RESET)..."
	@docker compose -p ${PROJECT_NAME} up -d --build --remove-orphans
	@echo "Services $(GREEN)started$(RESET). Web service available at $(CYAN)http://localhost:8080$(RESET)"

compose-down: ##@ Stop and remove services
	@echo "$(YELLOW)Stopping$(RESET) Docker services for project: $(CYAN)${PROJECT_NAME}$(RESET)..."
	@docker compose -p ${PROJECT_NAME} down -v --remove-orphans

compose-clean: ##@ Stop services and remove images, volumes, and build artifacts
	@echo "$(YELLOW)Cleaning$(RESET) project: $(CYAN)${PROJECT_NAME}$(RESET)..."
	@docker compose -p ${PROJECT_NAME} down -v --remove-orphans --rmi local
	@rm -f go-autoscale

##@ Interaction & Testing
.PHONY: logs ps stats load
logs: ##@ Follow the logs for the 'autoscaler' service
	@echo "$(YELLOW)Following logs$(RESET) for the 'autoscaler' service... (Press Ctrl+C to stop)"
	@docker compose -p ${PROJECT_NAME} logs -f autoscaler

ps: ##@ List the running 'web' container instances
	@echo "$(YELLOW)Listing$(RESET) 'webapp' container instances for project: $(CYAN)${PROJECT_NAME}$(RESET)..."
	@docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "label=com.docker.compose.service=webapp" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

stats: ##@ Show live resource usage for project containers
	@echo "$(YELLOW)Showing$(RESET) live resource usage for project containers... (Press Ctrl+C to stop)"
	@watch --color "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \$$(docker ps --filter 'label=com.docker.compose.project=${PROJECT_NAME}' -q)"

load: ##@ Generate HTTP load on the web service (requires 'hey')
	@echo "$(YELLOW)Generating$(RESET) high CPU load on $(CYAN)http://localhost:8080$(RESET)..."
	@hey -n 100000 -c 100 "http://localhost:8080"
	@echo "Load generation $(GREEN)complete$(RESET)."
