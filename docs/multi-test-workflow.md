# Mehrere k6-Tests mit testdatafiles.txt

## Zielstruktur

```text
k6-tests/
├── Makefile
├── scripts/
│   └── deploy.sh
├── shared/
│   └── data/
│       └── betriebsformen.json
└── tests/
    ├── verfahren-a/
    │   ├── README.md
    │   ├── test.js
    │   ├── testdatafiles.txt
    │   └── testrun.yaml
    └── verfahren-b/
        ├── README.md
        ├── test.js
        └── testrun.yaml
```

`test.js` wird immer in die ConfigMap aufgenommen.
Zusatzdateien werden nur aufgenommen, wenn sie in `testdatafiles.txt` stehen.

## testdatafiles.txt

Ein Test mit gemeinsamen Testdaten:

```text
shared/data/betriebsformen.json
shared/data/users.json
tests/verfahren-a/data/login-daten.json
```

Ein Test ohne Testdaten braucht keine `testdatafiles.txt`.

Wenn zwei Dateien denselben Dateinamen haben, kann ein Zielname vergeben werden:

```text
betriebsformen.json=shared/data/betriebsformen.json
login-daten.json=tests/verfahren-a/data/login-daten.json
```

Im k6-Skript werden die Dateien ueber den Zielnamen geladen:

```javascript
const betriebsformen = JSON.parse(open('./betriebsformen.json'));
```

## Beispiel testrun.yaml

```yaml
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: ${TESTRUN_NAME}
  namespace: ${NAMESPACE}
spec:
  parallelism: 2
  script:
    configMap:
      name: ${CONFIGMAP_NAME}
      file: test.js
  runner:
    image: grafana/k6:latest
    env:
      - name: TEST_RUN_ID
        value: "${TEST_RUN_ID}"
      - name: RUN_MODE
        value: "cluster"
      - name: K6_OUT
        value: "experimental-prometheus-rw"
```

## Bedienung

Alle Tests anzeigen:

```bash
make list
```

Test starten:

```bash
make deploy TEST=verfahren-a
```

Logs verfolgen:

```bash
make logs TEST=verfahren-a
```

Status anzeigen:

```bash
make status
```

TestRun loeschen:

```bash
make clean TEST=verfahren-a
```

## Ausgabe nach dem Start

`scripts/deploy.sh` zeigt nach dem Start:

- Namespace
- Testname
- TestRun-Name
- Test Run ID
- ConfigMap-Name
- alle Dateien, die in die ConfigMap aufgenommen wurden
- aktuellen TestRun
- laufende Pods zum Label `k6_cr=<testrun-name>`
- konkrete `kubectl logs` Befehle
- Befehle fuer Status und Cleanup
