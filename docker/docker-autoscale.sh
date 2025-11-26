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
SCALE_DOWN_CHECKS=2             # Number of consecutive checks before scaling down.
POLL_INTERVAL=15                # Seconds between each metric check
LOG_HEARTBEAT_INTERVAL=30       # Log a status message even if nothing changes, after this many seconds.

# --- State Variables ---
LAST_SCALE_EVENT_TS=0
LAST_SCALE_DIRECTION="none" # 'up' or 'down'
CONSECUTIVE_SCALE_DOWN_CHECKS=0
# For verbose logging control
LAST_LOG_TS=0
LAST_LOGGED_REPLICAS=-1
LAST_LOGGED_CPU=-1
LAST_LOGGED_MEM=-1

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
  --scale-down-checks <num> Number of consecutive checks before scaling down. (Default: $SCALE_DOWN_CHECKS)
  --heartbeat <sec>     Interval in seconds to log a heartbeat status. (Default: $LOG_HEARTBEAT_INTERVAL)
  --poll <sec>          Interval in seconds to check metrics. (Default: $POLL_INTERVAL)
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
        --scale-down-checks) SCALE_DOWN_CHECKS="$2"; shift ;;
        --heartbeat) LOG_HEARTBEAT_INTERVAL="$2"; shift ;;
        --poll) POLL_INTERVAL="$2"; shift ;;
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
    local message="[$(date '+%m-%d %H:%M:%S')] - $1"
    echo "$message"
}

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


for var in MIN_REPLICAS MAX_REPLICAS CPU_UPPER_THRESHOLD CPU_LOWER_THRESHOLD MEM_UPPER_THRESHOLD MEM_LOWER_THRESHOLD SCALE_UP_COOLDOWN SCALE_DOWN_COOLDOWN POLL_INTERVAL SCALE_DOWN_CHECKS LOG_HEARTBEAT_INTERVAL; do
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

get_avg_stats() {
    local container_ids
    container_ids=$(docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}")

    if [ -z "$container_ids" ]; then
        echo "0 0" # Return CPU 0, Mem 0
        return
    fi

    # Run docker stats once to get both CPU and Mem, preventing race conditions.
    # The output format is "CPUPerc MemPerc" for each container, separated by newlines.
    local stats_output
    stats_output=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemPerc}}" $container_ids 2>/dev/null || echo "")

    if [ -z "$stats_output" ]; then
        log_msg "Warning: Failed to get stats for service '$SERVICE_NAME'. Assuming 0% usage."
        echo "0 0"
        return
    fi

    # Use awk to calculate the average of both columns at once.
    # It sums the first column (CPU) and second column (Mem), then divides by the number of lines (NR).
    echo "$stats_output" | sed 's/%//g' | grep . | awk '{ cpu_total += $1; mem_total += $2 } END { if (NR > 0) printf "%.0f %.0f", cpu_total/NR, mem_total/NR; else print "0 0" }'
}

get_current_replicas() {
    docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}" | wc -l
}

get_avg_cpu_usage() {
    local container_ids
    container_ids=$(docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}")
    # Deprecated in favor of get_avg_stats, but kept for potential single-metric logic if ever needed.
    get_avg_stats | awk '{print $1}'
}

get_avg_mem_usage() {
    local container_ids
    container_ids=$(docker ps -q --filter "label=com.docker.compose.service=${SERVICE_NAME}")
    
    get_avg_stats | awk '{print $2}'
}

scale_service() {
    local new_replicas="$1"
    local direction="$2"
    local attempt=1
    local max_attempts=3
    local retry_delay=5 # seconds

    local current_replicas
    current_replicas=$(get_current_replicas)
    if [[ "$current_replicas" -eq "$new_replicas" ]]; then
        return 0 # Already at the desired state
    fi

    log_msg "Scaling $SERVICE_NAME $direction to $new_replicas replicas..."

    while [ "$attempt" -le "$max_attempts" ]; do
        log_msg "Attempt ($attempt/$max_attempts) to scale $SERVICE_NAME $direction to $new_replicas replicas..."
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
if [[ "$SCALE_METRIC" == "cpu" || "$SCALE_METRIC" == "mem" ]]; then
    metric_name=$(echo "$SCALE_METRIC" | tr '[:lower:]' '[:upper:]')
    log_msg "Configuration: Metric=$metric_name Min=$MIN_REPLICAS Max=$MAX_REPLICAS Up-Threshold=$CPU_UPPER_THRESHOLD% Down-Threshold=$CPU_LOWER_THRESHOLD% Down-Checks=$SCALE_DOWN_CHECKS Poll=${POLL_INTERVAL}s Heartbeat=${LOG_HEARTBEAT_INTERVAL}s"
else # any
    log_msg "Configuration: Metric=Any(CPU or Mem) Min=$MIN_REPLICAS Max=$MAX_REPLICAS CPU-Up=$CPU_UPPER_THRESHOLD% Mem-Up=$MEM_UPPER_THRESHOLD% CPU-Down=$CPU_LOWER_THRESHOLD% Mem-Down=$MEM_LOWER_THRESHOLD% Down-Checks=$SCALE_DOWN_CHECKS Poll=${POLL_INTERVAL}s Heartbeat=${LOG_HEARTBEAT_INTERVAL}s"
fi

while true; do
    current_replicas=$(get_current_replicas)

    # --- Cooldown Check ---
    now=$(date +%s)
    elapsed_since_last_scale=$((now - LAST_SCALE_EVENT_TS))

    cooldown_period=0
    if [[ "$LAST_SCALE_DIRECTION" == "up" ]]; then
        cooldown_period=$SCALE_UP_COOLDOWN
    elif [[ "$LAST_SCALE_DIRECTION" == "down" ]]; then
        cooldown_period=$SCALE_DOWN_COOLDOWN
    fi

    if (( cooldown_period > 0 && elapsed_since_last_scale < cooldown_period )); then
        remaining_cooldown=$((cooldown_period - elapsed_since_last_scale))
        if (( (now - LAST_LOG_TS) >= 10 )); then
            log_msg "Scale-${LAST_SCALE_DIRECTION} cooldown active (${remaining_cooldown}s left). Waiting..."
            LAST_LOG_TS=$now
        fi
        # Sleep for the remainder of the cooldown or the poll interval, whichever is shorter.
        sleep_duration=$(( remaining_cooldown < POLL_INTERVAL ? remaining_cooldown : POLL_INTERVAL ))
        sleep "$sleep_duration"
        continue # Re-evaluate after waiting
    fi

    # --- Scaling Logic ---
    # Fetch stats once for efficiency
    read -r avg_cpu avg_mem < <(get_avg_stats)

    # Determine if a scale-up or scale-down is needed based on the chosen metric.
    should_scale_up=false
    should_scale_down=false
    scale_reason=""

    if [[ "$SCALE_METRIC" == "cpu" || "$SCALE_METRIC" == "any" ]]; then
        if (( avg_cpu > CPU_UPPER_THRESHOLD )); then should_scale_up=true; scale_reason="CPU ($avg_cpu% > $CPU_UPPER_THRESHOLD%)"; fi
        if (( avg_cpu < CPU_LOWER_THRESHOLD )); then should_scale_down=true; fi
    fi

    if [[ "$SCALE_METRIC" == "mem" || "$SCALE_METRIC" == "any" ]]; then
        if (( avg_mem > MEM_UPPER_THRESHOLD )); then
            should_scale_up=true
            if [[ -n "$scale_reason" ]]; then scale_reason+=" and "; fi
            scale_reason+="Memory ($avg_mem% > $MEM_UPPER_THRESHOLD%)"
        fi
        if (( avg_mem < MEM_LOWER_THRESHOLD )); then should_scale_down=true; else should_scale_down=false; fi
    fi

    # Log status only if it changed or if the heartbeat interval has passed
    if (( current_replicas != LAST_LOGGED_REPLICAS || avg_cpu != LAST_LOGGED_CPU || avg_mem != LAST_LOGGED_MEM || (now - LAST_LOG_TS) >= LOG_HEARTBEAT_INTERVAL )); then
        log_message=""
        if [[ "$SCALE_METRIC" == "any" ]]; then
            log_message="$SERVICE_NAME: Replicas=$current_replicas, AvgCPU=${avg_cpu}%, AvgMem=${avg_mem}%"
            if ! (( avg_cpu < CPU_LOWER_THRESHOLD && avg_mem < MEM_LOWER_THRESHOLD )); then
                should_scale_down=false
            fi
        elif [[ "$SCALE_METRIC" == "cpu" ]]; then
            log_message="$SERVICE_NAME: Replicas=$current_replicas, AvgCPU=${avg_cpu}%"
        elif [[ "$SCALE_METRIC" == "mem" ]]; then
            log_message="$SERVICE_NAME: Replicas=$current_replicas, AvgMem=${avg_mem}%"
        fi
        log_msg "$log_message"
        LAST_LOG_TS=$now
        LAST_LOGGED_REPLICAS=$current_replicas
        LAST_LOGGED_CPU=$avg_cpu
        LAST_LOGGED_MEM=$avg_mem
    fi

    if $should_scale_up && (( current_replicas < MAX_REPLICAS )); then
        log_msg "Scale up triggered by: $scale_reason. Scaling up."
        scale_service $((current_replicas + 1)) "up"
        CONSECUTIVE_SCALE_DOWN_CHECKS=0 # Reset counter on any scale up
    elif $should_scale_down && (( current_replicas > MIN_REPLICAS )); then
        CONSECUTIVE_SCALE_DOWN_CHECKS=$((CONSECUTIVE_SCALE_DOWN_CHECKS + 1))
        log_msg "Scale down condition met ($CONSECUTIVE_SCALE_DOWN_CHECKS/$SCALE_DOWN_CHECKS)."
        if (( CONSECUTIVE_SCALE_DOWN_CHECKS >= SCALE_DOWN_CHECKS )); then
            log_msg "Scaling down: threshold met for $CONSECUTIVE_SCALE_DOWN_CHECKS consecutive checks."
            scale_service $((current_replicas - 1)) "down"
            CONSECUTIVE_SCALE_DOWN_CHECKS=0 # Reset counter after scaling
        fi
    else
        # If neither scale up nor scale down condition is met, reset the down-check counter.
        CONSECUTIVE_SCALE_DOWN_CHECKS=0
    fi

    sleep "$POLL_INTERVAL"
done
