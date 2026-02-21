#!/bin/bash

# =============================================================================
# Ralph Search - Generic Iterative Research Loop Runner
# =============================================================================
# A generic CLI tool that runs Claude Code in a loop to perform iterative
# research. It is domain-agnostic: all domain knowledge lives in prompt.md
# inside the search folder.
#
# Subcommands:
#   run    <folder> [iterations] [--model sonnet|opus] [--timeout 20m]
#   status <folder>
#
# Requirements:
#   - Claude Code CLI installed and authenticated
#   - gtimeout (brew install coreutils)
#   - A search folder containing prompt.md
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

usage() {
    cat <<'USAGE'
Ralph Search - Generic Iterative Research Loop Runner

Usage:
  ralph_search.sh run <folder> [iterations] [--model sonnet|opus] [--timeout 20m]
  ralph_search.sh status <folder>
  ralph_search.sh dashboard <folder> [--port 8420]
  ralph_search.sh --help

Subcommands:
  run       Run the iterative research loop.
              <folder>       Path to a search folder containing prompt.md
              [iterations]   Number of iterations (default: 5, 0 = infinite)
              --model        Claude model to use: sonnet or opus (default: sonnet)
              --timeout      Timeout per session (default: 20m)

  status    Show current state of a search folder.
              <folder>       Path to the search folder

  dashboard Start the live web dashboard for monitoring.
              <folder>       Path to a search folder
              --port         Port to serve on (default: 8420)

Examples:
  ralph_search.sh run ./my_search
  ralph_search.sh run ./my_search 10 --model opus --timeout 30m
  ralph_search.sh run ./my_search 0
  ralph_search.sh status ./my_search
  ralph_search.sh dashboard ./my_search --port 8420
USAGE
}

# Detect the dossier subdirectory inside a search folder.
# Strategy: find the subdirectory (not logs/ or docs/) with the most .md files.
# This is the most likely dossier directory.
detect_dossier_dir() {
    local folder="$1"
    local best_dir=""
    local best_count=0

    for d in "$folder"/*/; do
        [ -d "$d" ] || continue
        local name
        name="$(basename "$d")"
        # Skip logs and docs directories
        [[ "$name" == "logs" || "$name" == "docs" ]] && continue

        # If a directory is named "dossiers", prefer it immediately
        if [[ "$name" == "dossiers" ]]; then
            best_dir="$d"
            break
        fi

        local count
        count=$(find "$d" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt "$best_count" ]]; then
            best_count=$count
            best_dir="$d"
        fi
    done

    # Fallback: if no directory has .md files, pick the first non-logs/non-docs dir
    if [[ -z "$best_dir" ]]; then
        for d in "$folder"/*/; do
            [ -d "$d" ] || continue
            local name
            name="$(basename "$d")"
            [[ "$name" == "logs" || "$name" == "docs" ]] && continue
            best_dir="$d"
            break
        done
    fi

    # Remove trailing slash for consistency
    echo "${best_dir%/}"
}

# Count .md files in the dossier directory
count_dossiers() {
    local dossier_dir="$1"
    if [[ -z "$dossier_dir" || ! -d "$dossier_dir" ]]; then
        echo "0"
        return
    fi
    local count
    count=$(find "$dossier_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "$count"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    local folder="$1"

    log_info "Checking prerequisites..."

    # Check if Claude CLI is installed
    if ! command -v claude &> /dev/null; then
        log_error "Claude Code CLI not found. Please install it first."
        log_error "Run: npm install -g @anthropic-ai/claude-code"
        exit 1
    fi

    # Check if gtimeout is installed
    if ! command -v gtimeout &> /dev/null; then
        log_error "gtimeout not found. Please install coreutils:"
        log_error "Run: brew install coreutils"
        exit 1
    fi

    # Check if folder exists
    if [[ ! -d "$folder" ]]; then
        log_error "Search folder not found: $folder"
        exit 1
    fi

    # Check if prompt.md exists
    if [[ ! -f "$folder/prompt.md" ]]; then
        log_error "prompt.md not found in: $folder"
        log_error "The search folder must contain a prompt.md file."
        exit 1
    fi

    # Ensure notes.md exists
    if [[ ! -f "$folder/notes.md" ]]; then
        log_warning "notes.md not found. Creating empty notes.md..."
        touch "$folder/notes.md"
    fi

    # Create logs directory
    mkdir -p "$folder/logs"

    # Detect and ensure dossier directory exists
    local dossier_dir
    dossier_dir="$(detect_dossier_dir "$folder")"
    if [[ -z "$dossier_dir" ]]; then
        log_warning "No dossier subdirectory found. Dossier counting will start at 0."
    else
        log_info "Dossier directory: $dossier_dir"
    fi

    log_success "All prerequisites met."
}

# =============================================================================
# Run Subcommand
# =============================================================================

run_iteration() {
    local folder="$1"
    local iteration="$2"
    local model="$3"
    local timeout="$4"

    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="$folder/logs/session_${timestamp}.log"
    local err_file="$folder/logs/session_${timestamp}.err"

    log_info "=========================================="
    log_info "Starting iteration $iteration"
    log_info "Log file: $log_file"
    log_info "=========================================="

    # Detect dossier dir and count before
    local dossier_dir
    dossier_dir="$(detect_dossier_dir "$folder")"
    local before_count
    before_count=$(count_dossiers "$dossier_dir")

    log_info "Dossiers before: $before_count"

    # Generic short prompt
    local short_prompt="You are a research assistant running an iterative search.

FIRST: Read prompt.md for full instructions.
THEN: Read notes.md and check the dossier directory to understand current state.
THEN: Choose ONE item to research (from backlog or find a new one).
FINALLY: Create a dossier and update notes.md.

Session iteration: $iteration
Existing dossiers: $before_count

Start now by reading prompt.md."

    # Run Claude Code with timeout
    log_info "Launching Claude Code (model: $model)..."

    gtimeout --signal=TERM "$timeout" \
        claude -p --model "$model" --dangerously-skip-permissions "$short_prompt" \
        < /dev/null 2>"$err_file" | tee "$log_file"
    local exit_code=${PIPESTATUS[0]}

    # Re-detect dossier dir (it may have been created during the session)
    dossier_dir="$(detect_dossier_dir "$folder")"
    local after_count
    after_count=$(count_dossiers "$dossier_dir")
    local new_dossiers=$((after_count - before_count))

    if [[ $exit_code -eq 124 ]]; then
        if [[ $new_dossiers -gt 0 ]]; then
            log_success "Session timed out after $timeout but created $new_dossiers new dossier(s). Work was saved."
        else
            log_warning "Session timed out after $timeout. No new dossiers created."
        fi
    elif [[ $exit_code -eq 0 ]]; then
        log_success "Session completed. Created $new_dossiers new dossier(s)."
    else
        log_warning "Session ended with exit code $exit_code."
        if [[ -s "$err_file" ]]; then
            log_error "Stderr output:"
            head -20 "$err_file"
        fi
    fi

    log_info "Dossiers before: $before_count"
    log_info "Dossiers after:  $after_count"
    log_info "New dossiers this session: $new_dossiers"

    # Return the count of new dossiers via a global variable
    _NEW_DOSSIERS=$new_dossiers

    return 0
}

cmd_run() {
    local folder=""
    local iterations=5
    local model="sonnet"
    local timeout="20m"

    # Parse arguments
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)
                model="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    # Extract positional args
    folder="${positional[0]:-}"
    if [[ -n "${positional[1]:-}" ]]; then
        iterations="${positional[1]}"
    fi

    # Validate
    if [[ -z "$folder" ]]; then
        log_error "Missing required argument: <folder>"
        echo ""
        usage
        exit 1
    fi

    # Resolve to absolute path
    folder="$(cd "$folder" 2>/dev/null && pwd)" || {
        log_error "Search folder not found: ${positional[0]}"
        exit 1
    }

    # Validate model
    if [[ "$model" != "sonnet" && "$model" != "opus" ]]; then
        log_error "Invalid model: $model (must be 'sonnet' or 'opus')"
        exit 1
    fi

    # Prerequisites
    check_prerequisites "$folder"

    # Detect folder name for banner
    local folder_name
    folder_name="$(basename "$folder")"

    # Detect dossier dir for banner
    local dossier_dir
    dossier_dir="$(detect_dossier_dir "$folder")"
    local dossier_dir_name=""
    if [[ -n "$dossier_dir" ]]; then
        dossier_dir_name="$(basename "$dossier_dir")"
    fi

    # Print banner
    echo ""
    echo -e "${BOLD}=============================================="
    echo -e "   Ralph Search - Iterative Research Loop"
    echo -e "==============================================${NC}"
    echo ""
    log_info "Configuration:"
    log_info "  Folder:      $folder_name"
    log_info "  Full path:   $folder"
    log_info "  Model:       $model"
    log_info "  Iterations:  $([ "$iterations" -eq 0 ] && echo 'infinite' || echo "$iterations")"
    log_info "  Timeout:     $timeout"
    if [[ -n "$dossier_dir_name" ]]; then
        log_info "  Dossier dir: $dossier_dir_name/"
    fi
    echo ""

    local iteration=1
    local consecutive_zero=0
    local pause_between=10

    while true; do
        # Check iteration limit
        if [[ "$iterations" -gt 0 && "$iteration" -gt "$iterations" ]]; then
            log_success "Completed $iterations iteration(s). Stopping."
            break
        fi

        # Count dossiers before (in parent shell for reliable stall detection)
        local pre_dossier_dir
        pre_dossier_dir="$(detect_dossier_dir "$folder")"
        local pre_count
        pre_count=$(count_dossiers "$pre_dossier_dir")

        # Run one iteration (working directory = search folder)
        (cd "$folder" && run_iteration "$folder" "$iteration" "$model" "$timeout") || true

        # Count dossiers after (in parent shell)
        local post_dossier_dir
        post_dossier_dir="$(detect_dossier_dir "$folder")"
        local post_count
        post_count=$(count_dossiers "$post_dossier_dir")
        local new_dossiers=$((post_count - pre_count))

        # Stall detection
        if [[ $new_dossiers -le 0 ]]; then
            consecutive_zero=$((consecutive_zero + 1))
        else
            consecutive_zero=0
        fi

        if [[ $consecutive_zero -ge 2 ]]; then
            echo ""
            log_warning "STALL DETECTED: $consecutive_zero consecutive sessions with 0 new dossiers."
            log_warning "The search may be stuck. Exiting loop."
            log_warning "Check notes.md and the last log files for details."
            break
        fi

        iteration=$((iteration + 1))

        # Pause between iterations (unless it would be the last)
        if [[ "$iterations" -eq 0 || "$iteration" -le "$iterations" ]]; then
            log_info "Pausing for ${pause_between}s before next iteration..."
            log_info "(Press Ctrl+C to stop)"
            sleep "$pause_between"
        fi
    done

    echo ""
    local dossier_dir_final
    dossier_dir_final="$(detect_dossier_dir "$folder")"
    log_success "Research loop completed!"
    log_info "Total dossiers: $(count_dossiers "$dossier_dir_final")"
    log_info "Logs saved in: $folder/logs"
}

# =============================================================================
# Status Subcommand
# =============================================================================

cmd_status() {
    local folder="${1:-}"

    if [[ -z "$folder" ]]; then
        log_error "Missing required argument: <folder>"
        echo ""
        usage
        exit 1
    fi

    # Resolve to absolute path
    folder="$(cd "$folder" 2>/dev/null && pwd)" || {
        log_error "Search folder not found: $1"
        exit 1
    }

    if [[ ! -d "$folder" ]]; then
        log_error "Search folder not found: $folder"
        exit 1
    fi

    local folder_name
    folder_name="$(basename "$folder")"

    echo ""
    echo -e "${BOLD}Ralph Search - Status: ${folder_name}${NC}"
    echo -e "${BOLD}$(printf '=%.0s' {1..50})${NC}"
    echo ""

    # Dossier count
    local dossier_dir
    dossier_dir="$(detect_dossier_dir "$folder")"
    local dossier_count
    dossier_count=$(count_dossiers "$dossier_dir")

    if [[ -n "$dossier_dir" ]]; then
        echo -e "  Dossier directory: ${CYAN}$(basename "$dossier_dir")/${NC}"
        echo -e "  Total dossiers:    ${BOLD}$dossier_count${NC}"
    else
        echo -e "  Dossier directory: ${YELLOW}(none found)${NC}"
        echo -e "  Total dossiers:    0"
    fi
    echo ""

    # Last 3 log files
    echo -e "  ${BOLD}Recent sessions:${NC}"
    local log_dir="$folder/logs"
    if [[ -d "$log_dir" ]]; then
        local log_files
        log_files=$(ls -1t "$log_dir"/session_*.log 2>/dev/null | head -3)
        if [[ -n "$log_files" ]]; then
            while IFS= read -r lf; do
                local fname
                fname="$(basename "$lf")"
                # Extract timestamp from filename: session_YYYYMMDD_HHMMSS.log
                local ts="${fname#session_}"
                ts="${ts%.log}"
                local date_part="${ts:0:8}"
                local time_part="${ts:9:6}"
                local formatted="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"
                echo "    - $formatted ($fname)"
            done <<< "$log_files"
        else
            echo "    (no session logs found)"
        fi
    else
        echo "    (no logs directory)"
    fi
    echo ""

    # Backlog analysis from notes.md
    echo -e "  ${BOLD}Backlog (from notes.md):${NC}"
    if [[ -f "$folder/notes.md" ]]; then
        local high_count
        high_count=$(grep -ic 'HIGH' "$folder/notes.md" 2>/dev/null || echo "0")
        local medium_count
        medium_count=$(grep -ic 'MEDIUM' "$folder/notes.md" 2>/dev/null || echo "0")
        echo "    HIGH priority:   $high_count lines"
        echo "    MEDIUM priority: $medium_count lines"
    else
        echo "    (notes.md not found)"
    fi
    echo ""

    # Stall risk detection: check last 2 log files for "new dossiers" count
    echo -e "  ${BOLD}Stall risk:${NC}"
    if [[ -d "$log_dir" ]]; then
        local last_two
        last_two=$(ls -1t "$log_dir"/session_*.log 2>/dev/null | head -2)
        local zero_count=0
        local log_count=0
        while IFS= read -r lf; do
            [[ -z "$lf" ]] && continue
            log_count=$((log_count + 1))
            # Look for lines like "New dossiers this session: 0" or "new dossiers"
            local new_line
            new_line=$(grep -i 'new dossiers\|new.*this session' "$lf" 2>/dev/null | tail -1)
            if [[ -n "$new_line" ]]; then
                # Extract the number at the end
                local num
                num=$(echo "$new_line" | grep -oE '[0-9]+$' || echo "")
                if [[ "$num" == "0" ]]; then
                    zero_count=$((zero_count + 1))
                fi
            fi
        done <<< "$last_two"

        if [[ $log_count -lt 2 ]]; then
            echo -e "    ${GREEN}Not enough sessions to assess (need at least 2).${NC}"
        elif [[ $zero_count -ge 2 ]]; then
            echo -e "    ${RED}HIGH - Last 2 sessions produced 0 new dossiers. Search may be stalled.${NC}"
        else
            echo -e "    ${GREEN}LOW - Recent sessions are producing dossiers.${NC}"
        fi
    else
        echo "    (no logs to analyze)"
    fi
    echo ""
}

# =============================================================================
# Dashboard Subcommand
# =============================================================================

cmd_dashboard() {
    local folder=""
    local port=8420

    # Parse arguments
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                port="$2"
                shift 2
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    folder="${positional[0]:-}"

    if [[ -z "$folder" ]]; then
        log_error "Missing required argument: <folder>"
        echo ""
        usage
        exit 1
    fi

    # Resolve to absolute path
    folder="$(cd "$folder" 2>/dev/null && pwd)" || {
        log_error "Search folder not found: ${positional[0]}"
        exit 1
    }

    if [[ ! -d "$folder" ]]; then
        log_error "Search folder not found: $folder"
        exit 1
    fi

    # Check python3
    if ! command -v python3 &> /dev/null; then
        log_error "python3 not found. Please install Python 3."
        exit 1
    fi

    # Determine dashboard directory (next to this script)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local dashboard_dir="$script_dir/dashboard"
    local requirements="$dashboard_dir/requirements.txt"

    if [[ ! -f "$dashboard_dir/server.py" ]]; then
        log_error "Dashboard not found at: $dashboard_dir/server.py"
        exit 1
    fi

    # Auto-install dependencies if needed
    if ! python3 -c "import flask, yaml, markdown" &> /dev/null 2>&1; then
        log_info "Installing dashboard dependencies..."
        pip3 install -q -r "$requirements" || {
            log_error "Failed to install dependencies. Try: pip3 install -r $requirements"
            exit 1
        }
        log_success "Dependencies installed."
    fi

    # Print URLs
    echo ""
    echo -e "${BOLD}=============================================="
    echo -e "   Ralph Search Dashboard"
    echo -e "==============================================${NC}"
    echo ""
    log_info "Folder: $(basename "$folder")"
    log_info "URL:    http://localhost:$port"

    # Try to get Tailscale IP
    if command -v tailscale &> /dev/null; then
        local ts_ip
        ts_ip=$(tailscale ip -4 2>/dev/null)
        if [[ -n "$ts_ip" ]]; then
            log_info "Tailscale: http://${ts_ip}:${port}"
        fi
    fi
    echo ""

    # Run the server
    python3 "$dashboard_dir/server.py" --folder "$folder" --port "$port"
}

# =============================================================================
# Main Entry Point
# =============================================================================

# Handle Ctrl+C gracefully
trap 'echo ""; log_warning "Interrupted by user. Exiting..."; exit 0' INT

# Parse subcommand
case "${1:-}" in
    run)
        shift
        cmd_run "$@"
        ;;
    status)
        shift
        cmd_status "$@"
        ;;
    dashboard)
        shift
        cmd_dashboard "$@"
        ;;
    --help|-h|help)
        usage
        exit 0
        ;;
    "")
        usage
        exit 0
        ;;
    *)
        log_error "Unknown subcommand: $1"
        echo ""
        usage
        exit 1
        ;;
esac
