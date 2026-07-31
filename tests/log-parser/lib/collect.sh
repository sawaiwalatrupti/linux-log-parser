#!/usr/bin/env bash
# lib/collect.sh — log data collection (file, dmesg, journalctl)
#
# Requires: testlib-core/bash/output.sh sourced first (log, error).
#
# Provides:
#   collect_logs TMPFILE INPUT_FILE USE_DMESG USE_JOURNAL SINCE_TIME
#   Populates TMPFILE with raw log data; exits 1 if INPUT_FILE not found.

collect_logs() {
    local tmpfile="$1"
    local input_file="$2"
    local use_dmesg="$3"
    local use_journal="$4"
    local since_time="$5"

    if [[ -n "$input_file" ]]; then
        if [[ ! -f "$input_file" ]]; then
            error "File not found: $input_file"
            exit 1
        fi
        log "Reading log file: $input_file"
        cat "$input_file" > "$tmpfile"
        return
    fi

    if [[ "$use_dmesg" -eq 1 ]]; then
        log "Collecting dmesg output..."
        dmesg --time-format iso 2>/dev/null >> "$tmpfile" || dmesg >> "$tmpfile"
    fi

    if [[ "$use_journal" -eq 1 ]]; then
        log "Collecting journalctl output..."
        if [[ -n "$since_time" ]]; then
            journalctl --no-pager --since "$since_time" 2>/dev/null >> "$tmpfile" || true
        else
            journalctl --no-pager -b 2>/dev/null >> "$tmpfile" || true
        fi
    fi
}
