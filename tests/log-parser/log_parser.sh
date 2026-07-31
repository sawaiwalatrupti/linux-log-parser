#!/usr/bin/env bash
# log_parser.sh — Linux system log analyser (entry point)
#
# Usage:
#   ./log_parser.sh                        # scan dmesg + journalctl live
#   ./log_parser.sh -f /var/log/syslog     # scan a log file
#   ./log_parser.sh -f kern.log -o report.txt
#   ./log_parser.sh --since "1 hour ago"   # journalctl time filter

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
SHARED_LIB="$SCRIPT_DIR/../../../bash-test-libs/bash"

# ── load shared library ───────────────────────────────────────────────────────
if [[ ! -d "$SHARED_LIB" ]]; then
    echo "ERROR: bash-test-libs not found at: $SHARED_LIB" >&2
    echo "       Clone it: git clone https://github.com/sawaiwalatrupti/bash-test-libs.git" >&2
    exit 1
fi

# shellcheck source=../../../bash-test-libs/bash/colors.sh
source "$SHARED_LIB/colors.sh"
# shellcheck source=../../../bash-test-libs/bash/output.sh
source "$SHARED_LIB/output.sh"

# ── load local modules ────────────────────────────────────────────────────────
# shellcheck source=lib/patterns.sh
source "$LIB_DIR/patterns.sh"
# shellcheck source=lib/collect.sh
source "$LIB_DIR/collect.sh"
# shellcheck source=lib/scoring.sh
source "$LIB_DIR/scoring.sh"

# ── state ─────────────────────────────────────────────────────────────────────
REPORT_LINES=()
INPUT_FILE=""
OUTPUT_FILE=""
SINCE_TIME=""
USE_DMESG=1
USE_JOURNAL=1

# ── usage ─────────────────────────────────────────────────────────────────────
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

# ── argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)   INPUT_FILE="$2"; USE_DMESG=0; USE_JOURNAL=0; shift 2 ;;
        -o|--output) OUTPUT_FILE="$2"; shift 2 ;;
        --since)     SINCE_TIME="$2"; USE_DMESG=0; shift 2 ;;
        -h|--help)   usage ;;
        *) error "Unknown option: $1"; usage ;;
    esac
done

# ── collect logs ──────────────────────────────────────────────────────────────
TMPFILE=$(mktemp /tmp/log_parser_XXXXXX.log)
trap 'rm -f "$TMPFILE"' EXIT

collect_logs "$TMPFILE" "$INPUT_FILE" "$USE_DMESG" "$USE_JOURNAL" "$SINCE_TIME"

TOTAL_LINES=$(wc -l < "$TMPFILE")
log "Total log lines to scan: $TOTAL_LINES"

# ── count events ──────────────────────────────────────────────────────────────
KERNEL_PANICS=$(count_matches "$PAT_KERNEL_PANICS" "$TMPFILE")
OOM_KILLS=$(count_matches     "$PAT_OOM_KILLS"     "$TMPFILE")
SEGFAULTS=$(count_matches     "$PAT_SEGFAULTS"     "$TMPFILE")
HW_ERRORS=$(count_matches     "$PAT_HW_ERRORS"     "$TMPFILE")
ERRORS=$(count_matches        "$PAT_ERRORS"        "$TMPFILE")
WARNINGS=$(count_matches      "$PAT_WARNINGS"      "$TMPFILE")
CALL_TRACES=$(count_matches   "$PAT_CALL_TRACES"   "$TMPFILE")
DISK_ERRORS=$(count_matches   "$PAT_DISK_ERRORS"   "$TMPFILE")
NET_ERRORS=$(count_matches    "$PAT_NET_ERRORS"    "$TMPFILE")
SERVICE_FAILS=$(count_matches "$PAT_SERVICE_FAILS" "$TMPFILE")

# ── compute severity ──────────────────────────────────────────────────────────
compute_severity

# ── report ────────────────────────────────────────────────────────────────────
NOW=$(date '+%Y-%m-%d %H:%M:%S')

emit ""
emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit "${BOLD}  Linux Log Analysis Report${RESET}"
emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit "  Host      : $(hostname)"
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

# ── detailed sections (only when events found) ────────────────────────────────
if [[ "$KERNEL_PANICS" -gt 0 ]]; then
    emit "${RED}${BOLD}  ● KERNEL PANICS${RESET}"
    extract_matches "$PAT_KERNEL_PANICS" "Kernel Panic Lines" "$TMPFILE" 5
    emit ""
fi

if [[ "$OOM_KILLS" -gt 0 ]]; then
    emit "${RED}${BOLD}  ● OOM KILLS${RESET}"
    extract_matches "$PAT_OOM_KILLS" "OOM Events" "$TMPFILE" 5
    emit ""
fi

if [[ "$HW_ERRORS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● HARDWARE / MCE ERRORS${RESET}"
    extract_matches "$PAT_HW_ERRORS" "HW Errors" "$TMPFILE" 5
    emit ""
fi

if [[ "$DISK_ERRORS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● DISK / I/O ERRORS${RESET}"
    extract_matches "$PAT_DISK_ERRORS" "Disk Errors" "$TMPFILE" 5
    emit ""
fi

if [[ "$SERVICE_FAILS" -gt 0 ]]; then
    emit "${YELLOW}${BOLD}  ● FAILED SYSTEMD SERVICES${RESET}"
    extract_matches "$PAT_SERVICE_FAILS" "Service Failures" "$TMPFILE" 5
    emit ""
fi

emit "${BOLD}════════════════════════════════════════════════════════════${RESET}"
emit ""

[[ -n "$OUTPUT_FILE" ]] && save_report "$OUTPUT_FILE"
