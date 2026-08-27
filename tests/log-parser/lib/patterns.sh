#!/usr/bin/env bash
# shellcheck disable=SC2034  # Pattern variables are set here for use by callers that source this file
# lib/patterns.sh — log event regex patterns and match helpers
#
# Provides:
#   count_matches PATTERN FILE  — echo integer count of matching lines
#   extract_matches PATTERN LABEL FILE [MAX]  — emit first MAX matching lines
#
# Requires: testlib-core/bash/output.sh sourced first (emit, BOLD, RESET).

count_matches() {
    grep -cEi "$1" "$2" 2>/dev/null || true
    # grep -c exits 1 on zero matches but still prints "0" — the || true
    # prevents the fallthrough echo that would produce "0\n0" and break
    # arithmetic comparisons in the caller.
}

extract_matches() {
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

# ── Pattern definitions ────────────────────────────────────────────────────────
PAT_KERNEL_PANICS="kernel panic|panic occurred|BUG: unable to handle"
PAT_OOM_KILLS="Out of memory|oom.kill|Killed process|oom_kill_process"
PAT_SEGFAULTS="segfault|general protection fault|SIGSEGV"
PAT_HW_ERRORS="hardware error|mce|machine check|uncorrectable|correctable error"
PAT_ERRORS=" error[: ]| error$|\[error\]|ERROR:"
PAT_WARNINGS=" warning[: ]| warning$|\[warning\]|WARNING:"
PAT_CALL_TRACES="Call Trace:|call trace:"
PAT_DISK_ERRORS="I/O error|blk_update_request|end_request|SCSI error|medium error"
PAT_NET_ERRORS="link is down|NIC.*fail|network.*unreachable|eth[0-9].*error"
PAT_SERVICE_FAILS="Failed to start|service failed|systemd.*fail|Unit.*failed"
