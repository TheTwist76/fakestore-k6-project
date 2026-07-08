# FakeStore k6 HTTP Premium Demo

## Ziel

Professionelles Showcase-Beispiel für **k6 HTTP/API Load Testing** gegen die öffentliche **FakeStoreAPI**.
Ergänzt den Browser-basierten SauceDemo-Test um ein klassisches API-/Backend-Lasttest-Szenario.

---

## Architektur

```
┌─────────────────────────────────────────────────────────┐
│  deploy.sh                                              │
│    └─► kubectl apply ConfigMap + TestRun                │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│  Kubernetes (Namespace: k6-testing)                     │
│                                                         │
│  k6-Operator                                            │
│    └─► TestRun (parallelism: 2)                         │
│          ├─ Pod 1: grafana/k6  ──┐                      │
│          └─ Pod 2: grafana/k6  ──┤► FakeStoreAPI        │
└──────────────────────────────────┼──────────────────────┘
                                   │ Prometheus Remote Write
                                   ▼
┌─────────────────────────────────────────────────────────┐
│  Prometheus  ──►  Grafana Dashboard                     │
└─────────────────────────────────────────────────────────┘
```

---

## Lastprofil (Ramping)

| Phase       | Dauer | VUs           |
|-------------|-------|---------------|
| Ramp-up     | 1 min | 0 → MAX_VUS   |
| Steady Load | 3 min | MAX_VUS (100) |
| Ramp-down   | 1 min | MAX_VUS → 0   |

---

## API-Flow (6 Schritte)

```
1. GET  /products              → Produktliste laden
2. GET  /products/categories   → Kategorien laden
3. GET  /products/{id}         → Produktdetails laden
4. POST /auth/login            → Login durchführen
5. GET  /carts                 → Warenkörbe abrufen
6. POST /carts                 → Warenkorb anlegen (Checkout-Simulation)
```

---

## Enthaltene Dateien

| Datei | Beschreibung |
|-------|--------------|
| `fakestore-premium.js` | k6-Testskript – **einzige zu bearbeitende Datei** |
| `k8s/fakestore-premium-configmap.yaml` | Nur Referenz – wird vom deploy.sh automatisch aus der JS-Datei generiert |
| `k8s/fakestore-premium-testrun.yaml` | k6-Operator TestRun CRD (normaler Lauf) |
| `k8s/fakestore-badrun-testrun.yaml` | TestRun für Bad-Run-Demo (falsche Credentials) |
| `Grafana/FakeStore k6 HTTP Premium Dashboard-*.json` | Grafana Dashboard |
| `grafana/alerts/fakestore-k6-alerts.yaml` | Grafana Alert Rules (Provisioning) |
| `deploy.sh` | Deployment-Skript (generiert ConfigMap + startet TestRun) |
| `demo-badrun.sh` | Demo-Skript: Startet einen bewusst fehlerhaften Testlauf |

---

## Quick Demo

### Lokal (Einzelner Lauf, 5 VUs)

```bash
k6 run fakestore-premium.js
```

### Lokal – detaillierte Ausgabe

```bash
RUN_MODE=local SUMMARY_MODE=detailed TEST_VUS=10 k6 run fakestore-premium.js
```

### Kubernetes-Deployment

```bash
./deploy.sh
```

Das Skript:
1. Erstellt den Namespace `k6-testing` (falls nicht vorhanden)
2. **Generiert die ConfigMap direkt aus `fakestore-premium.js`** — kein manuelles Synchronisieren nötig
3. Löscht einen alten TestRun (falls vorhanden)
4. Startet einen neuen TestRun mit eindeutiger **Test Run ID** (Timestamp)
5. Wartet auf Pod-Start und zeigt Logs-Hinweis

> **Workflow:** Nur `fakestore-premium.js` bearbeiten, dann `./deploy.sh` ausführen — fertig.

---

## Erwartete Ergebnisse

| Metrik | Erwarteter Wert |
|--------|----------------|
| Login Success Rate | ~100 % |
| Checkout Sim. OK | ~100 % |
| API Error Rate | < 5 % |
| Journey P95 | < 8 000 ms |
| Journey Avg | 500 – 2 000 ms |

---

## Grafana Dashboard

Nach dem Deployment im Grafana-Dashboard nach der **Test Run ID** filtern (wird beim Deploy ausgegeben).

Dashboard enthält (5 Sektionen):

| Sektion | Panels |
|---------|--------|
| **Test Overview** | Completed / Failed Journeys, Login & Checkout Success Rate |
| **Performance KPIs** | Journey Avg / P95 / P99, API Error Rate |
| **Load & Latency** | VUs über Zeit, HTTP Request Rate, API Error Rate per Step, API Step Durations |
| **Infrastructure** | Runner CPU & Memory (gesamt + pro Pod), Active Pods |
| **API Step Performance** | Tabelle: Min / Avg / P95 / P99 / Max pro Step |

---

## Logging

Das Skript gibt strukturierte Logs aus, sichtbar via `kubectl logs`:

```bash
kubectl logs -f -l k6_cr=fakestore-premium -n k6-testing
```

**Beispiel-Ausgabe:**
```
 FakeStore k6 HTTP Test – gestartet
 Run ID  : fakestore-20260417-143022
 Max VUs : 100
 Stages  : 1m Ramp-up → 3m Steady → 1m Ramp-down
[VU 1][iter 0] Journey START
[VU 1][iter 0] Journey OK  1243ms  [products_list:31ms categories:39ms login:245ms ...]
[VU 3][iter 1] FAIL  step=login  status=401  duration=312ms  body="..."
[VU 3][iter 1] Journey FAILED  total=789ms
```

| Log-Level | Gesetzt via | Inhalt |
|-----------|-------------|--------|
| `info` (Standard) | — | Journey Start/Ende + alle Fehler |
| `debug` | `LOG_LEVEL=debug` | zusätzlich jeder einzelne Step-OK |

> Hinweis: k6 ergänzt jeden Eintrag automatisch mit `source=console` — das ist normales k6-Verhalten.

---

---

## Grafana Annotations (optional)

Das Skript kann automatisch **Annotationen** im Grafana-Dashboard erzeugen — ein farbiger Bereich markiert die gesamte Testlaufzeit.

**Konfiguration** in `k8s/fakestore-premium-testrun.yaml`:

```yaml
- name: GRAFANA_URL
  value: "http://grafana.monitoring:3000"   # Grafana-URL eintragen
- name: GRAFANA_TOKEN
  value: "glsa_xxxx..."                     # Service Account Token
```

Ohne Konfiguration (leere Werte) werden die Annotations-Aufrufe still übersprungen.

---

## Grafana Alert Rules

Fertige Alert-Regeln liegen unter `grafana/alerts/fakestore-k6-alerts.yaml`.

**Installation via Grafana Provisioning:**

```bash
# Datasource-UID ermitteln: Grafana → Configuration → Data Sources → Prometheus
# UID in die YAML-Datei einsetzen (${PROMETHEUS_DS_UID} ersetzen)
sed -i 's/${PROMETHEUS_DS_UID}/DEINE_UID/g' grafana/alerts/fakestore-k6-alerts.yaml

# Als ConfigMap in Grafana mounten oder in Helm-Values unter provisioning.alerting eintragen
```

| Alert | Schwellwert | Severity |
|-------|-------------|----------|
| API Error Rate | > 5 % | warning |
| Journey P95 | > 8 000 ms | warning |
| Login Success Rate | < 95 % | critical |
| Checkout Success Rate | < 95 % | warning |

---

## Bad-Run Demo

Demonstriert wie ein **fehlerhafter Testlauf** im Dashboard aussieht (0 % Login Success Rate, hohe Fehlerrate):

```bash
./demo-badrun.sh
```

Der Bad Run verwendet bewusst falsche Credentials (`wrong_user` / `wrong_password`).
Die Test Run ID enthält `BADRUN-` — im Dashboard sofort als Demo-Run erkennbar.

**Erwartetes Ergebnis im Dashboard:**
- Login Success Rate → 0 %
- API Error Rate → hoch
- Failed Journeys → steigt kontinuierlich

Nach der Demo normalen Lauf starten:

```bash
./deploy.sh
```

---

## Hinweise

- Default-Credentials sind Demo-Credentials von FakeStoreAPI.
  Falls die API sie ändert: `USERNAME` und `PASSWORD` per Env Vars überschreiben.
- `envsubst` muss auf dem System installiert sein (Standard auf Linux/macOS).
