# Makefile for Centurion

BINARY_NAME := centurion
BUILD_DIR := bin

.DEFAULT_GOAL := help

# Visuals
C_RESET   := \033[0m
C_GREEN   := \033[32m
C_RED     := \033[31m
C_CYAN    := \033[36m

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
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Formatting code..."
	@output=$$(go fmt ./... 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$(C_GREEN)[✓]$(C_RESET)"; \
	else \
		echo "$(C_RED)[✗]$(C_RESET)"; \
		printf "\n$(C_RED)An error occurred:$(C_RESET)\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: vet
vet: ##@ Run go vet
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Vetting code..."
	@output=$$(go vet ./... 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$(C_GREEN)[✓]$(C_RESET)"; \
	else \
		echo "$(C_RED)[✗]$(C_RESET)"; \
		printf "\n$(C_RED)An error occurred:$(C_RESET)\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: tidy
tidy: ##@ Run go mod tidy
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Tidying modules..."
	@output=$$(go mod tidy 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$(C_GREEN)[✓]$(C_RESET)"; \
	else \
		echo "$(C_RED)[✗]$(C_RESET)"; \
		printf "\n$(C_RED)An error occurred:$(C_RESET)\n%s\n" "$$output"; \
		exit 1; \
	fi

##@ Build

.PHONY: build
build: tidy fmt vet ##@ Build the binary
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@output=$$(go build -o $(BUILD_DIR)/$(BINARY_NAME) . 2>&1); \
	if [ $$? -eq 0 ]; then \
		echo "$(C_GREEN)[✓]$(C_RESET)"; \
	else \
		echo "$(C_RED)[✗]$(C_RESET)"; \
		printf "\n$(C_RED)An error occurred:$(C_RESET)\n%s\n" "$$output"; \
		exit 1; \
	fi

.PHONY: clean
clean: ##@ Clean build artifacts
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Cleaning..."
	@rm -rf $(BUILD_DIR)
	@echo "$(C_GREEN)[✓]$(C_RESET)"

# Docker helpers
DOCKER_IMAGE := centurion:dev

.PHONY: docker-image
docker-image:
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Building docker image..."
	@docker build -t $(DOCKER_IMAGE) . > /dev/null && echo "$(C_GREEN)[✓]$(C_RESET)" || (echo "$(C_RED)[✗]$(C_RESET)" && exit 1)

.PHONY: docker-build
docker-build: docker-image ##@ Docker: build the binary using a container
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Extracting binary from image..."
	@mkdir -p $(BUILD_DIR)
	@container=$$(docker create $(DOCKER_IMAGE)); \
	docker cp $$container:/centurion $(BUILD_DIR)/$(BINARY_NAME); \
	docker rm $$container > /dev/null; \
	chmod +x $(BUILD_DIR)/$(BINARY_NAME); \
	echo "$(C_GREEN)[✓]$(C_RESET)"

.PHONY: docker-clean
docker-clean: ##@ Docker: remove local image
	@printf "$(C_CYAN)  %-30s$(C_RESET)" "Removing docker image..."
	@docker rmi -f $(DOCKER_IMAGE) > /dev/null 2>&1 || true
	@echo "$(C_GREEN)[✓]$(C_RESET)"
