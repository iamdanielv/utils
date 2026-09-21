# Visuals
C_RESET   := \033[0m
C_GREEN   := \033[32m
C_RED     := \033[31m
C_CYAN    := \033[36m

.DEFAULT_GOAL := help

##@ General

.PHONY: help dev-setup dev-setup-verify logs-start logs-stop logs-view logs-open logs-clean logs-debug logs-restart

help: ##@ Show this help message
	@awk 'BEGIN {FS = ":.*?##@ "} /^[a-zA-Z_-]+:.*?##@ / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)}' $(MAKEFILE_LIST)

##@ Dev Setup

dev-setup: ##@ run Dev Machine Setup script
	@bash dev-setup/setup-dev-machine.sh

dev-setup-verify: ##@ run Dev Machine Setup verification suite
	@bash dev-setup/tests/test-setup-verify.sh

##@ Observability (observability/Makefile)

logs-start: ##@ start the docker log viewer stack
	@./observability/docker/dv-docker-log-viewer.sh start

logs-stop: ##@ stop the docker log viewer stack
	@./observability/docker/dv-docker-log-viewer.sh stop

logs-view: ##@ open the log viewer UI
	@xdg-open http://localhost:3000 2>/dev/null || printf '%s\n' 'Open http://localhost:3000 in your browser.'

logs-open: ##@ open Grafana in the default browser
	@xdg-open http://localhost:3000 2>/dev/null || printf '%s\n' 'Open http://localhost:3000 in your browser.'

logs-clean: ##@ stop and remove log stack data
	@./observability/docker/dv-docker-log-viewer.sh clean

logs-debug: ##@ inspect the docker log stack health
	@./observability/docker/dv-docker-log-viewer.sh debug

logs-restart: ##@ restart the docker log viewer stack
	@$(MAKE) logs-stop
	@$(MAKE) logs-start
