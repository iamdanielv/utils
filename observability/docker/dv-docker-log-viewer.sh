#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
TEST_COMPOSE_FILE="${SCRIPT_DIR}/docker-compose-test.yml"
ACTION="${1:-help}"

usage() {
    cat <<'EOF'
Usage: dv-docker-log-viewer.sh [start|stop|status|logs|clean|debug|help]

Manage the repository's on-demand Docker log aggregation stack.

Commands:
  start    Start Loki + Promtail + Grafana
  stop     Stop and remove the main stack
  status   Show current stack status
  logs     Tail the aggregated logs from the stack
  clean    Stop and remove the main stack, any test compose stack, and all local volumes
  debug    Print a quick validation summary for Loki, Promtail, and project-scoped logs
  help     Show this message

Access:
  Grafana: http://localhost:3000
  Loki:    http://localhost:3100

Default Grafana login:
  user: admin
  pass: admin
EOF
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is required but not installed." >&2
        exit 1
    fi
}

cleanup_compose_file() {
    local compose_path="$1"
    if [[ -f "$compose_path" ]]; then
        echo "Cleaning compose stack: $compose_path"
        docker compose -f "$compose_path" down -v --remove-orphans || true
    fi
}

run_debug_checks() {
    echo '--- stack status ---'
    docker compose -f "$COMPOSE_FILE" ps || true

    if [[ -f "$TEST_COMPOSE_FILE" ]]; then
        echo '--- test stack status ---'
        docker compose -f "$TEST_COMPOSE_FILE" ps || true
    fi

    echo '--- promtail logs ---'
    docker compose -f "$COMPOSE_FILE" logs --tail=80 promtail || true

    echo '--- loki labels ---'
    curl -fsS http://localhost:3100/loki/api/v1/labels || true

    echo '--- docker logs query ---'
    curl -fsS -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={job="docker"}' || true

    echo '--- system logs query ---'
    curl -fsS -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={job="varlogs"}' || true

    if [[ -f "$TEST_COMPOSE_FILE" ]]; then
        echo '--- sample compose project query ---'
        curl -fsS -G 'http://localhost:3100/loki/api/v1/query' --data-urlencode 'query={compose_project="sample-stack"}' || true
    fi
}

case "$ACTION" in
    start)
        require_docker
        docker compose -f "$COMPOSE_FILE" up -d
        echo "Docker log stack started. Open http://localhost:3000"
        ;;
    stop)
        require_docker
        docker compose -f "$COMPOSE_FILE" down
        echo "Docker log stack stopped."
        ;;
    status)
        require_docker
        docker compose -f "$COMPOSE_FILE" ps
        ;;
    logs)
        require_docker
        docker compose -f "$COMPOSE_FILE" logs -f --tail=100
        ;;
    help|-h|--help)
        usage
        ;;
    clean)
        require_docker
        cleanup_compose_file "$COMPOSE_FILE"
        cleanup_compose_file "$TEST_COMPOSE_FILE"
        docker volume rm -f docker_loki_data docker_grafana_data 2>/dev/null || true
        echo "Docker log stack cleaned up."
        ;;
    debug)
        require_docker
        run_debug_checks
        ;;
    *)
        echo "Error: Invalid action '$ACTION'. Usage:" >&2
        usage >&2
        exit 1
        ;;
 esac
