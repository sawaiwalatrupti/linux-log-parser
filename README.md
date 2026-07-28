# linux-log-parser

A Bash script that scans Linux system logs for errors, warnings, kernel panics, OOM kills, hardware faults, and failed services — and outputs a clean, colour-coded summary report.

Useful for post-mortem analysis, CI test environment debugging, and routine system health checks.

---

## What it detects

| Category | Patterns matched |
|---|---|
| Kernel panics | `kernel panic`, `BUG: unable to handle` |
| OOM kills | `Out of memory`, `Killed process`, `oom_kill_process` |
| Segfaults | `segfault`, `general protection fault`, `SIGSEGV` |
| Hardware errors | `mce`, `machine check`, `uncorrectable error` |
| Disk / I/O errors | `I/O error`, `blk_update_request`, `SCSI error` |
| Network errors | `link is down`, `eth* error` |
| Systemd failures | `Failed to start`, `Unit * failed` |
| Kernel call traces | `Call Trace:` |

The script computes an overall **severity score** (`CRITICAL / WARNING / LOW / CLEAN`) based on which events were found.

---

## Usage

```bash
# Make executable (first time only)
chmod +x log_parser.sh

# Scan live system logs (dmesg + journalctl for current boot)
./log_parser.sh

# Scan a specific log file
./log_parser.sh -f /var/log/syslog

# Scan a file and save the report
./log_parser.sh -f /var/log/kern.log -o report.txt

# Scan the last 2 hours of the journal
./log_parser.sh --since "2 hours ago"
```

---

## Sample output

```
════════════════════════════════════════════════════════════
  Linux Log Analysis Report
════════════════════════════════════════════════════════════
  Host      : testserver-01
  Generated : 2025-06-01 14:32:10
  Source    : /var/log/syslog
  Log lines : 48231
────────────────────────────────────────────────────────────

  Overall severity : WARNING  (score: 35)

  Event Summary
  ─────────────────────────────────────
  Kernel panics         : 0
  OOM kills             : 2
  Segfaults             : 1
  Hardware errors (MCE) : 0
  Disk / I/O errors     : 3
  Kernel call traces    : 0
  Network errors        : 0
  Systemd service fails : 1
  Total errors          : 27
  Total warnings        : 14

  ● OOM KILLS
  ── OOM Events (first 5 shown) ──
    Jun  1 12:15:44 testserver-01 kernel: Out of memory: Killed process 4821 (java)
    Jun  1 13:02:01 testserver-01 kernel: oom_kill_process: total-vm:2048000kB

════════════════════════════════════════════════════════════
```

---

## Options

| Flag | Description |
|---|---|
| `-f FILE` | Parse a specific log file |
| `-o FILE` | Write plain-text report to a file (ANSI colours stripped) |
| `--since TIME` | journalctl `--since` value (e.g. `"1 hour ago"`, `"2025-05-01"`) |
| `-h` | Show help |

---

## Requirements

- Bash 4.0+
- `dmesg` and/or `journalctl` available (for live system mode)
- No external dependencies

Tested on RHEL 9, SLES 15, Ubuntu 22.04.
