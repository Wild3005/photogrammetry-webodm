#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================================
# NodeODM Auto Runner
# ============================================================================

NODE_HOST="${NODE_HOST:-0.0.0.0}"
NODE_PORT="${NODE_PORT:-3000}"
NODE_URL="http://${NODE_HOST}:${NODE_PORT}"

ODM_OPTIONS='[
  {"name":"feature-quality","value":"high"},
  {"name":"min-num-features","value":16000},
  {"name":"matcher-type","value":"flann"},
  {"name":"mesh-octree-depth","value":11},
  {"name":"mesh-size","value":200000},
  {"name":"use-3dmesh","value":true},
  {"name":"pc-quality","value":"medium"},
  {"name":"ignore-gsd","value":true},
  {"name":"bg-removal","value":true}
]'

# ============================================================================
# Colors
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

TASK_UUID=""
START_TIME=""

spinner_chars='|/-\'

# ============================================================================
# Logging
# ============================================================================

log_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERR]${NC} $*" >&2
}

# ============================================================================
# Utils
# ============================================================================

fmt_time() {
    local s=$1

    if (( s >= 3600 )); then
        printf "%02d:%02d:%02d" \
            $((s / 3600)) \
            $(((s % 3600) / 60)) \
            $((s % 60))
    else
        printf "%02d:%02d" \
            $((s / 60)) \
            $((s % 60))
    fi
}

draw_progress_bar() {
    local progress=$1
    local width=30

    (( progress > 100 )) && progress=100
    (( progress < 0 )) && progress=0

    local filled=$(( progress * width / 100 ))
    local empty=$(( width - filled ))

    printf "${GREEN}"

    for ((i=0; i<filled; i++)); do
        printf "█"
    done

    printf "${DIM}"

    for ((i=0; i<empty; i++)); do
        printf "░"
    done

    printf "${NC}"
}

cleanup() {
    echo

    if [[ -n "${TASK_UUID}" ]]; then
        log_warn "Interrupted. Canceling task on NodeODM..."
        curl -fsS -X POST "${NODE_URL}/task/cancel" -d "uuid=${TASK_UUID}" > /dev/null 2>&1 || true
        log_warn "Task canceled."
    fi

    exit 130
}

trap cleanup INT TERM

# ============================================================================
# Checks
# ============================================================================

check_dependencies() {
    local missing=()

    for cmd in curl jq unzip find stat; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_err "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    log_ok "Dependencies OK"
}

check_node_connection() {
    local info
    log_err "DEBUG: Memeriksa NODE_URL -> '${NODE_URL}'"
    if ! info=$(curl -fsS "${NODE_URL}/info"); then
        log_err "Cannot connect to NodeODM at ${NODE_URL}"
        exit 1
    fi

    local version
    version=$(jq -r '.version // "unknown"' <<< "$info")

    local engine
    engine=$(jq -r '.engineVersion // "unknown"' <<< "$info")

    log_ok "Connected to NodeODM v${version} (${engine})"
}

# ============================================================================
# Image Scan
# ============================================================================

scan_images() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_err "Directory not found: $dir"
        exit 1
    fi

    mapfile -d '' IMAGES < <(
        find "$dir" \
            -maxdepth 1 \
            -type f \
            \( \
                -iname "*.jpg" -o \
                -iname "*.jpeg" -o \
                -iname "*.png" -o \
                -iname "*.tif" -o \
                -iname "*.tiff" \
            \) \
            -print0 | LC_ALL=C sort -z
    )

    IMAGE_COUNT=${#IMAGES[@]}

    if (( IMAGE_COUNT < 5 )); then
        log_err "Need at least 5 images"
        exit 1
    fi

    log_ok "Found ${IMAGE_COUNT} images"
}

# ============================================================================
# Submit
# ============================================================================

submit_task() {
    local task_name="$1"

    log_info "Submitting task..."

    local form_args=()

    for img in "${IMAGES[@]}"; do
        form_args+=(-F "images=@${img}")
    done

    form_args+=(-F "name=${task_name}")
    form_args+=(-F "options=${ODM_OPTIONS}")

    local response

    response=$(
        curl -fsS \
            -X POST \
            "${form_args[@]}" \
            "${NODE_URL}/task/new"
    )

    TASK_UUID=$(jq -r '.uuid // empty' <<< "$response")

    if [[ -z "${TASK_UUID}" ]]; then
        log_err "Failed to parse UUID"
        echo "$response"
        exit 1
    fi

    echo "${TASK_UUID}" > .last_task_uuid

    log_ok "Task submitted"
    log_info "UUID: ${TASK_UUID}"
}

# ============================================================================
# Monitor
# ============================================================================

monitor_task() {
    START_TIME=$(date +%s)

    local spinner_idx=0

    while true; do

        local info
        info=$(curl -fsS "${NODE_URL}/task/${TASK_UUID}/info" 2>/dev/null || echo '{}')

        local status_code
        status_code=$(jq -r '.status.code // 0' <<< "$info")

        local progress
        progress=$(jq -r '.progress // 0' <<< "$info")

        progress=${progress%.*}

        local elapsed
        elapsed=$(( $(date +%s) - START_TIME ))

        local elapsed_str
        elapsed_str=$(fmt_time "$elapsed")

        local spin_char="${spinner_chars:$spinner_idx:1}"
        spinner_idx=$(( (spinner_idx + 1) % ${#spinner_chars} ))

        local status_text="UNKNOWN"
        local status_color="$NC"

        case "$status_code" in
            10)
                status_text="QUEUED"
                status_color="$YELLOW"
                ;;
            20)
                status_text="RUNNING"
                status_color="$BLUE"
                ;;
            30)
                status_text="FAILED"
                status_color="$RED"
                ;;
            40)
                status_text="COMPLETED"
                status_color="$GREEN"
                ;;
            50)
                status_text="CANCELED"
                status_color="$YELLOW"
                ;;
        esac

        printf "\r%s %b%s%b " \
            "$spin_char" \
            "$status_color" \
            "$status_text" \
            "$NC"

        draw_progress_bar "$progress"

        printf " %3d%% elapsed:%s" \
            "$progress" \
            "$elapsed_str"

        case "$status_code" in
            40)
                echo
                log_ok "Task completed"
                return 0
                ;;
            30)
                echo

                local err
                err=$(jq -r '.status.errorMessage // "Unknown error"' <<< "$info")

                log_err "Task failed: ${err}"
                return 1
                ;;
            50)
                echo
                log_warn "Task canceled"
                return 1
                ;;
        esac

        sleep 1
    done
}

# ============================================================================
# Download
# ============================================================================

download_results() {
    local output_dir="$1"

    mkdir -p "$output_dir"

    local zip_path="${output_dir}/all.zip"

    log_info "Downloading results..."

    curl -fLo "$zip_path" \
        "${NODE_URL}/task/${TASK_UUID}/download/all.zip"

    unzip -qo "$zip_path" -d "$output_dir"

    rm -f "$zip_path"

    log_ok "Results downloaded"
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Usage:
  $(basename "$0") <input_dir> [output_dir]

  $(basename "$0") --resume <uuid> [output_dir]
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {

    if (( $# == 0 )); then
        usage
        exit 1
    fi

    check_dependencies
    check_node_connection

    case "${1}" in

        --help|-h)
            usage
            ;;

        --resume)

            TASK_UUID="${2:-}"

            if [[ -z "${TASK_UUID}" ]]; then
                log_err "UUID required"
                exit 1
            fi

            local output_dir="${3:-./output_${TASK_UUID:0:8}}"

            monitor_task
            download_results "$output_dir"
            ;;

        *)

            local input_dir="$1"
            local output_dir="${2:-./output/output_$(date +%Y%m%d_%H%M%S)}"

            scan_images "$input_dir"

            local task_name
            task_name="task_$(basename "$input_dir")"

            submit_task "$task_name"

            monitor_task

            download_results "$output_dir"
            ;;
    esac
}

main "$@"