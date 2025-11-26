#!/bin/bash
set -o pipefail

# --- Default Configuration ---
SERVICE_NAME=""                 # The service to scale (required)
MIN_REPLICAS=1                  # Minimum number of containers
MAX_REPLICAS=5                  # Maximum number of containers
SCALE_METRIC="cpu"              # Metric to scale on: 'cpu', 'mem', or 'any'
CPU_UPPER_THRESHOLD=70          # Scale up when CPU usage is above this percentage
CPU_LOWER_THRESHOLD=20          # Scale down when CPU usage is below this percentage
MEM_UPPER_THRESHOLD=80          # Scale up when Memory usage is above this percentage
MEM_LOWER_THRESHOLD=30          # Scale down when Memory usage is below this percentage
SCALE_UP_COOLDOWN=20            # Seconds to wait after scaling up before scaling again
SCALE_DOWN_COOLDOWN=20          # Seconds to wait after scaling down before scaling again
POLL_INTERVAL=15                # Seconds between each metric check
LOG_FILE="/tmp/docker-autoscale.log" # Log file location

# --- State Variables ---
LAST_SCALE_EVENT_TS=0
LAST_SCALE_DIRECTION="none" # 'up' or 'down'

print_usage() {
    cat <<EOF
Usage: $0 --service <service_name> [options]

A utility to watch and automatically scale a docker-compose service based on CPU usage.

Required:
  --service <name>      The name of the service in docker-compose.yml to scale.

Options:
  --min <num>           Minimum number of replicas. (Default: $MIN_REPLICAS)
  --max <num>           Maximum number of replicas. (Default: $MAX_REPLICAS)
  --cpu-up <%>          CPU percentage threshold to scale up. (Default: $CPU_UPPER_THRESHOLD)
  --cpu-down <%>        CPU percentage threshold to scale down. (Default: $CPU_LOWER_THRESHOLD)
  --metric <type>       Metric to scale on: 'cpu', 'mem', or 'any'. (Default: $SCALE_METRIC)
  --mem-up <%>          Memory percentage threshold to scale up. (Default: $MEM_UPPER_THRESHOLD)
  --mem-down <%>        Memory percentage threshold to scale down. (Default: $MEM_LOWER_THRESHOLD)
  --cooldown-up <sec>   Cooldown in seconds after scaling up. (Default: $SCALE_UP_COOLDOWN)
  --cooldown-down <sec> Cooldown in seconds after scaling down. (Default: $SCALE_DOWN_COOLDOWN)
  --poll <sec>          Interval in seconds to check metrics. (Default: $POLL_INTERVAL)
  --log-file <path>     Path to the log file. (Default: $LOG_FILE)
  -h, --help            Show this help message.
EOF
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --service) SERVICE_NAME="$2"; shift ;;
        --min) MIN_REPLICAS="$2"; shift ;;
        --max) MAX_REPLICAS="$2"; shift ;;
        --cpu-up) CPU_UPPER_THRESHOLD="$2"; shift ;;
        --cpu-down) CPU_LOWER_THRESHOLD="$2"; shift ;;
        --metric) SCALE_METRIC="$2"; shift ;;
        --mem-up) MEM_UPPER_THRESHOLD="$2"; shift ;;
        --mem-down) MEM_LOWER_THRESHOLD="$2"; shift ;;
        --cooldown-up) SCALE_UP_COOLDOWN="$2"; shift ;;
        --cooldown-down) SCALE_DOWN_COOLDOWN="$2"; shift ;;
        --poll) POLL_INTERVAL="$2"; shift ;;
        --log-file) LOG_FILE="$2"; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; print_usage; exit 1 ;;
    esac
    shift
done

# --- Validation and Setup ---
if [ -z "$SERVICE_NAME" ]; then
    echo "Error: --service is a required argument." >&2
    print_usage
    exit 1
fi

if [[ "$SCALE_METRIC" != "cpu" && "$SCALE_METRIC" != "mem" && "$SCALE_METRIC" != "any" ]]; then
    echo "Error: Invalid value for --metric. Must be 'cpu', 'mem', or 'any'." >&2
    print_usage
    exit 1
fi

# --- Helper Functions ---
log_msg() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
    echo "$message"
    # Log to file only after LOG_FILE is confirmed, to avoid errors on startup
    if [ -w "$(dirname "$LOG_FILE")" ] && [ -f "$LOG_FILE" ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

touch "$LOG_FILE" 2>/dev/null || { log_msg "Warning: Cannot write to log file $LOG_FILE. Continuing with stdout logging only."; }

# --- Dependency Check & Setup ---
COMPOSE_CMD=""
if command -v "docker" &> /dev/null && docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
    log_msg "Using 'docker compose' (v2)"
elif command -v "docker-compose" &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    log_msg "Using 'docker-compose' (v1)"
else
    log_msg "Error: Neither 'docker compose' (v2) nor 'docker-compose' (v1) could be found."
    exit 1
fi

# The compose command is handled above. We just need to check for the other dependencies.
for cmd in docker bc; do
    if ! command -v "$cmd" &> /dev/null; then
        log_msg "Error: Required command '$cmd' not found. Please install it."
        exit 1
    fi
done

# Check if the provided service name actually exists in the docker-compose file
if ! $COMPOSE_CMD config --services | grep -q "^${SERVICE_NAME}$"; then
    log_msg "Error: Service '$SERVICE_NAME' not found in docker-compose.yml."
    log_msg "Available services are:"
    # Indent the service list for readability
    $COMPOSE_CMD config --services | sed 's/^/  /'
    exit 1
fi


for var in MIN_REPLICAS MAX_REPLICAS CPU_UPPER_THRESHOLD CPU_LOWER_THRESHOLD MEM_UPPER_THRESHOLD MEM_LOWER_THRESHOLD SCALE_UP_COOLDOWN SCALE_DOWN_COOLDOWN POLL_INTERVAL; do
    if ! [[ "${!var}" =~ ^[0-9]+$ ]]; then
        log_msg "Error: Value for '$var' is not a valid integer: '${!var}'"
        exit 1
    fi
done

cleanup() {
    log_msg "Shutdown signal received. Exiting auto-scaler."
    exit 0
}

trap cleanup SIGINT SIGTERM

get_current_replicas() {
    docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}" | wc -l
}

get_avg_cpu_usage() {
    local container_ids
    container_ids=$(docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}")

    if [ -z "$container_ids" ]; then
        echo 0
        return
    fi

    # Run docker stats in a subshell to prevent script exit on error (e.g., container disappears)
    local stats_output
    stats_output=$(docker stats --no-stream --format "{{.CPUPerc}}" $container_ids 2>/dev/null || echo "")

    if [ -z "$stats_output" ]; then
        log_msg "Warning: Failed to get stats for service '$SERVICE_NAME'. Assuming 0% CPU."
        echo 0
        return
    fi

    local total_cpu
    total_cpu=$(echo "$stats_output" | sed 's/%//' | paste -sd+ - | LC_NUMERIC=C bc)
    local replica_count
    replica_count=$(echo "$stats_output" | wc -l)

    # Use awk for floating point division
    awk -v total="$total_cpu" -v count="$replica_count" 'BEGIN {if (count > 0) printf "%.0f", total/count; else print 0}'
}

get_avg_mem_usage() {
    local container_ids
    container_ids=$(docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}")

    if [ -z "$container_ids" ]; then
        echo 0
        return
    fi

    # Run docker stats in a subshell to prevent script exit on error (e.g., container disappears)
    local stats_output
    stats_output=$(docker stats --no-stream --format "{{.MemPerc}}" $container_ids 2>/dev/null || echo "")

    if [ -z "$stats_output" ]; then
        log_msg "Warning: Failed to get stats for service '$SERVICE_NAME'. Assuming 0% Memory."
        echo 0
        return
    fi

    local total_mem
    total_mem=$(echo "$stats_output" | sed 's/%//' | paste -sd+ - | LC_NUMERIC=C bc)
    local replica_count
    replica_count=$(echo "$stats_output" | wc -l)

    # Use awk for floating point division
    awk -v total="$total_mem" -v count="$replica_count" 'BEGIN {if (count > 0) printf "%.0f", total/count; else print 0}'
}

scale_service() {
    local new_replicas="$1"
    local direction="$2"
    local attempt=1
    local max_attempts=3
    local retry_delay=5 # seconds

    log_msg "Scaling $SERVICE_NAME $direction to $new_replicas replicas..."

    while [ "$attempt" -le "$max_attempts" ]; do
        log_msg "Attempt $attempt to scale $SERVICE_NAME $direction to $new_replicas replicas..."
        local compose_output
        # Execute docker compose, capturing its stdout and stderr into a variable.
        # We use $COMPOSE_CMD which is already determined to be "docker compose" or "docker-compose". The `then` keyword is required here.
        # We capture the output and check the exit code ($?) separately to avoid syntax errors in some shells.
        compose_output=$($COMPOSE_CMD up -d --scale "$SERVICE_NAME=$new_replicas" --no-recreate 2>&1)
        if [ $? -ne 0 ]; then
            log_msg "Error (Attempt $attempt): Failed to scale $SERVICE_NAME."
            log_msg "Docker Compose output for attempt $attempt:\n$compose_output"

            if [ "$attempt" -lt "$max_attempts" ]; then
                log_msg "Retrying in $retry_delay seconds..."
                sleep "$retry_delay"
            fi
        else
            log_msg "Successfully scaled $SERVICE_NAME $direction to $new_replicas replicas."
            LAST_SCALE_EVENT_TS=$(date +%s)
            LAST_SCALE_DIRECTION="$direction"
            return 0 # Success
        fi
        attempt=$((attempt + 1))
    done

    log_msg "Error: Failed to scale $SERVICE_NAME after $max_attempts attempts."
    return 1 # Failure
}

# --- Main Loop ---
log_msg "Starting auto-scaler for service: '$SERVICE_NAME'"
if [[ "$SCALE_METRIC" == "cpu" ]]; then
    log_msg "Configuration: Metric=CPU Min=$MIN_REPLICAS Max=$MAX_REPLICAS Up-Threshold=$CPU_UPPER_THRESHOLD% Down-Threshold=$CPU_LOWER_THRESHOLD% Poll=$POLL_INTERVALs"
elif [[ "$SCALE_METRIC" == "mem" ]]; then
    log_msg "Configuration: Metric=Memory Min=$MIN_REPLICAS Max=$MAX_REPLICAS Up-Threshold=$MEM_UPPER_THRESHOLD% Down-Threshold=$MEM_LOWER_THRESHOLD% Poll=$POLL_INTERVALs"
else # any
    log_msg "Configuration: Metric=Any(CPU or Mem) Min=$MIN_REPLICAS Max=$MAX_REPLICAS CPU-Up=$CPU_UPPER_THRESHOLD% Mem-Up=$MEM_UPPER_THRESHOLD% CPU-Down=$CPU_LOWER_THRESHOLD% Mem-Down=$MEM_LOWER_THRESHOLD% Poll=$POLL_INTERVALs"
fi

while true; do
    current_replicas=$(get_current_replicas)
    
    # --- Metric Collection ---
    avg_metric=0
    upper_threshold=0
    lower_threshold=0

    # --- Cooldown Check ---
    # This check is moved before metric collection to avoid unnecessary `docker stats` calls during cooldown.
    now=$(date +%s)
    elapsed_since_last_scale=$((now - LAST_SCALE_EVENT_TS))

    # --- Cooldown Check ---
    if [[ "$LAST_SCALE_DIRECTION" == "up" && $elapsed_since_last_scale -lt $SCALE_UP_COOLDOWN ]]; then
        log_msg "++ scale-up cooldown ($((SCALE_UP_COOLDOWN - elapsed_since_last_scale))s left)"
        sleep "$POLL_INTERVAL"
        continue
    elif [[ "$LAST_SCALE_DIRECTION" == "down" && $elapsed_since_last_scale -lt $SCALE_DOWN_COOLDOWN ]]; then
        log_msg "-- scale-down cooldown ($((SCALE_DOWN_COOLDOWN - elapsed_since_last_scale))s left)"
        sleep "$POLL_INTERVAL"
        continue
    fi

    # --- Scaling Logic ---
    if [[ "$SCALE_METRIC" == "any" ]]; then
        avg_cpu=$(get_avg_cpu_usage)
        avg_mem=$(get_avg_mem_usage)
        log_msg "$SERVICE_NAME: Replicas=$current_replicas, AvgCPU=${avg_cpu}%, AvgMem=${avg_mem}%"

        # Scale up if EITHER metric is high
        if (( avg_cpu > CPU_UPPER_THRESHOLD || avg_mem > MEM_UPPER_THRESHOLD )) && (( current_replicas < MAX_REPLICAS )); then
            scale_up_reason=""
            if (( avg_cpu > CPU_UPPER_THRESHOLD )); then
                scale_up_reason+="CPU ($avg_cpu% > $CPU_UPPER_THRESHOLD%)"
            fi
            if (( avg_mem > MEM_UPPER_THRESHOLD )); then
                if [ -n "$scale_up_reason" ]; then
                    scale_up_reason+=" and "
                fi
                scale_up_reason+="Memory ($avg_mem% > $MEM_UPPER_THRESHOLD%)"
            fi
            log_msg "Scale up triggered by: $scale_up_reason. Scaling up."
            scale_service $((current_replicas + 1)) "up"
        # Scale down only if BOTH metrics are low
        elif (( avg_cpu < CPU_LOWER_THRESHOLD && avg_mem < MEM_LOWER_THRESHOLD )) && (( current_replicas > MIN_REPLICAS )); then
            log_msg "Both CPU ($avg_cpu% < $CPU_LOWER_THRESHOLD%) and Memory ($avg_mem% < $MEM_LOWER_THRESHOLD%) are below thresholds. Scaling down."
            scale_service $((current_replicas - 1)) "down"
        fi
    else # Single metric logic (cpu or mem)
        if [[ "$SCALE_METRIC" == "cpu" ]]; then
            avg_metric=$(get_avg_cpu_usage)
            upper_threshold=$CPU_UPPER_THRESHOLD
            lower_threshold=$CPU_LOWER_THRESHOLD
            log_msg "$SERVICE_NAME: Replicas=$current_replicas, AvgCPU=${avg_metric}%"
        else # mem
            avg_metric=$(get_avg_mem_usage)
            upper_threshold=$MEM_UPPER_THRESHOLD
            lower_threshold=$MEM_LOWER_THRESHOLD
            log_msg "$SERVICE_NAME: Replicas=$current_replicas, AvgMem=${avg_metric}%"
        fi

        if (( avg_metric > upper_threshold && current_replicas < MAX_REPLICAS )); then
            log_msg "Metric threshold breached ($avg_metric% > $upper_threshold%). Scaling up."
            scale_service $((current_replicas + 1)) "up"
        elif (( avg_metric < lower_threshold && current_replicas > MIN_REPLICAS )); then
            log_msg "Metric is below threshold ($avg_metric% < $lower_threshold%). Scaling down."
            scale_service $((current_replicas - 1)) "down"
        fi
    fi

    sleep "$POLL_INTERVAL"
done
