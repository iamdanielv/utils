.PHONY: help setup setup-verify logs-start logs-stop logs-view logs-open logs-clean logs-debug logs-restart clean

help:
	@printf '%s\n' ''
	@printf '%s\n' 'Available targets:'
	@printf '%s\n' '  make setup         - run the developer machine setup script'
	@printf '%s\n' '  make setup-verify  - run the setup verification suite'
	@printf '%s\n' '  make logs-start    - start the docker log viewer stack'
	@printf '%s\n' '  make logs-stop     - stop the docker log viewer stack'
	@printf '%s\n' '  make logs-restart  - restart the docker log viewer stack'
	@printf '%s\n' '  make logs-view     - open the log viewer UI'
	@printf '%s\n' '  make logs-open     - open Grafana in the default browser'
	@printf '%s\n' '  make logs-clean    - stop and remove log stack data'
	@printf '%s\n' '  make logs-debug    - inspect the docker log stack health'
	@printf '%s\n' ''
	@printf '%s\n' 'Observability defaults:'
	@printf '%s\n' '  Grafana URL: http://localhost:3000'
	@printf '%s\n' '  Grafana user: admin'
	@printf '%s\n' '  Grafana pass: admin'

setup:
	@bash dev-setup/setup-dev-machine.sh

setup-verify:
	@bash dev-setup/tests/test-setup-verify.sh

logs-start:
	@./observability/docker/dv-docker-log-viewer.sh start

logs-stop:
	@./observability/docker/dv-docker-log-viewer.sh stop

logs-view:
	@xdg-open http://localhost:3000 2>/dev/null || printf '%s\n' 'Open http://localhost:3000 in your browser.'

logs-open:
	@xdg-open http://localhost:3000 2>/dev/null || printf '%s\n' 'Open http://localhost:3000 in your browser.'

logs-clean:
	@./observability/docker/dv-docker-log-viewer.sh clean

logs-debug:
	@./observability/docker/dv-docker-log-viewer.sh debug

logs-restart: logs-stop logs-start

clean: logs-clean
