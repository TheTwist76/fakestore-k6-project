#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="${1:?Testname fehlt, z.B. verfahren-a}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

NAMESPACE="${NAMESPACE:-lup-k6}"
TEST_DIR="tests/${TEST_NAME}"
SCRIPT_FILE="${TEST_DIR}/test.js"
TESTRUN_FILE="${TEST_DIR}/testrun.yaml"

CONFIGMAP_NAME="${TEST_NAME}-script"
export TEST_NAME
export NAMESPACE
export CONFIGMAP_NAME
export TEST_RUN_ID="${TEST_NAME}-$(date +%Y%m%d-%H%M%S)"

if [[ ! -d "$TEST_DIR" ]]; then
  echo "Testverzeichnis nicht gefunden: ${TEST_DIR}"
  exit 1
fi

if [[ ! -f "$SCRIPT_FILE" ]]; then
  echo "k6-Skript nicht gefunden: ${SCRIPT_FILE}"
  exit 1
fi

if [[ ! -f "$TESTRUN_FILE" ]]; then
  echo "TestRun YAML nicht gefunden: ${TESTRUN_FILE}"
  exit 1
fi

echo "============================================"
echo " k6 Test Deployment"
echo "============================================"
echo "Namespace:    ${NAMESPACE}"
echo "Test:         ${TEST_NAME}"
echo "Test Run ID:  ${TEST_RUN_ID}"
echo "ConfigMap:    ${CONFIGMAP_NAME}"
echo ""

echo "[1/3] ConfigMap erzeugen oder aktualisieren"
kubectl create configmap "${CONFIGMAP_NAME}" \
  --from-file=test.js="${SCRIPT_FILE}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[2/3] Vorherigen TestRun löschen"
kubectl delete testrun "${TEST_NAME}" \
  -n "${NAMESPACE}" \
  --ignore-not-found=true

echo "[3/3] Neuen TestRun starten"
envsubst < "${TESTRUN_FILE}" | kubectl apply -f -

echo ""
echo "Logs:"
echo "  kubectl logs -f -l k6_cr=${TEST_NAME} -n ${NAMESPACE}"
echo ""
echo "Grafana Filter:"
echo "  test_run_id = ${TEST_RUN_ID}"
echo "============================================"
