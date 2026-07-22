# k6 Test: verfahren-a

## Ziel

Dieser Test prueft den API-Flow fuer Verfahren A.

## Testobjekt

| Wert | Beschreibung |
| --- | --- |
| System | Verfahren A |
| Namespace | lup-k6 |
| Basis-URL | wird ueber `BASE_URL` gesetzt |
| Ausfuehrung | k6 Operator ueber `TestRun` |

## Ablauf

1. Login ausfuehren
2. Testdaten laden
3. Fachlichen API-Flow ausfuehren
4. Antworten validieren
5. Metriken an Prometheus/Grafana uebergeben

## Dateien

| Datei | Zweck |
| --- | --- |
| `README.md` | Beschreibung dieses Tests |
| `test.js` | k6-Testskript |
| `testrun.yaml` | k6 Operator `TestRun` |
| `testdatafiles.txt` | Liste der zusaetzlich benoetigten Testdaten |
| `data/` | testspezifische Testdaten |

## Testdaten

Zusatzdateien werden nur geladen, wenn sie in `testdatafiles.txt` stehen.

Beispiel:

```text
shared/data/betriebsformen.json
tests/verfahren-a/data/verfahren-a-daten.json
```

Im k6-Skript koennen diese Dateien dann so geladen werden:

```javascript
const betriebsformen = JSON.parse(open('./betriebsformen.json'));
```

Wenn der Test keine Zusatzdaten benoetigt, kann `testdatafiles.txt` entfallen.

## Make-Befehle

Alle verfuegbaren Tests anzeigen:

```bash
make list
```

Details zu diesem Test anzeigen:

```bash
make info TEST=verfahren-a
```

TestRun-Manifest validieren:

```bash
make validate TEST=verfahren-a
```

Test starten:

```bash
make deploy TEST=verfahren-a
```

Logs verfolgen:

```bash
make logs TEST=verfahren-a
```

Status aller TestRuns und Pods anzeigen:

```bash
make status
```

TestRun loeschen:

```bash
make clean TEST=verfahren-a
```

## Erwartete Ausgabe nach dem Start

Nach `make deploy TEST=verfahren-a` zeigt das Deploy-Skript unter anderem:

- Namespace
- Testname
- TestRun-Name
- Test Run ID
- ConfigMap-Name
- geladene Dateien in der ConfigMap
- aktuellen TestRun
- laufende Pods
- Log-Befehle
- Diagnosebefehle fuer Initializer-Probleme

## Erfolgskennzahlen

| Metrik | Erwartung |
| --- | --- |
| `checks` | > 95 % |
| `http_req_failed` | < 5 % |
| `journey_duration p95` | < 8000 ms |

## Logs

Live-Logs:

```bash
make logs TEST=verfahren-a
```

Direkt mit `kubectl`:

```bash
kubectl logs -f -l k6_cr=verfahren-a -n lup-k6 --all-containers=true
```

## Troubleshooting

TestRun anzeigen:

```bash
kubectl get testrun verfahren-a -n lup-k6 -o yaml
```

TestRun beschreiben:

```bash
kubectl describe testrun verfahren-a -n lup-k6
```

Pods anzeigen:

```bash
kubectl get pods -n lup-k6 -l k6_cr=verfahren-a
```

Pod beschreiben:

```bash
kubectl describe pod -n lup-k6 -l k6_cr=verfahren-a
```

Logs anzeigen:

```bash
kubectl logs -n lup-k6 -l k6_cr=verfahren-a --all-containers=true
```

## Hinweise

- `test.js` wird immer in die ConfigMap aufgenommen.
- Zusatzdateien werden nur ueber `testdatafiles.txt` geladen.
- RBAC gehoert nicht in `testdatafiles.txt`.
- Zertifikate gehoeren normalerweise nicht in die Test-ConfigMap.
- Private Keys duerfen nicht unverschluesselt ins Repository.
- Sensible Werte muessen ueber Secrets oder Umgebungsvariablen bereitgestellt werden.
