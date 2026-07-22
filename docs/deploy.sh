#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="${1:-}"

if [[ -z "${TEST_NAME}" ]]; then
  echo "Fehler: Testname fehlt."
  echo "Beispiel: make deploy TEST=verfahren-a"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -o allexport
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +o allexport
fi

NAMESPACE="${NAMESPACE:-lup-k6}"
TEST_DIR="tests/${TEST_NAME}"
SCRIPT_FILE="${TEST_DIR}/test.js"
TESTRUN_FILE="${TEST_DIR}/testrun.yaml"
TESTDATAFILES_FILE="${TEST_DIR}/testdatafiles.txt"

CONFIGMAP_NAME="${CONFIGMAP_NAME:-${TEST_NAME}-script}"
TESTRUN_NAME="${TESTRUN_NAME:-${TEST_NAME}}"
TEST_RUN_ID="${TEST_RUN_ID:-${TEST_NAME}-$(date +%Y%m%d-%H%M%S)}"
POD_READY_TIMEOUT="${POD_READY_TIMEOUT:-90s}"

export NAMESPACE
export TEST_NAME
export TESTRUN_NAME
export CONFIGMAP_NAME
export TEST_RUN_ID

fail() {
  echo "Fehler: $1"
  exit 1
}

require_file() {
  local file="$1"
  local label="$2"

  [[ -f "${file}" ]] || fail "${label} nicht gefunden: ${file}"
}

[[ -d "${TEST_DIR}" ]] || fail "Testverzeichnis nicht gefunden: ${TEST_DIR}"
require_file "${SCRIPT_FILE}" "k6-Skript"
require_file "${TESTRUN_FILE}" "TestRun YAML"

CONFIGMAP_ARGS=()
CONFIGMAP_KEYS=()
CONFIGMAP_FILES=()

has_configmap_key() {
  local wanted="$1"
  local key

  for key in "${CONFIGMAP_KEYS[@]}"; do
    [[ "${key}" == "${wanted}" ]] && return 0
  done

  return 1
}

add_configmap_file() {
  local key="$1"
  local file="$2"

  [[ -n "${key}" ]] || fail "Leerer ConfigMap-Dateiname in ${TESTDATAFILES_FILE}"
  [[ -f "${file}" ]] || fail "Datei fuer ConfigMap nicht gefunden: ${file}"

  if has_configmap_key "${key}"; then
    echo "Doppelter ConfigMap-Dateiname: ${key}"
    echo "Nutze in testdatafiles.txt das Format zielname=pfad/zur/datei.json."
    exit 1
  fi

  CONFIGMAP_KEYS+=("${key}")
  CONFIGMAP_FILES+=("${key} <= ${file}")
  CONFIGMAP_ARGS+=(--from-file="${key}=${file}")
}

add_configmap_file "test.js" "${SCRIPT_FILE}"

if [[ -f "${TESTDATAFILES_FILE}" ]]; then
  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line="${raw_line%%#*}"
    line="$(echo "${line}" | xargs)"

    [[ -z "${line}" ]] && continue

    if [[ "${line}" == *"="* ]]; then
      key="${line%%=*}"
      file="${line#*=}"
    else
      file="${line}"
      key="$(basename "${file}")"
    fi

    key="$(echo "${key}" | xargs)"
    file="$(echo "${file}" | xargs)"

    add_configmap_file "${key}" "${file}"
  done < "${TESTDATAFILES_FILE}"
fi

echo "============================================================"
echo " k6 Test Deployment"
echo "============================================================"
echo "Namespace:       ${NAMESPACE}"
echo "Test:            ${TEST_NAME}"
echo "TestRun:         ${TESTRUN_NAME}"
echo "Test Run ID:     ${TEST_RUN_ID}"
echo "ConfigMap:       ${CONFIGMAP_NAME}"
echo "k6 Script:       ${SCRIPT_FILE}"
echo "TestRun YAML:    ${TESTRUN_FILE}"
echo "Testdatenliste:  ${TESTDATAFILES_FILE}"
echo ""
echo "Dateien in der ConfigMap:"
for entry in "${CONFIGMAP_FILES[@]}"; do
  echo "  - ${entry}"
done
echo ""

echo "[1/4] ConfigMap mit k6-Skript und expliziten Testdaten anwenden"
kubectl create configmap "${CONFIGMAP_NAME}" \
  "${CONFIGMAP_ARGS[@]}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[2/4] Vorherigen TestRun loeschen, falls vorhanden"
kubectl delete testrun "${TESTRUN_NAME}" \
  --namespace="${NAMESPACE}" \
  --ignore-not-found=true

echo "[3/4] Neuen TestRun anwenden"
envsubst < "${TESTRUN_FILE}" | kubectl apply -f -

echo "[4/4] Pod-Start pruefen"
sleep 5
kubectl wait pod \
  -l "k6_cr=${TESTRUN_NAME}" \
  --namespace="${NAMESPACE}" \
  --for=condition=Ready \
  --timeout="${POD_READY_TIMEOUT}" 2>/dev/null || true

echo ""
echo "Aktueller TestRun:"
kubectl get testrun "${TESTRUN_NAME}" \
  --namespace="${NAMESPACE}" \
  -o wide 2>/dev/null || echo "  TestRun noch nicht sichtbar oder CRD-Ausgabe nicht verfuegbar."

echo ""
echo "Aktuelle Pods fuer diesen TestRun:"
kubectl get pods \
  --namespace="${NAMESPACE}" \
  -l "k6_cr=${TESTRUN_NAME}" \
  -o wide 2>/dev/null || echo "  Noch keine Pods fuer Label k6_cr=${TESTRUN_NAME} gefunden."

echo ""
echo "Logs verfolgen:"
echo "  kubectl logs -f -l k6_cr=${TESTRUN_NAME} -n ${NAMESPACE} --all-containers=true"
echo ""
echo "Einzelne Pod-Logs anzeigen:"
echo "  kubectl get pods -n ${NAMESPACE} -l k6_cr=${TESTRUN_NAME}"
echo "  kubectl logs -f <pod-name> -n ${NAMESPACE}"
echo ""
echo "Status pruefen:"
echo "  kubectl get testrun ${TESTRUN_NAME} -n ${NAMESPACE} -o yaml"
echo "  kubectl describe testrun ${TESTRUN_NAME} -n ${NAMESPACE}"
echo ""
echo "Initializer-Probleme analysieren:"
echo "  kubectl describe pod -n ${NAMESPACE} -l k6_cr=${TESTRUN_NAME}"
echo "  kubectl logs -n ${NAMESPACE} -l k6_cr=${TESTRUN_NAME} --all-containers=true"
echo ""
echo "Aufraeumen:"
echo "  kubectl delete testrun ${TESTRUN_NAME} -n ${NAMESPACE} --ignore-not-found=true"
echo ""
echo "Grafana/Prometheus Filter:"
echo "  test_run_id = ${TEST_RUN_ID}"
echo "============================================================"
