# =============================================================
# k6 Teststeuerung fuer mehrere Verfahren
# =============================================================
# Beispiele:
#   make list
#   make deploy TEST=verfahren-a
#   make logs TEST=verfahren-a
#   make status
#   make clean TEST=verfahren-a
# =============================================================

-include .env
export

NAMESPACE ?= lup-k6
TEST ?=
TESTRUN_NAME ?= $(TEST)

CYAN  := \033[36m
RESET := \033[0m
BOLD  := \033[1m

.DEFAULT_GOAL := help

.PHONY: help list deploy logs status clean validate

help: ## Zeigt diese Hilfe
	@echo ""
	@echo "$(BOLD)k6 Teststeuerung$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-16s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "Beispiele:"
	@echo "  make list"
	@echo "  make deploy TEST=verfahren-a"
	@echo "  make logs TEST=verfahren-a"
	@echo ""

list: ## Listet alle Tests unter tests/
	@if [ -d tests ]; then \
	  find tests -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort; \
	else \
	  echo "Kein tests/ Verzeichnis gefunden."; \
	fi

deploy: ## Startet einen TestRun, z.B. make deploy TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make deploy TEST=verfahren-a" && exit 1)
	@bash scripts/deploy.sh "$(TEST)"

logs: ## Folgt den Logs eines TestRuns, z.B. make logs TEST=verfahren-a
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make logs TEST=verfahren-a" && exit 1)
	kubectl logs -f -l k6_cr=$(TESTRUN_NAME) -n $(NAMESPACE) --all-containers=true

status: ## Zeigt TestRuns und Pods im Namespace
	@echo ""
	@echo "$(BOLD)TestRuns ($(NAMESPACE))$(RESET)"
	@kubectl get testruns -n $(NAMESPACE) 2>/dev/null || echo "  Keine TestRuns gefunden."
	@echo ""
	@echo "$(BOLD)Pods ($(NAMESPACE))$(RESET)"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "  Keine Pods gefunden."
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
