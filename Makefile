# =============================================================
# FakeStore k6 HTTP Premium – Makefile
# =============================================================
# Verwendung:
#   make help        → Alle verfügbaren Targets
#   make deploy      → Testlauf starten
#   make badrun      → Bad-Run Demo starten
#   make logs        → Logs verfolgen
#   make status      → Pod- und TestRun-Status
#   make clean       → Laufende Tests stoppen
#
# Konfiguration (optional):
#   Datei .env anlegen (Vorlage: .env.example)
#   → GRAFANA_URL und GRAFANA_TOKEN für Annotations setzen
# =============================================================

-include .env
export

NAMESPACE   := k6-testing
TESTRUN     := fakestore-premium
BADRUN      := fakestore-badrun

# Farben
CYAN  := \033[36m
RESET := \033[0m
BOLD  := \033[1m

.DEFAULT_GOAL := help

.PHONY: help deploy badrun logs logs-badrun status clean clean-all validate

help: ## Zeigt diese Hilfe
	@echo ""
	@echo "$(BOLD)FakeStore k6 HTTP Premium$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-16s$(RESET) %s\n", $$1, $$2}'
	@echo ""

deploy: ## Startet einen normalen Testlauf (Ramping VUs, korrekte Credentials)
	@bash deploy.sh

badrun: ## Startet den Bad-Run Demo (falsche Credentials → 0% Login Success)
	@bash demo-badrun.sh

logs: ## Folgt den Logs des laufenden Testlaufs
	kubectl logs -f -l k6_cr=$(TESTRUN) -n $(NAMESPACE)

logs-badrun: ## Folgt den Logs des Bad-Run
	kubectl logs -f -l k6_cr=$(BADRUN) -n $(NAMESPACE)

status: ## Zeigt Pod- und TestRun-Status im Namespace
	@echo ""
	@echo "$(BOLD)Pods ($(NAMESPACE))$(RESET)"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "  (keine Pods gefunden)"
	@echo ""
	@echo "$(BOLD)TestRuns ($(NAMESPACE))$(RESET)"
	@kubectl get testruns -n $(NAMESPACE) 2>/dev/null || echo "  (keine TestRuns gefunden)"
	@echo ""

clean: ## Löscht aktive TestRuns (Namespace und ConfigMap bleiben erhalten)
	kubectl delete testrun $(TESTRUN) -n $(NAMESPACE) --ignore-not-found=true
	kubectl delete testrun $(BADRUN)  -n $(NAMESPACE) --ignore-not-found=true

clean-all: ## Löscht den gesamten Namespace k6-testing (VORSICHT!)
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true

validate: ## Validiert k8s-Manifests via dry-run (ohne Deployment)
	@echo "Validiere fakestore-premium-testrun.yaml ..."
	@export TEST_RUN_ID="validate-dryrun" GRAFANA_URL="" GRAFANA_TOKEN="" && \
	  envsubst < k8s/fakestore-premium-testrun.yaml | kubectl apply --dry-run=client -f -
	@echo "Validiere fakestore-badrun-testrun.yaml ..."
	@export TEST_RUN_ID="validate-dryrun" && \
	  envsubst < k8s/fakestore-badrun-testrun.yaml | kubectl apply --dry-run=client -f -
	@echo "Alle Manifests valide."
