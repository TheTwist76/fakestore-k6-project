#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="k6-testing"
TESTRUN_NAME="fakestore-premium"
export TEST_RUN_ID="fakestore-$(date +%Y%m%d-%H%M%S)"

# .env laden, falls vorhanden (für GRAFANA_URL, GRAFANA_TOKEN usw.)
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -o allexport
  # shellcheck source=.env
  source "${SCRIPT_DIR}/.env"
  set +o allexport
fi
export GRAFANA_URL="${GRAFANA_URL:-}"
export GRAFANA_TOKEN="${GRAFANA_TOKEN:-}"

echo "============================================"
echo " FakeStore k6 HTTP Demo – Deployment"
echo "============================================"
echo "Namespace:   ${NAMESPACE}"
echo "Test Run ID: ${TEST_RUN_ID}"
echo ""

echo "[1/4] Namespace sicherstellen"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/4] ConfigMap aus fakestore-premium.js generieren und anwenden"
kubectl create configmap fakestore-premium-script \
  --from-file=fakestore-premium.js=fakestore-premium.js \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[3/4] Vorherigen TestRun löschen (falls vorhanden)"
kubectl delete testrun "${TESTRUN_NAME}" -n "${NAMESPACE}" --ignore-not-found=true

echo "[4/4] Neuen TestRun starten (Test Run ID: ${TEST_RUN_ID})"
envsubst < k8s/fakestore-premium-testrun.yaml | kubectl apply -f -

echo ""
echo "Warte auf Pod-Start..."
sleep 5
kubectl wait pod \
  -l "k6_cr=${TESTRUN_NAME}" \
  -n "${NAMESPACE}" \
  --for=condition=Ready \
  --timeout=90s 2>/dev/null || true

echo ""
echo "Aktuelle Pods:"
kubectl get pods -n "${NAMESPACE}" | grep "${TESTRUN_NAME}" || true

echo ""
echo "Logs verfolgen (Beispiel):"
echo "  kubectl logs -f -l k6_cr=${TESTRUN_NAME} -n ${NAMESPACE}"
echo ""
echo "Grafana: Filter auf Test Run ID → ${TEST_RUN_ID}"
echo "============================================"
