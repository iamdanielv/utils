#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VIEWER_SCRIPT="$SCRIPT_DIR/../bin/dv-docker-networks.sh"
IMAGE="busybox:latest"
RESOURCE_PREFIX="net-test"
POPULATED_NETWORK="${RESOURCE_PREFIX}-populated"
EMPTY_NETWORK="${RESOURCE_PREFIX}-empty"
RUNNING_CONTAINER="${RESOURCE_PREFIX}-cont-running"
PAUSED_CONTAINER="${RESOURCE_PREFIX}-cont-paused"

POPULATED_NETWORK_CREATED=false
EMPTY_NETWORK_CREATED=false
RUNNING_CONTAINER_CREATED=false
PAUSED_CONTAINER_CREATED=false

cleanup() {
    local exit_status=$?
    local cleanup_failed=false

    trap - EXIT
    printf '\nCleaning up Docker network test fixtures...\n'

    if [[ "$RUNNING_CONTAINER_CREATED" == true ]] && ! docker rm -f "$RUNNING_CONTAINER" >/dev/null; then
        printf 'Error: failed to remove container %s\n' "$RUNNING_CONTAINER" >&2
        cleanup_failed=true
    fi
    if [[ "$PAUSED_CONTAINER_CREATED" == true ]] && ! docker rm -f "$PAUSED_CONTAINER" >/dev/null; then
        printf 'Error: failed to remove container %s\n' "$PAUSED_CONTAINER" >&2
        cleanup_failed=true
    fi
    if [[ "$POPULATED_NETWORK_CREATED" == true ]] && ! docker network rm "$POPULATED_NETWORK" >/dev/null; then
        printf 'Error: failed to remove network %s\n' "$POPULATED_NETWORK" >&2
        cleanup_failed=true
    fi
    if [[ "$EMPTY_NETWORK_CREATED" == true ]] && ! docker network rm "$EMPTY_NETWORK" >/dev/null; then
        printf 'Error: failed to remove network %s\n' "$EMPTY_NETWORK" >&2
        cleanup_failed=true
    fi

    if [[ "$cleanup_failed" == true ]]; then
        printf 'Error: Docker network test cleanup did not complete successfully.\n' >&2
        exit_status=1
    else
        printf 'Docker network test fixtures cleaned up.\n'
    fi

    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if ! command -v docker >/dev/null 2>&1; then
    printf 'Error: Docker command not found; install Docker and ensure it is in PATH.\n' >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'Error: jq command not found; install jq before running this test.\n' >&2
    exit 1
fi

if ! docker info >/dev/null; then
    printf 'Error: Docker daemon is not available; start Docker and check your access.\n' >&2
    exit 1
fi

if [[ ! -f "$VIEWER_SCRIPT" ]]; then
    printf 'Error: Docker network viewer not found at %s\n' "$VIEWER_SCRIPT" >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull "$IMAGE"
fi

docker network create "$POPULATED_NETWORK" >/dev/null
POPULATED_NETWORK_CREATED=true
docker network create "$EMPTY_NETWORK" >/dev/null
EMPTY_NETWORK_CREATED=true

docker create \
    --network "$POPULATED_NETWORK" \
    --name "$RUNNING_CONTAINER" \
    "$IMAGE" sleep 3600 >/dev/null
RUNNING_CONTAINER_CREATED=true
docker start "$RUNNING_CONTAINER" >/dev/null

docker create \
    --network "$POPULATED_NETWORK" \
    --name "$PAUSED_CONTAINER" \
    "$IMAGE" sleep 3600 >/dev/null
PAUSED_CONTAINER_CREATED=true
docker start "$PAUSED_CONTAINER" >/dev/null
docker pause "$PAUSED_CONTAINER" >/dev/null

printf '\nCreated test fixtures:\n'
printf '  Populated network: %s\n' "$POPULATED_NETWORK"
printf '  Empty network:     %s\n' "$EMPTY_NETWORK"
printf '  Running container: %s\n' "$RUNNING_CONTAINER"
printf '  Paused container:  %s\n' "$PAUSED_CONTAINER"
printf '\n--- Docker network viewer output (all daemon networks) ---\n'

bash "$VIEWER_SCRIPT"
