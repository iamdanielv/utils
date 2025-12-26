# Makefile for Centurion

BINARY_NAME := centurion
BUILD_DIR := bin

.DEFAULT_GOAL := help

##@ General

.PHONY: help
help: ##@ Show this help message
	@awk 'BEGIN {FS = ":.*?##@ "} /^[a-zA-Z_-]+:.*?##@ / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Development

.PHONY: run
run: ##@ Run the application
#   @echo "  \033[32mRunning $(BINARY_NAME)...\033[0m"
	@go run .

.PHONY: fmt
fmt: ##@ Format Go source code
	@printf "  %-30s" "Formatting code..."
	@output=$$(go fmt ./... 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "\033[32m[✓]\033[0m"; \
	else \
		echo "\033[31m[✗]\033[0m"; \
		printf "\n\033[31mAn error occurred:\033[0m\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: vet
vet: ##@ Run go vet
	@printf "  %-30s" "Vetting code..."
	@output=$$(go vet ./... 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "\033[32m[✓]\033[0m"; \
	else \
		echo "\033[31m[✗]\033[0m"; \
		printf "\n\033[31mAn error occurred:\033[0m\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: tidy
tidy: ##@ Run go mod tidy
	@printf "  %-30s" "Tidying modules..."
	@output=$$(go mod tidy 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "\033[32m[✓]\033[0m"; \
	else \
		echo "\033[31m[✗]\033[0m"; \
		printf "\n\033[31mAn error occurred:\033[0m\n%s\n" "$$output"; \
		exit 1; \
	fi

##@ Build

.PHONY: build
build: tidy fmt vet ##@ Build the binary
	@printf "  %-30s" "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@output=$$(go build -o $(BUILD_DIR)/$(BINARY_NAME) . 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "\033[32m[✓]\033[0m"; \
	else \
		echo "\033[31m[✗]\033[0m"; \
		printf "\n\033[31mAn error occurred:\033[0m\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: clean
clean: ##@ Clean build artifacts
	@printf "  %-30s" "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@echo "\033[32m[✓]\033[0m"

# Docker helpers
DOCKER_IMAGE := centurion:dev

.PHONY: docker-image
docker-image:
	@printf "  %-30s" "Building docker image..."
	@docker build -t $(DOCKER_IMAGE) . > /dev/null && echo "\033[32m[✓]\033[0m" || (echo "\033[31m[✗]\033[0m" && exit 1)

.PHONY: docker-build
docker-build: docker-image ##@ Docker: build the binary using a container
	@printf "  %-30s" "Extracting binary from image..."
	@mkdir -p $(BUILD_DIR)
	@container=$$(docker create $(DOCKER_IMAGE)); \
	docker cp $$container:/centurion $(BUILD_DIR)/$(BINARY_NAME); \
	docker rm $$container > /dev/null; \
	chmod +x $(BUILD_DIR)/$(BINARY_NAME); \
	echo "\033[32m[✓]\033[0m"

.PHONY: docker-clean
docker-clean: ##@ Docker: remove local image
	docker rmi -f $(DOCKER_IMAGE) || true
