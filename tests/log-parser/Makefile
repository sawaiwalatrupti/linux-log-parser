# tests/log-parser/Makefile

SCRIPT  := log_parser.sh
OUTFILE := /tmp/log_report.txt

.PHONY: run run-file lint clean

run:
	bash $(SCRIPT)

run-file:
	@test -n "$(FILE)" || (echo "Usage: make run-file FILE=/path/to/log"; exit 1)
	bash $(SCRIPT) -f $(FILE) -o $(OUTFILE)
	@echo "Report written to $(OUTFILE)"

lint:
	shellcheck $(SCRIPT) lib/patterns.sh lib/collect.sh lib/scoring.sh

clean:
	rm -f $(OUTFILE)
