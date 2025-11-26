.PHONY: all up down build load test clean logs ps

# Dynamically determine the project name from the current directory's name.
PROJECT_NAME := $(shell basename $(CURDIR))
# Export variables to be available in the shell commands executed by make.
.EXPORT_ALL_VARIABLES:

# Default target
all: up

# Start the Docker Compose services in detached mode, building the autoscaler image
up:
	@echo "Starting Docker Compose services for ${PROJECT_NAME}..."
	docker compose -p ${PROJECT_NAME} up -d --build --scale webapp=1
	@echo "Services started. Webapp available at http://localhost:8080"
	@echo "Monitor autoscaler logs with: make logs"
	@echo "Monitor webapp instances with: make ps"

# Stop and remove the Docker Compose services
down:
	@echo "Stopping Docker Compose services..."
	docker compose -p ${PROJECT_NAME} down

# Build the autoscaler image (useful for quick rebuilds without starting everything)
build:
	@echo "Building autoscaler image..."
	docker compose -p ${PROJECT_NAME} build autoscaler

# Generate load on the webapp service
load:
	@echo "Generating load on http://localhost:8080..."
	./hey -n 100000 -c 50 "http://localhost:8080"
	@echo "Load generation complete."

# Follow the logs for the autoscaler service
logs:
	@echo "Following logs for the 'autoscaler' service... (Press Ctrl+C to stop)"
	@docker compose -p ${PROJECT_NAME} logs -f autoscaler

# Show live resource usage for webapp containers
stats:
	@echo "Showing live resource usage for all project containers... (Press Ctrl+C to stop)"
	@watch --color "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \$$(docker ps --filter 'label=com.docker.compose.project=${PROJECT_NAME}' -q)"

# List the running webapp container instances
ps:
	@echo "Listing running webapp container instances..."
	@docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --filter "label=com.docker.compose.service=webapp" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Run a full test cycle: up, load, then down
test: up load down

# Clean up stopped containers and dangling images (optional, but good practice)
clean:
	@echo "Cleaning up stopped containers and dangling images..."
	@docker system prune -f