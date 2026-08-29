#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ACTION="${1:-help}"

usage() {
    cat <<'EOF'
Usage: dv-docker-log-viewer.sh [start|stop|status|logs|help]

Manage the repository's on-demand Docker log aggregation stack.

Commands:
  start    Start Loki + Promtail + Grafana
  stop     Stop and remove the stack
  status   Show current stack status
  logs     Tail the aggregated logs from the stack
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
    *)
        echo "Unknown action: $ACTION" >&2
        usage >&2
        exit 1
        ;;
 esac
