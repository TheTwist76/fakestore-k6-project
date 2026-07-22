-include .env
export

NAMESPACE ?= lup-k6
TEST ?=

.PHONY: help list deploy logs status clean validate

help:
	@echo ""
	@echo "k6 Teststeuerung"
	@echo ""
	@echo "  make list"
	@echo "  make deploy TEST=verfahren-a"
	@echo "  make logs TEST=verfahren-a"
	@echo "  make status"
	@echo "  make clean TEST=verfahren-a"
	@echo "  make validate TEST=verfahren-a"
	@echo ""

list:
	@find tests -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort

deploy:
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make deploy TEST=verfahren-a" && exit 1)
	@bash scripts/deploy.sh "$(TEST)"

logs:
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make logs TEST=verfahren-a" && exit 1)
	kubectl logs -f -l k6_cr=$(TEST) -n $(NAMESPACE)

status:
	kubectl get testruns -n $(NAMESPACE)
	kubectl get pods -n $(NAMESPACE)

clean:
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make clean TEST=verfahren-a" && exit 1)
	kubectl delete testrun $(TEST) -n $(NAMESPACE) --ignore-not-found=true

validate:
	@test -n "$(TEST)" || (echo "Bitte TEST setzen, z.B. make validate TEST=verfahren-a" && exit 1)
	@TEST_RUN_ID="validate" TEST_NAME="$(TEST)" NAMESPACE="$(NAMESPACE)" \
	  CONFIGMAP_NAME="$(TEST)-script" \
	  envsubst < tests/$(TEST)/testrun.yaml | kubectl apply --dry-run=client -f -
