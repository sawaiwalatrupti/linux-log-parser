#!/usr/bin/env bash
# log_parser.sh — Linux system log analyser
# Scans dmesg, journalctl, or a log file for errors, warnings,
# kernel panics, OOM kills, and hardware faults.
# Outputs a timestamped summary report to stdout and optionally to a file.
#
# Usage:
#   ./log_parser.sh                        # scan dmesg + journalctl live
#   ./log_parser.sh -f /var/log/syslog     # scan a log file
#   ./log_parser.sh -f kern.log -o report.txt
#   ./log_parser.sh --since "1 hour ago"   # journalctl time filter

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────────────
INPUT_FILE=""
OUTPUT_FILE=""
SINCE_TIME=""
USE_DMESG=1
USE_JOURNAL=1
REPORT_LINES=()

# ── colours (disabled if not a terminal) ──────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; RESET=''
fi

# ── helpers ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -f, --file FILE       Parse a specific log file instead of live system logs
  -o, --output FILE     Write report to FILE (in addition to stdout)
  --since TIME          Passed to journalctl --since (e.g. "2 hours ago")
  -h, --help            Show this help

Examples:
  $0                              Scan dmesg + journalctl (needs root for full journal)
  $0 -f /var/log/syslog           Scan syslog file
  $0 -f kern.log -o report.txt    Scan file and save report
  $0 --since "1 hour ago"         Scan last hour of journal
EOF
    exit 0
}

log()   { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*"; }

emit() {
    # Print a line and also store it for file output
    echo -e "$1"
    REPORT_LINES+=("$1")
}

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)    INPUT_FILE="$2"; USE_DMESG=0; USE_JOURNAL=0; shift 2 ;;
        -o|--output)  OUTPUT_FILE="$2"; shift 2 ;;
        --since)      SINCE_TIME="$2"; USE_DMESG=0; shift 2 ;;
        -h|--help)    usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

# ── collect log data into a temp file ─────────────────────────────────────────
TMPFILE=$(mktemp /tmp/log_parser_XXXXXX.log)
trap 'rm -f "$TMPFILE"' EXIT

if [[ -n "$INPUT_FILE" ]]; then
    if [[ ! -f "$INPUT_FILE" ]]; then
        error "File not found: $INPUT_FILE"
        exit 1
    fi
    log "Reading log file: $INPUT_FILE"
    cat "$INPUT_FILE" > "$TMPFILE"
else
    if [[ "$USE_DMESG" -eq 1 ]]; then
        log "Collecting dmesg output..."
        dmesg --time-format iso 2>/dev/null >> "$TMPFILE" || dmesg >> "$TMPFILE"
    fi
    if [[ "$USE_JOURNAL" -eq 1 ]]; then
        log "Collecting journalctl output..."
        if [[ -n "$SINCE_TIME" ]]; then
            journalctl --no-pager --since "$SINCE_TIME" 2>/dev/null >> "$TMPFILE" || true
        else
            journalctl --no-pager -b 2>/dev/null >> "$TMPFILE" || true
        fi
    fi
fi

TOTAL_LINES=$(wc -l < "$TMPFILE")
log "Total log lines to scan: $TOTAL_LINES"

# ── pattern matching ──────────────────────────────────────────────────────────
count_matches() {
    # count_matches PATTERN FILE
    grep -cEi "$1" "$2" 2>/dev/null || echo 0
}

extract_matches() {
    # extract_matches PATTERN LABEL FILE MAX_LINES
    local pattern="$1" label="$2" file="$3" max="${4:-10}"
    local matches
    matches=$(grep -Ei "$pattern" "$file" 2>/dev/null | head -n "$max" || true)
    if [[ -n "$matches" ]]; then
        emit "${BOLD}  ── ${label} (first ${max} shown) ──${RESET}"
        while IFS= read -r line; do
            emit "    $line"
        done <<< "$matches"
    fi
}

KERNEL_PANICS=$(count_matches "kernel panic|panic occurred|BUG: unable to handle" "$TMPFILE")
OOM_KILLS=$(count_matches "Out of memory|oom.kill|Killed process|oom_kill_process" "$TMPFILE")
SEGFAULTS=$(count_matches "segfault|general protection fault|SIGSEGV" "$TMPFILE")
HW_ERRORS=$(count_matches "hardware error|mce|machine check|uncorrectable|correctable error" "$TMPFILE")
ERRORS=$(count_matches " error[: ]| error$|\[error\]|ERROR:" "$TMPFILE")
WARNINGS=$(count_matches " warning[: ]| warning$|\[warning\]|WARNING:" "$TMPFILE")
CALL_TRACES=$(count_matches "Call Trace:|call trace:" "$TMPFILE")
DISK_ERRORS=$(count_matches "I/O error|blk_update_request|end_request|SCSI error|medium error" "$TMPFILE")
NET_ERRORS=$(count_matches "link is down|NIC.*fail|network.*unreachable|eth[0-9].*error" "$TMPFILE")
SERVICE_FAILS=$(count_matches "Failed to start|service failed|systemd.*fail|Unit.*failed" "$TMPFILE")

# ── severity scoring ──────────────────────────────────────────────────────────
SCORE=0
[[ "$KERNEL_PANICS" -gt 0 ]] && SCORE=$((SCORE + 50))
[[ "$OOM_KILLS"     -gt 0 ]] && SCORE=$((SCORE + 30))
[[ "$HW_ERRORS"     -gt 0 ]] && SCORE=$((SCORE + 20))
[[ "$SEGFAULTS"     -gt 0 ]] && SCORE=$((SCORE + 15))
[[ "$DISK_ERRORS"   -gt 0 ]] && SCORE=$((SCORE + 15))
[[ "$CALL_TRACES"   -gt 0 ]] && SCORE=$((SCORE + 10))
[[ "$ERRORS"        -gt 5 ]] && SCORE=$((SCORE + 5))

if   [[ "$SCORE" -ge 50 ]]; then SEVERITY="${RED}CRITICAL${RESET}"
elif [[ "$SCORE" -ge 20 ]]; then SEVERITY="${YELLOW}WARNING${RESET}"
elif [[ "$SCORE" -ge 1  ]]; then SEVERITY="${YELLOW}LOW${RESET}"
else                              SEVERITY="${GREEN}CLEAN${RESET}"
fi

# ── report ────────────────────────────────────────────────────────────────────
NOW=$(date '+%Y-%m-%d %H:%M:%S')
HOSTNAME=$(hostname)

emit ""
emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit "${BOLD}  Linux Log Analysis Report${RESET}"
emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit "  Host      : $HOSTNAME"
emit "  Generated : $NOW"
if [[ -n "$INPUT_FILE" ]]; then
    emit "  Source    : $INPUT_FILE"
else
    emit "  Source    : live system (dmesg + journalctl)"
fi
emit "  Log lines : $TOTAL_LINES"
emit "${BOLD}────────────────────────────────────────────────────────────${RESET}"
emit ""
emit "${BOLD}  Overall severity : ${SEVERITY}${RESET}  (score: $SCORE)"
emit ""
emit "${BOLD}  Event Summary${RESET}"
emit "  ─────────────────────────────────────"
emit "  Kernel panics         : $([ "$KERNEL_PANICS" -gt 0 ] && echo "${RED}${KERNEL_PANICS}${RESET}" || echo "${GREEN}0${RESET}")"
emit "  OOM kills             : $([ "$OOM_KILLS"     -gt 0 ] && echo "${RED}${OOM_KILLS}${RESET}"     || echo "${GREEN}0${RESET}")"
emit "  Segfaults             : $([ "$SEGFAULTS"     -gt 0 ] && echo "${YELLOW}${SEGFAULTS}${RESET}"  || echo "${GREEN}0${RESET}")"
emit "  Hardware errors (MCE) : $([ "$HW_ERRORS"     -gt 0 ] && echo "${RED}${HW_ERRORS}${RESET}"    || echo "${GREEN}0${RESET}")"
emit "  Disk / I/O errors     : $([ "$DISK_ERRORS"   -gt 0 ] && echo "${YELLOW}${DISK_ERRORS}${RESET}" || echo "${GREEN}0${RESET}")"
emit "  Kernel call traces    : $([ "$CALL_TRACES"   -gt 0 ] && echo "${YELLOW}${CALL_TRACES}${RESET}" || echo "${GREEN}0${RESET}")"
emit "  Network errors        : $([ "$NET_ERRORS"    -gt 0 ] && echo "${YELLOW}${NET_ERRORS}${RESET}"  || echo "${GREEN}0${RESET}")"
emit "  Systemd service fails : $([ "$SERVICE_FAILS" -gt 0 ] && echo "${YELLOW}${SERVICE_FAILS}${RESET}" || echo "${GREEN}0${RESET}")"
emit "  Total errors          : $ERRORS"
emit "  Total warnings        : $WARNINGS"
emit ""

# ── detailed sections (only printed if events found) ─────────────────────────
if [[ "$KERNEL_PANICS" -gt 0 ]]; then
    emit "${RED}${BOLD}  ● KERNEL PANICS${RESET}"
    extract_matches "kernel panic|panic occurred|BUG: unable to handle" "Kernel Panic Lines" "$TMPFILE" 5
    emit ""
fi

if [[ "$OOM_KILLS" -gt 0 ]]; then
    emit "${RED}${BOLD}  ● OOM KILLS${RESET}"
    extract_matches "Out of memory|oom.kill|Killed process|oom_kill_process" "OOM Events" "$TMPFILE" 5
    emit ""
fi

if [[ "$HW_ERRORS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● HARDWARE / MCE ERRORS${RESET}"
    extract_matches "hardware error|mce|machine check|uncorrectable|correctable error" "HW Errors" "$TMPFILE" 5
    emit ""
fi

if [[ "$DISK_ERRORS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● DISK / I/O ERRORS${RESET}"
    extract_matches "I/O error|blk_update_request|end_request|SCSI error|medium error" "Disk Errors" "$TMPFILE" 5
    emit ""
fi

if [[ "$SERVICE_FAILS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● FAILED SYSTEMD SERVICES${RESET}"
    extract_matches "Failed to start|service failed|systemd.*fail|Unit.*failed" "Service Failures" "$TMPFILE" 5
    emit ""
fi

emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit ""

# ── write report to file if requested ─────────────────────────────────────────
if [[ -n "$OUTPUT_FILE" ]]; then
    # Strip ANSI colour codes for the file version
    printf '%s\n' "${REPORT_LINES[@]}" | sed 's/\x1b\[[0-9;]*m//g' > "$OUTPUT_FILE"
    log "Report saved to: $OUTPUT_FILE"
fi
