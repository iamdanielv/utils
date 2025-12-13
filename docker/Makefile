# Makefile for Docker Examples

.DEFAULT_GOAL := help

##@ General
.PHONY: help
help: ##@ Show this help message
	@awk 'BEGIN {FS = ":.*?##@ "} /^[a-zA-Z_-]+:.*?##@ / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Scale Example
.PHONY: scale-compose-up scale-compose-down scale-compose-build scale-compose-clean scale-logs scale-stats scale-ps scale-load scale-test
scale-compose-up: ##@ Start the scale example services via 'compose up'
	@$(MAKE) --no-print-directory -C scale up
scale-compose-down: ##@ Stop the scale example services via 'compose down'
	@$(MAKE) --no-print-directory -C scale down
scale-compose-build: ##@ Build the autoscaler image via 'compose build'
	@$(MAKE) --no-print-directory -C scale build
scale-compose-clean: ##@ Stop services and clean up the system
	@$(MAKE) --no-print-directory -C scale clean
scale-logs: ##@ Follow logs for the autoscaler
	@$(MAKE) --no-print-directory -C scale logs
scale-stats: ##@ Show live resource usage for containers
	@$(MAKE) --no-print-directory -C scale stats
scale-ps: ##@ List running webapp containers
	@$(MAKE) --no-print-directory -C scale ps
scale-load: ##@ Generate HTTP load on the webapp
	@$(MAKE) --no-print-directory -C scale load
scale-test: ##@ Run a full test cycle (up, load, down)
	@$(MAKE) scale-compose-up scale-load scale-compose-down

##@ Schedule Example
.PHONY: schedule-compose-up schedule-compose-down schedule-compose-build schedule-compose-clean schedule-logs schedule-stats schedule-ps
schedule-compose-up: ##@ Start the schedule example services via 'compose up'
	@$(MAKE) --no-print-directory -C schedule compose-up
schedule-compose-down: ##@ Stop the schedule example services via 'compose down'
	@$(MAKE) --no-print-directory -C schedule compose-down
schedule-compose-build: ##@ Build the scheduler image via 'compose build'
	@$(MAKE) --no-print-directory -C schedule compose-build
schedule-compose-clean: ##@ Stop services and clean up the system
	@$(MAKE) --no-print-directory -C schedule compose-clean
schedule-logs: ##@ Follow logs for the scheduler
	@$(MAKE) --no-print-directory -C schedule logs
schedule-stats: ##@ Show live resource usage for containers
	@$(MAKE) --no-print-directory -C schedule stats
schedule-ps: ##@ List running containers
	@$(MAKE) --no-print-directory -C schedule ps
