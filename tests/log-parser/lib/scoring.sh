#!/usr/bin/env bash
# shellcheck disable=SC2034  # SEVERITY is set here for use by caller that sources this file
# lib/scoring.sh — severity scoring for log events
#
# Requires: patterns.sh sourced and count vars populated (KERNEL_PANICS etc.)
# Requires: bash-test-libs/bash/colors.sh sourced first (RED, YELLOW, GREEN, RESET).
#
# Provides:
#   compute_severity  — sets SCORE and SEVERITY based on event counts

compute_severity() {
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
}
