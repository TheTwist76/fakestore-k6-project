#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NAMESPACE="k6-testing"
TESTRUN_NAME="fakestore-badrun"
export TEST_RUN_ID="BADRUN-$(date +%Y%m%d-%H%M%S)"

# .env laden, falls vorhanden
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -o allexport
  source "${SCRIPT_DIR}/.env"
  set +o allexport
fi

echo "============================================"
echo " FakeStore – BAD RUN Demo"
echo "============================================"
echo " Zweck:      Login-Fehler demonstrieren"
echo " Fehler:     Falsche Credentials"
echo " Test Run ID: ${TEST_RUN_ID}"
echo ""
echo " Im Grafana-Dashboard wird sichtbar:"
echo "   - Login Success Rate → 0 %"
echo "   - API Error Rate     → hoch"
echo "   - Failed Journeys    → steigt"
echo "============================================"
echo ""

echo "[1/3] Namespace sicherstellen"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[2/3] ConfigMap sicherstellen"
kubectl create configmap fakestore-premium-script \
  --from-file=fakestore-premium.js=fakestore-premium.js \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[3/3] Bad-Run TestRun starten"
kubectl delete testrun "${TESTRUN_NAME}" -n "${NAMESPACE}" --ignore-not-found=true
envsubst < k8s/fakestore-badrun-testrun.yaml | kubectl apply -f -

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
kubectl get pods -n "${NAMESPACE}" | grep "badrun" || true

echo ""
echo "Logs verfolgen:"
echo "  kubectl logs -f -l k6_cr=${TESTRUN_NAME} -n ${NAMESPACE}"
echo ""
echo "Grafana: Filter auf Test Run ID → ${TEST_RUN_ID}"
echo "============================================"
echo ""
echo "Nach der Demo normalen Run starten:"
echo "  ./deploy.sh"
echo "============================================"
