# =============================================================
# k6 Teststeuerung fuer mehrere Verfahren
# =============================================================
# Diese Datei ist als Vorlage gedacht.
# Erwartete Struktur:
#   tests/<testname>/test.js
#   tests/<testname>/testrun.yaml
#   tests/<testname>/testdatafiles.txt   optional
# =============================================================

SHELL := /bin/bash

-include .env
export

NAMESPACE ?= lup-k6
TEST ?=
TESTRUN_NAME ?= $(TEST)

CYAN  := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED   := \033[31m
RESET := \033[0m
BOLD  := \033[1m

.DEFAULT_GOAL := help

.PHONY: help list info deploy logs status clean validate

help: ## Zeigt Hilfe und Beispiele
	@echo ""
	@echo -e "$(BOLD)k6 Teststeuerung$(RESET)"
	@echo ""
	@echo "Namespace: $(NAMESPACE)"
	@echo ""
	@echo "Befehle:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Typischer Ablauf:"
	@echo "  make list"
	@echo "  make info TEST=verfahren-a"
	@echo "  make validate TEST=verfahren-a"
	@echo "  make deploy TEST=verfahren-a"
	@echo "  make logs TEST=verfahren-a"
	@echo ""

list: ## Listet alle Tests mit Status der benoetigten Dateien
	@echo ""
	@echo -e "$(BOLD)Verfuegbare k6 Tests$(RESET)"
	@echo "Namespace: $(NAMESPACE)"
	@echo ""
	@if [[ ! -d tests ]]; then \
	  echo -e "$(YELLOW)Kein tests/ Verzeichnis gefunden.$(RESET)"; \
	  echo "Erwartet wird z.B.: tests/verfahren-a/test.js"; \
	else \
	  printf "%-28s %-8s %-8s %-10s %-8s\n" "Test" "Script" "TestRun" "Testdaten" "README"; \
	  printf "%-28s %-8s %-8s %-10s %-8s\n" "----------------------------" "--------" "--------" "----------" "--------"; \
	  found=0; \
	  while IFS= read -r dir; do \
	    found=1; \
	    test_name="$$(basename "$$dir")"; \
	    script_status="MISSING"; \
	    testrun_status="MISSING"; \
	    readme_status="-"; \
	    data_status="-"; \
	    [[ -f "$$dir/test.js" ]] && script_status="OK"; \
	    [[ -f "$$dir/testrun.yaml" ]] && testrun_status="OK"; \
	    [[ -f "$$dir/README.md" ]] && readme_status="OK"; \
	    if [[ -f "$$dir/testdatafiles.txt" ]]; then \
	      data_count="$$(grep -Ev '^[[:space:]]*($$|#)' "$$dir/testdatafiles.txt" | wc -l | xargs)"; \
	      data_status="$${data_count} file(s)"; \
	    fi; \
	    printf "%-28s %-8s %-8s %-10s %-8s\n" "$$test_name" "$$script_status" "$$testrun_status" "$$data_status" "$$readme_status"; \
	  done < <(find tests -mindepth 1 -maxdepth 1 -type d | sort); \
	  if [[ "$$found" -eq 0 ]]; then \
	    echo "Keine Testordner unter tests/ gefunden."; \
	  fi; \
	fi
	@echo ""
	@echo "Details zu einem Test:"
	@echo "  make info TEST=<testname>"
	@echo ""

info: ## Zeigt Details zu einem Test, z.B. make info TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make info TEST=verfahren-a" && exit 1)
	@TEST_DIR="tests/$(TEST)"; \
	if [[ ! -d "$$TEST_DIR" ]]; then \
	  echo "Testverzeichnis nicht gefunden: $$TEST_DIR"; \
	  exit 1; \
	fi; \
	echo ""; \
	echo -e "$(BOLD)k6 Test: $(TEST)$(RESET)"; \
	echo ""; \
	echo "Namespace:       $(NAMESPACE)"; \
	echo "TestRun Name:    $(TESTRUN_NAME)"; \
	echo "Testordner:      $$TEST_DIR"; \
	echo "k6 Skript:       $$TEST_DIR/test.js"; \
	echo "TestRun YAML:    $$TEST_DIR/testrun.yaml"; \
	echo "Testdatenliste:  $$TEST_DIR/testdatafiles.txt"; \
	echo ""; \
	echo "Dateistatus:"; \
	[[ -f "$$TEST_DIR/test.js" ]] && echo "  OK      test.js" || echo "  FEHLT   test.js"; \
	[[ -f "$$TEST_DIR/testrun.yaml" ]] && echo "  OK      testrun.yaml" || echo "  FEHLT   testrun.yaml"; \
	[[ -f "$$TEST_DIR/testdatafiles.txt" ]] && echo "  OK      testdatafiles.txt" || echo "  -       testdatafiles.txt nicht vorhanden"; \
	[[ -f "$$TEST_DIR/README.md" ]] && echo "  OK      README.md" || echo "  -       README.md nicht vorhanden"; \
	if [[ -f "$$TEST_DIR/testdatafiles.txt" ]]; then \
	  echo ""; \
	  echo "Explizite Testdaten:"; \
	  grep -Ev '^[[:space:]]*($$|#)' "$$TEST_DIR/testdatafiles.txt" | sed 's/^/  - /' || true; \
	fi; \
	echo ""; \
	echo "Naechste Befehle:"; \
	echo "  make validate TEST=$(TEST)"; \
	echo "  make deploy TEST=$(TEST)"; \
	echo "  make logs TEST=$(TEST)"; \
	echo ""

deploy: ## Startet einen TestRun, z.B. make deploy TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make deploy TEST=verfahren-a" && exit 1)
	@bash scripts/deploy.sh "$(TEST)"

logs: ## Folgt den Logs eines TestRuns, z.B. make logs TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make logs TEST=verfahren-a" && exit 1)
	kubectl logs -f -l k6_cr=$(TESTRUN_NAME) -n $(NAMESPACE) --all-containers=true

status: ## Zeigt TestRuns und Pods im Namespace
	@echo ""
	@echo -e "$(BOLD)TestRuns ($(NAMESPACE))$(RESET)"
	@kubectl get testruns -n $(NAMESPACE) -o wide 2>/dev/null || echo "  Keine TestRuns gefunden oder kein Zugriff."
	@echo ""
	@echo -e "$(BOLD)Pods ($(NAMESPACE))$(RESET)"
	@kubectl get pods -n $(NAMESPACE) -o wide 2>/dev/null || echo "  Keine Pods gefunden oder kein Zugriff."
	@echo ""

clean: ## Loescht einen TestRun, z.B. make clean TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make clean TEST=verfahren-a" && exit 1)
	kubectl delete testrun $(TESTRUN_NAME) -n $(NAMESPACE) --ignore-not-found=true

validate: ## Validiert das TestRun-Manifest, z.B. make validate TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make validate TEST=verfahren-a" && exit 1)
	@test -f tests/$(TEST)/testrun.yaml || (echo "Nicht gefunden: tests/$(TEST)/testrun.yaml" && exit 1)
	@TEST_NAME="$(TEST)" \
	  TESTRUN_NAME="$(TESTRUN_NAME)" \
	  NAMESPACE="$(NAMESPACE)" \
	  CONFIGMAP_NAME="$(TEST)-script" \
	  TEST_RUN_ID="validate-dryrun" \
	  envsubst < tests/$(TEST)/testrun.yaml | kubectl apply --dry-run=client -f -
