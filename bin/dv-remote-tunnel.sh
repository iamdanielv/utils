#!/bin/bash
# ===============
# Script Name: dv-remote-tunnel.sh
# Description: Reverse-tunnels local internet to remote machine via SSH
#              for system updates, interactive shells, or commands.
# Keybinding:  None
# Config:      N/A
# Dependencies: ssh, ss, nc (optional, if proxy detected)
# ===============

set -o pipefail

#region Library Functions

#region Colors and Styles
export C_RED=$'\033[31m'
export C_GREEN=$'\033[32m'
export C_YELLOW=$'\033[33m'
export C_BLUE=$'\033[34m'
export C_MAGENTA=$'\033[35m'
export C_CYAN=$'\033[36m'
export C_WHITE=$'\033[37m'
export C_GRAY=$'\033[38;5;244m'
export C_L_RED=$'\033[31;1m'
export C_L_GREEN=$'\033[32m'
export C_L_YELLOW=$'\033[33m'
export C_L_BLUE=$'\033[34m'
export C_L_MAGENTA=$'\033[35m'
export C_L_CYAN=$'\033[36m'
export C_L_WHITE=$'\033[37;1m'

export T_RESET=$'\033[0m'
export T_BOLD=$'\033[1m'

export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"
export T_QST_ICON="[${T_BOLD}${C_L_CYAN}?${T_RESET}]"

export DIV="──────────────────────────────────────────────────────────"
#endregion Colors and Styles


#region Logging
printMsg() { printf '%b\n' "$1"; }
printMsgNoNewline() { printf '%b' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_L_RED} ${1} ${T_RESET}" >&2; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }
#endregion Logging

#endregion Library Functions

# --- HELP & USAGE ---
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <remote_user> <remote_host>
       $(basename "$0") [OPTIONS] <remote_user@remote_host>

Description:
  Reverse-tunnels local internet connectivity to a remote system via SSH SOCKS5.
  By default, opens an interactive remote shell with proxy environment variables configured.

Options:
  -u, --update           Execute automated OS package upgrades through the tunnel and exit.
  -c, --command <CMD>    Execute a specific command on the remote system through the tunnel.
  -k, --keep-alive       Hold the tunnel open in foreground without launching an interactive shell.
  -s, --shell            Open an interactive remote shell (default behavior).
  -d, --dry-run          Validate connectivity and tunnel configuration without running session.
  -p, --port <PORT>      Specify remote SSH port (default: 22).
  -i, --identity <KEY>   Specify SSH private key file path.
  -h, --help             Display this help menu and exit (code 0).

Examples:
  $(basename "$0") admin 192.168.1.50
  $(basename "$0") root@isolated-host
  $(basename "$0") -u admin@server.internal
  $(basename "$0") -k -p 2222 root@10.0.0.5
  $(basename "$0") -c "git clone https://github.com/org/repo.git" admin@isolated-host
EOF
    exit 0
}

show_usage_error() {
    local err_msg="$1"
    cat << EOF >&2
Usage: $(basename "$0") [OPTIONS] <remote_user> <remote_host>
       $(basename "$0") [OPTIONS] <remote_user@remote_host>

EOF
    printErrMsg "$err_msg"
    printMsg "${C_GRAY}Run '$(basename "$0") --help' for full options and examples.${T_RESET}" >&2
    exit 1
}

# --- CLI ARGUMENT PARSING ---
DRY_RUN=false
EXEC_MODE="shell"
COMMAND_PAYLOAD=""
SSH_PORT=""
SSH_IDENTITY=""
REMOTE_USER=""
REMOTE_HOST=""
POSITIONAL_ARGS=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -u|--update)
            EXEC_MODE="update"
            shift
            ;;
        -s|--shell)
            EXEC_MODE="shell"
            shift
            ;;
        -k|--keep-alive|--hold)
            EXEC_MODE="keep-alive"
            shift
            ;;
        -c|--command)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                show_usage_error "Option '$1' requires a non-empty command argument."
            fi
            EXEC_MODE="command"
            COMMAND_PAYLOAD="$2"
            shift 2
            ;;
        -p|--port)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                show_usage_error "Option '$1' requires a port argument."
            fi
            SSH_PORT="$2"
            shift 2
            ;;
        -i|--identity)
            if [[ -z "${2:-}" || "$2" == -* ]]; then
                show_usage_error "Option '$1' requires an identity file path."
            fi
            SSH_IDENTITY="$2"
            shift 2
            ;;
        -*)
            show_usage_error "Unknown option: $1"
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Positional arguments: user@host or user host
if [ "${#POSITIONAL_ARGS[@]}" -eq 1 ]; then
    if [[ "${POSITIONAL_ARGS[0]}" == *"@"* ]]; then
        REMOTE_USER="${POSITIONAL_ARGS[0]%%@*}"
        REMOTE_HOST="${POSITIONAL_ARGS[0]#*@}"
    else
        show_usage_error "Single positional target must be in format 'user@host'."
    fi
elif [ "${#POSITIONAL_ARGS[@]}" -eq 2 ]; then
    REMOTE_USER="${POSITIONAL_ARGS[0]}"
    REMOTE_HOST="${POSITIONAL_ARGS[1]}"
else
    show_usage_error "Missing required target arguments (<remote_user> <remote_host> or <user@host>)."
fi

if [[ -z "$REMOTE_USER" || -z "$REMOTE_HOST" ]]; then
    show_usage_error "Remote user and host cannot be empty."
fi

# --- LOGGING SETUP ---
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/remote_tunnel_${REMOTE_HOST}_${TIMESTAMP}.log"


exec > >(tee -i "$LOG_FILE") 2>&1

printMsg "${C_GRAY}${DIV}${T_RESET}"
printMsg "${T_BOLD}START TIME:${T_RESET}  $(date)"
printMsg "${T_BOLD}TARGET:${T_RESET}      ${REMOTE_USER}@${REMOTE_HOST}"
if [ -n "$SSH_PORT" ]; then
    printMsg "${T_BOLD}PORT:${T_RESET}        ${SSH_PORT}"
fi
printMsg "${T_BOLD}MODE:${T_RESET}        ${EXEC_MODE^^}$( [ "$DRY_RUN" = true ] && echo " (Dry Run)" || echo "" )"
printMsg "${T_BOLD}LOG FILE:${T_RESET}    ${LOG_FILE}"
printMsg "${C_GRAY}${DIV}${T_RESET}"


START_SECONDS=$SECONDS

# 1. Detect Local Network Profile & Validate Dependencies
PROXY_URL=${http_proxy:-$HTTP_PROXY}
SSH_EXTRA_ARGS=()

if [ -n "$PROXY_URL" ]; then
    printInfoMsg "[LOCAL] Network Profile: PROXY ENVIRONMENT DETECTED"
    
    if ! command -v nc &> /dev/null; then
        printErrMsg "[LOCAL] 'nc' (netcat) is required to tunnel through local proxy."
        printMsg "       Run: sudo apt install netcat-openbsd" >&2
        exit 1
    fi
    
    CLEAN_URL=$(echo "$PROXY_URL" | sed -e 's,^http://,,g' -e 's,^https://,,g')
    PROXY_HOST=$(echo "$CLEAN_URL" | cut -d: -f1)
    PROXY_PORT=$(echo "$CLEAN_URL" | cut -d: -f2)
    printInfoMsg "[LOCAL] Routing SSH via HTTP Proxy: ${PROXY_HOST}:${PROXY_PORT}"
    SSH_EXTRA_ARGS+=("-o" "ProxyCommand=nc -X connect -x ${PROXY_HOST}:${PROXY_PORT} %h %p")
else
    printInfoMsg "[LOCAL] Network Profile: DIRECT INTERNET DETECTED"
fi

# 2. Find a random open port locally
printInfoMsg "[LOCAL] Finding open dynamic port..."
while true; do
    TUNNEL_PORT=$((RANDOM % 16383 + 49152))
    if ! ss -tuln | grep -q ":${TUNNEL_PORT} "; then
        break
    fi
done
printOkMsg "[LOCAL] Selected ephemeral port: ${TUNNEL_PORT}"

# 3. Assemble SSH Arguments
SSH_BASE_ARGS=(
    "-D" "localhost:${TUNNEL_PORT}"
    "-R" "${TUNNEL_PORT}:localhost:${TUNNEL_PORT}"
    "-o" "ExitOnForwardFailure=yes"
    "-o" "ServerAliveInterval=15"
    "-o" "ServerAliveCountMax=3"
    "-o" "ConnectTimeout=10"
    "-o" "ControlMaster=no"
    "-o" "StrictHostKeyChecking=accept-new"
    "-t"
)

if [ -n "$SSH_PORT" ]; then
    SSH_BASE_ARGS+=("-p" "$SSH_PORT")
fi

if [ -n "$SSH_IDENTITY" ]; then
    SSH_BASE_ARGS+=("-i" "$SSH_IDENTITY")
fi

if [ ${#SSH_EXTRA_ARGS[@]} -gt 0 ]; then
    SSH_BASE_ARGS+=("${SSH_EXTRA_ARGS[@]}")
fi

printInfoMsg "[LOCAL] Injecting payload and spawning reverse tunnel..."

# --- REMOTE SCRIPT PAYLOAD (ENCODED FOR SAFE PTY EXECUTION) ---
REMOTE_PAYLOAD_B64=$(base64 -w 0 << 'EOF'
#!/bin/bash
set -o pipefail

# ANSI Colors and Icons (matched to repo standards)
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'
C_GRAY=$'\033[38;5;244m'
T_RESET=$'\033[0m'
T_BOLD=$'\033[1m'

T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"
T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
T_WARN_ICON="[${T_BOLD}${C_YELLOW}!${T_RESET}]"

printMsg() { printf '%b\n' "$1"; }
printErrMsg() { printMsg "${T_ERR_ICON}${T_BOLD}${C_RED} ${1} ${T_RESET}" >&2; }
printOkMsg() { printMsg "${T_OK_ICON} ${1}${T_RESET}"; }
printInfoMsg() { printMsg "${T_INFO_ICON} ${1}${T_RESET}"; }
printWarnMsg() { printMsg "${T_WARN_ICON} ${1}${T_RESET}"; }

# Detect Operating System
OS="unknown"
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "$ID" =~ (ubuntu|debian|pop|mint|raspbian) ]]; then
        OS="ubuntu"
    elif [[ "$ID" =~ (rhel|centos|amzn|fedora|rocky|alma) ]]; then
        OS="rhel"
    fi
fi

printInfoMsg "[REMOTE] Detected system layout: ${OS}"

# Setup environment variables for proxy
export http_proxy="socks5h://127.0.0.1:${TUNNEL_PORT}"
export https_proxy="socks5h://127.0.0.1:${TUNNEL_PORT}"
export HTTP_PROXY="socks5h://127.0.0.1:${TUNNEL_PORT}"
export HTTPS_PROXY="socks5h://127.0.0.1:${TUNNEL_PORT}"
export ALL_PROXY="socks5h://127.0.0.1:${TUNNEL_PORT}"
export all_proxy="socks5h://127.0.0.1:${TUNNEL_PORT}"

test_connectivity() {
    local target="https://example.com"
    if command -v curl &>/dev/null; then
        curl --connect-timeout 5 -s "$target" > /dev/null 2>&1
        return $?
    elif command -v wget &>/dev/null; then
        https_proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" http_proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" wget -q --timeout=5 --spider "$target" > /dev/null 2>&1
        return $?
    elif command -v nc &>/dev/null; then
        nc -z -w 3 127.0.0.1 "$TUNNEL_PORT" > /dev/null 2>&1
        return $?
    else
        (exec 3<>/dev/tcp/127.0.0.1/"${TUNNEL_PORT}") 2>/dev/null
        return $?
    fi
}

printInfoMsg "[REMOTE] Testing internet connectivity through proxy tunnel (port ${TUNNEL_PORT})..."

if ! test_connectivity; then
    printErrMsg "[REMOTE] Network loop failed. Reverse proxy stream timed out."
    exit 1
fi

printOkMsg "[REMOTE] Tunnel validation successful!"

if [ "$DRY_RUN" = "true" ]; then
    printInfoMsg "[REMOTE] [DRY RUN] Connection verified. Skipping operations as requested."
    exit 0
fi

case "$EXEC_MODE" in
    shell)
        printInfoMsg "[REMOTE] Launching interactive shell with proxy enabled..."
        printMsg ""
        printMsg "${C_GRAY}────────────────────────────────────────────────────────────${T_RESET}"
        printMsg " ${T_BOLD}${C_GREEN}REMOTE SESSION ACTIVE:${T_RESET} ${T_BOLD}${C_CYAN}$(whoami)@$(hostname)${T_RESET}"
        printMsg " ${C_GRAY}Proxy Tunnel: 127.0.0.1:${TUNNEL_PORT} (http/https/all_proxy active)${T_RESET}"
        printMsg " ${C_YELLOW}Type 'exit' or press Ctrl+D to return to local machine.${T_RESET}"
        printMsg "${C_GRAY}────────────────────────────────────────────────────────────${T_RESET}"
        exec bash -i
        ;;

    keep-alive)
        printInfoMsg "[REMOTE] Tunnel active on port ${TUNNEL_PORT}."
        printMsg "       ${C_GRAY}(http_proxy, https_proxy, ALL_PROXY active)${T_RESET}"
        printMsg "       ${C_GRAY}Holding connection open. Press Ctrl+C locally to stop.${T_RESET}"
        while true; do sleep 3600; done
        ;;
    command)
        printInfoMsg "[REMOTE] Executing custom command..."
        eval "$COMMAND_PAYLOAD"
        exit $?
        ;;
    update)
        printInfoMsg "[REMOTE] Launching update cycle..."
        SUDO_CMD=""
        if [ "$(id -u)" -ne 0 ]; then
            if ! command -v sudo &>/dev/null; then
                printErrMsg "[REMOTE] 'sudo' is required to perform package updates as non-root user."
                exit 1
            fi
            SUDO_CMD="sudo"
        fi

        if [ "$OS" = "ubuntu" ]; then
            export DEBIAN_FRONTEND=noninteractive
            $SUDO_CMD apt-get -o Acquire::http::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" -o Acquire::https::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" update
            
            UPGRADES=$($SUDO_CMD apt-get -s -o Acquire::http::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" -o Acquire::https::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" dist-upgrade 2>/dev/null | grep -E '^Inst' | wc -l)
            printInfoMsg "[REMOTE] Found ${UPGRADES} packages queued for installation."
            
            $SUDO_CMD apt-get -o Acquire::http::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" -o Acquire::https::Proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" -o Dpkg::Options::="--force-confold" dist-upgrade -y
        elif [ "$OS" = "rhel" ]; then
            YUM_OUT=$($SUDO_CMD yum --setopt=proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" check-update -q 2>/dev/null || true)
            UPGRADES=$(echo "$YUM_OUT" | grep -v '^$' | wc -l)
            printInfoMsg "[REMOTE] Found ${UPGRADES} packages queued for installation."
            
            $SUDO_CMD yum --setopt=proxy="socks5h://127.0.0.1:${TUNNEL_PORT}" update -y
        else
            printErrMsg "[REMOTE] Operating system '$OS' not supported for automated updates."
            exit 1
        fi
        printOkMsg "[REMOTE] Package upgrades completed successfully."
        ;;
    *)
        printErrMsg "[REMOTE] Unknown execution mode: $EXEC_MODE"
        exit 1
        ;;
esac
EOF
)

# 4. Execute Remote Command via SSH PTY (Preserving target user session)
REMOTE_BOOTSTRAP="TMP_SCRIPT=\$(mktemp /tmp/dv_remote_XXXXXX.sh); echo '$REMOTE_PAYLOAD_B64' | base64 -d > \"\$TMP_SCRIPT\"; chmod +x \"\$TMP_SCRIPT\"; DRY_RUN='$DRY_RUN' TUNNEL_PORT='$TUNNEL_PORT' EXEC_MODE='$EXEC_MODE' COMMAND_PAYLOAD=$(printf '%q' "$COMMAND_PAYLOAD") \"\$TMP_SCRIPT\"; EXIT_CODE=\$?; rm -f \"\$TMP_SCRIPT\"; exit \$EXIT_CODE"

ssh "${SSH_BASE_ARGS[@]}" \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "bash -c $(printf '%q' "$REMOTE_BOOTSTRAP")"


# 5. Analytics & Timers
SSH_EXIT_CODE=$?
DURATION=$((SECONDS - START_SECONDS))

MIN=$((DURATION / 60))
SEC=$((DURATION % 60))

printMsg "=========================================================="
if [ $SSH_EXIT_CODE -eq 0 ] || [ $SSH_EXIT_CODE -eq 130 ]; then
    if [ "$DRY_RUN" = true ]; then
        printOkMsg "DRY RUN SUCCESS: Tunnel and remote connection verified."
    elif [ "$EXEC_MODE" = "shell" ]; then
        printOkMsg "SESSION CLOSED: Remote shell session terminated."
    elif [ "$EXEC_MODE" = "keep-alive" ]; then
        printOkMsg "TUNNEL CLOSED: Keep-alive session terminated."
    elif [ "$EXEC_MODE" = "command" ]; then
        printOkMsg "COMMAND SUCCESS: Remote command completed successfully."
    else
        printOkMsg "SUCCESS: Target system updated cleanly."
    fi
else
    printErrMsg "FAILURE: Remote connection dropped or exited with error code ${SSH_EXIT_CODE}"
fi

printMsg "⏱️  ELAPSED TIME: ${MIN}m ${SEC}s"
printMsg "END TIME:     $(date)"
printMsg "=========================================================="

exit $SSH_EXIT_CODE

