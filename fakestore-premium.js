/**
 * ============================================================
 * k6 HTTP/API Test: FakeStore Premium Demo
 * ============================================================
 *
 * TESTZIEL
 * ------------------------------------------------------------
 * Dieses Skript demonstriert einen professionell strukturierten
 * HTTP-/API-Lasttest gegen FakeStoreAPI.
 *
 * Geprüfte API-Flows:
 * 1. Produktliste laden
 * 2. Kategorien laden
 * 3. Produktdetails laden
 * 4. Login durchführen
 * 5. Warenkörbe abrufen
 * 6. Warenkorb anlegen (Checkout-Simulation)
 *
 * LAST-PROFIL (Ramping)
 * ------------------------------------------------------------
 * Phase 1 – Ramp-up:   1 min  → 0 bis MAX_VUS
 * Phase 2 – Steady:    3 min  → MAX_VUS konstant
 * Phase 3 – Ramp-down: 1 min  → MAX_VUS bis 0
 * Gesamt:              5 min
 *
 * HINWEIS ZU LOGIN-CREDENTIALS
 * ------------------------------------------------------------
 * Die Default-Credentials basieren auf häufig verwendeten
 * Demo-Zugangsdaten für FakeStoreAPI. Wenn sich die API ändert,
 * bitte USERNAME und PASSWORD per Env Vars überschreiben.
 * ============================================================
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const TEST_RUN_ID = __ENV.TEST_RUN_ID || 'local';
const RUN_MODE = (__ENV.RUN_MODE || 'local').toLowerCase();
const SUMMARY_MODE = (__ENV.SUMMARY_MODE || (RUN_MODE === 'cluster' ? 'compact' : 'detailed')).toLowerCase();
// LOG_LEVEL=info  → Journey-Start/Ende + Fehler (Standard)
// LOG_LEVEL=debug → zusätzlich jeder Step
const LOG_LEVEL = (__ENV.LOG_LEVEL || 'info').toLowerCase();

const BASE_URL  = __ENV.BASE_URL  || 'https://fakestoreapi.com';
const USERNAME  = __ENV.USERNAME  || 'mor_2314';
const PASSWORD  = __ENV.PASSWORD  || '83r5^_';

// Optional: Grafana Annotations (leer lassen → deaktiviert)
const GRAFANA_URL   = __ENV.GRAFANA_URL   || '';
const GRAFANA_TOKEN = __ENV.GRAFANA_TOKEN || '';

const THINK_TIME = Number(__ENV.THINK_TIME || '0.2');
const PRODUCT_ID_MIN = Number(__ENV.PRODUCT_ID_MIN || '1');
const PRODUCT_ID_MAX = Number(__ENV.PRODUCT_ID_MAX || '20');
const MAX_VUS = Number(__ENV.TEST_VUS || '20');

function randomProductId() {
  return Math.floor(Math.random() * (PRODUCT_ID_MAX - PRODUCT_ID_MIN + 1)) + PRODUCT_ID_MIN;
}

// --- Custom Metrics ---
const apiProductsListDuration = new Trend('api_products_list_duration', true);
const apiCategoriesDuration = new Trend('api_categories_duration', true);
const apiProductDetailDuration = new Trend('api_product_detail_duration', true);
const apiLoginDuration = new Trend('api_login_duration', true);
const apiCartsDuration = new Trend('api_carts_duration', true);
const apiCartCreateDuration = new Trend('api_cart_create_duration', true);
const journeyDuration = new Trend('journey_duration', true);

const loginSuccessRate = new Rate('login_success_rate');
const checkoutSimSuccessRate = new Rate('checkout_sim_success_rate');
const apiErrorRate = new Rate('api_error_rate');

const completedJourneys = new Counter('completed_journeys');
const failedJourneys = new Counter('failed_journeys');

const commonTags = {
  app: 'fakestore',
  test_type: 'http',
  journey: 'api_shop_flow',
};

// --- Options (Ramping Load Profile) ---
export const options = {
  scenarios: {
    fakestore_http_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: MAX_VUS },   // Ramp-up
        { duration: '3m', target: MAX_VUS },   // Steady load
        { duration: '1m', target: 0 },         // Ramp-down
      ],
      gracefulRampDown: '30s',
      tags: {
        ...commonTags,
        run_mode: RUN_MODE,
      },
    },
  },
  thresholds: {
    checks: ['rate>0.95'],
    api_error_rate: ['rate<0.05'],
    login_success_rate: ['rate>0.95'],
    checkout_sim_success_rate: ['rate>0.95'],

    api_products_list_duration: ['p(95)<1500'],
    api_categories_duration: ['p(95)<1200'],
    api_product_detail_duration: ['p(95)<1500'],
    api_login_duration: ['p(95)<2000'],
    api_carts_duration: ['p(95)<1500'],
    api_cart_create_duration: ['p(95)<2000'],
    journey_duration: ['p(95)<8000'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)'],
};

// --- Grafana Annotations ---
function grafanaAnnotation(payload) {
  if (!GRAFANA_URL || !GRAFANA_TOKEN) return null;
  try {
    const res = http.post(
      `${GRAFANA_URL}/api/annotations`,
      JSON.stringify(payload),
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${GRAFANA_TOKEN}`,
        },
        timeout: '5s',
        tags: { type: 'grafana_annotation' },
      }
    );
    if (res.status === 200) {
      console.log(`Annotation erstellt (id=${res.json('id')}): ${payload.text}`);
      return res.json('id');
    }
    console.warn(`Annotation fehlgeschlagen: HTTP ${res.status}`);
  } catch (e) {
    console.warn(`Annotation Fehler: ${e.message}`);
  }
  return null;
}

function grafanaPatchAnnotation(id, payload) {
  if (!GRAFANA_URL || !GRAFANA_TOKEN || !id) return;
  try {
    http.patch(
      `${GRAFANA_URL}/api/annotations/${id}`,
      JSON.stringify(payload),
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${GRAFANA_TOKEN}`,
        },
        timeout: '5s',
        tags: { type: 'grafana_annotation' },
      }
    );
  } catch (e) {
    console.warn(`Annotation PATCH Fehler: ${e.message}`);
  }
}

// --- Logging ---
function ctx() {
  return `[VU ${__VU}][iter ${__ITER}]`;
}

function logStep(step, durationMs, ok, res) {
  if (!ok) {
    const body = res && res.body ? res.body.substring(0, 120) : '-';
    const status = res ? res.status : '?';
    console.warn(`${ctx()} FAIL  step=${step}  status=${status}  duration=${durationMs}ms  body="${body}"`);
  } else if (LOG_LEVEL === 'debug') {
    console.log(`${ctx()} OK    step=${step}  status=${res ? res.status : '?'}  duration=${durationMs}ms`);
  }
}

// --- Helpers ---
function nowMs() {
  return Date.now();
}

function metricTags(extra = {}) {
  return {
    ...commonTags,
    run_mode: RUN_MODE,
    test_run_id: TEST_RUN_ID,
    ...extra,
  };
}

function recordTrend(metric, duration, extraTags = {}) {
  metric.add(duration, metricTags(extraTags));
}

function formatNumber(value) {
  if (value === 'n/a' || value === undefined || value === null) return 'n/a';
  return Number(value).toFixed(2);
}

function formatPercent(value) {
  if (value === 'n/a' || value === undefined || value === null) return 'n/a';
  return `${(Number(value) * 100).toFixed(2)} %`;
}

// --- Setup (einmalig beim Teststart) ---
export function setup() {
  const startTime = Date.now();
  const line = '='.repeat(52);
  console.log(line);
  console.log(' FakeStore k6 HTTP Test – gestartet');
  console.log(line);
  console.log(` Run ID      : ${TEST_RUN_ID}`);
  console.log(` Base URL    : ${BASE_URL}`);
  console.log(` Mode        : ${RUN_MODE}`);
  console.log(` Max VUs     : ${MAX_VUS}`);
  console.log(` Stages      : 1m Ramp-up → 3m Steady → 1m Ramp-down`);
  console.log(` LogLevel    : ${LOG_LEVEL}`);
  console.log(` Annotations : ${GRAFANA_URL ? 'aktiviert (' + GRAFANA_URL + ')' : 'deaktiviert'}`);
  console.log(line);

  // Grafana: Region-Annotation starten (timeEnd wird in teardown gesetzt)
  const annotationId = grafanaAnnotation({
    text: `▶ k6 Test gestartet: ${TEST_RUN_ID}`,
    tags: ['k6', 'fakestore', 'test-start'],
    time: startTime,
  });

  return { startTime, annotationId };
}

// --- Teardown (einmalig nach Testende) ---
export function teardown(data) {
  const endTime = Date.now();
  const durationMin = data && data.startTime
    ? Math.round((endTime - data.startTime) / 1000 / 60 * 10) / 10
    : '?';

  console.log(`Test beendet. Gesamtdauer: ~${durationMin} min`);

  if (data && data.annotationId) {
    // Start-Annotation zur Region erweitern (zeigt farbigen Bereich im Chart)
    grafanaPatchAnnotation(data.annotationId, {
      text:    `k6 Test: ${TEST_RUN_ID}  (${durationMin} min)`,
      tags:    ['k6', 'fakestore', 'test-region'],
      time:    data.startTime,
      timeEnd: endTime,
    });
  }

  // Zusätzliche Ende-Annotation als Markierungslinie
  grafanaAnnotation({
    text: `⏹ k6 Test beendet: ${TEST_RUN_ID}`,
    tags: ['k6', 'fakestore', 'test-end'],
    time: endTime,
  });
}

// --- Main Test Function ---
export default function () {
  const journeyStart = nowMs();
  let journeyOk = true;
  let productsOk, categoriesOk, detailOk, loginOk, cartsOk, cartCreateOk;
  let productId;
  const durations = {};

  console.log(`${ctx()} Journey START`);

  try {
    group('browse', () => {
      let t, dur;

      t = nowMs();
      const productsRes = http.get(`${BASE_URL}/products`, {
        tags: metricTags({ flow: 'browse', step: 'products_list', endpoint: '/products' }),
      });
      dur = nowMs() - t;
      durations.products_list = dur;
      recordTrend(apiProductsListDuration, dur, { flow: 'browse', step: 'products_list' });
      productsOk = check(productsRes, {
        'products list status is 200': (r) => r.status === 200,
        'products list is array': (r) => Array.isArray(r.json()),
        'products list has items': (r) => Array.isArray(r.json()) && r.json().length > 0,
      }, metricTags({ flow: 'browse', step: 'products_list' }));
      apiErrorRate.add(!productsOk, metricTags({ flow: 'browse', step: 'products_list' }));
      logStep('products_list', dur, productsOk, productsRes);

      t = nowMs();
      const categoriesRes = http.get(`${BASE_URL}/products/categories`, {
        tags: metricTags({ flow: 'browse', step: 'categories', endpoint: '/products/categories' }),
      });
      dur = nowMs() - t;
      durations.categories = dur;
      recordTrend(apiCategoriesDuration, dur, { flow: 'browse', step: 'categories' });
      categoriesOk = check(categoriesRes, {
        'categories status is 200': (r) => r.status === 200,
        'categories is array': (r) => Array.isArray(r.json()),
        'categories has values': (r) => Array.isArray(r.json()) && r.json().length > 0,
      }, metricTags({ flow: 'browse', step: 'categories' }));
      apiErrorRate.add(!categoriesOk, metricTags({ flow: 'browse', step: 'categories' }));
      logStep('categories', dur, categoriesOk, categoriesRes);

      productId = randomProductId();
      t = nowMs();
      const detailRes = http.get(`${BASE_URL}/products/${productId}`, {
        tags: metricTags({ flow: 'browse', step: 'product_detail', endpoint: `/products/${productId}` }),
      });
      dur = nowMs() - t;
      durations.product_detail = dur;
      recordTrend(apiProductDetailDuration, dur, { flow: 'browse', step: 'product_detail' });
      detailOk = check(detailRes, {
        'product detail status is 200': (r) => r.status === 200,
        'product detail has id': (r) => !!r.json('id'),
        'product detail has title': (r) => !!r.json('title'),
      }, metricTags({ flow: 'browse', step: 'product_detail' }));
      apiErrorRate.add(!detailOk, metricTags({ flow: 'browse', step: 'product_detail' }));
      logStep(`product_detail[id=${productId}]`, dur, detailOk, detailRes);
    });

    group('auth', () => {
      const t = nowMs();
      const loginRes = http.post(
        `${BASE_URL}/auth/login`,
        JSON.stringify({ username: USERNAME, password: PASSWORD }),
        {
          headers: { 'Content-Type': 'application/json' },
          tags: metricTags({ flow: 'auth', step: 'login', endpoint: '/auth/login' }),
        }
      );
      const dur = nowMs() - t;
      durations.login = dur;
      recordTrend(apiLoginDuration, dur, { flow: 'auth', step: 'login' });
      loginOk = check(loginRes, {
        'login status is successful': (r) => r.status === 200 || r.status === 201,
        'login returns token': (r) => !!r.json('token'),
      }, metricTags({ flow: 'auth', step: 'login' }));
      loginSuccessRate.add(loginOk, metricTags({ flow: 'auth', step: 'login' }));
      apiErrorRate.add(!loginOk, metricTags({ flow: 'auth', step: 'login' }));
      logStep('login', dur, loginOk, loginRes);
    });

    group('cart', () => {
      let t, dur;

      t = nowMs();
      const cartsRes = http.get(`${BASE_URL}/carts`, {
        tags: metricTags({ flow: 'cart', step: 'carts_list', endpoint: '/carts' }),
      });
      dur = nowMs() - t;
      durations.carts_list = dur;
      recordTrend(apiCartsDuration, dur, { flow: 'cart', step: 'carts_list' });
      cartsOk = check(cartsRes, {
        'carts status is 200': (r) => r.status === 200,
        'carts is array': (r) => Array.isArray(r.json()),
      }, metricTags({ flow: 'cart', step: 'carts_list' }));
      apiErrorRate.add(!cartsOk, metricTags({ flow: 'cart', step: 'carts_list' }));
      logStep('carts_list', dur, cartsOk, cartsRes);

      t = nowMs();
      const cartCreateRes = http.post(
        `${BASE_URL}/carts`,
        JSON.stringify({
          userId: 1,
          date: new Date().toISOString().split('T')[0],
          products: [{ productId, quantity: 1 }],
        }),
        {
          headers: { 'Content-Type': 'application/json' },
          tags: metricTags({ flow: 'checkout', step: 'cart_create', endpoint: '/carts' }),
        }
      );
      dur = nowMs() - t;
      durations.cart_create = dur;
      recordTrend(apiCartCreateDuration, dur, { flow: 'checkout', step: 'cart_create' });
      cartCreateOk = check(cartCreateRes, {
        'cart create status is 200 or 201': (r) => r.status === 200 || r.status === 201,
        'cart create returns id': (r) => !!r.json('id'),
      }, metricTags({ flow: 'checkout', step: 'cart_create' }));
      checkoutSimSuccessRate.add(cartCreateOk, metricTags({ flow: 'checkout', step: 'cart_create' }));
      apiErrorRate.add(!cartCreateOk, metricTags({ flow: 'checkout', step: 'cart_create' }));
      logStep('cart_create', dur, cartCreateOk, cartCreateRes);
    });

    journeyOk = productsOk && categoriesOk && detailOk && loginOk && cartsOk && cartCreateOk;
  } catch (err) {
    journeyOk = false;
    apiErrorRate.add(true, metricTags({ flow: 'journey', step: 'exception' }));
    console.error(`${ctx()} EXCEPTION: ${err && err.message ? err.message : err}`);
  } finally {
    const totalJourney = nowMs() - journeyStart;
    journeyDuration.add(totalJourney, metricTags({
      flow: 'journey',
      step: 'full_journey',
      result: journeyOk ? 'success' : 'failed',
    }));

    if (journeyOk) {
      completedJourneys.add(1, metricTags({ flow: 'journey', step: 'full_journey' }));
      console.log(
        `${ctx()} Journey OK  ${totalJourney}ms` +
        `  [products_list:${durations.products_list}ms` +
        ` categories:${durations.categories}ms` +
        ` product_detail:${durations.product_detail}ms` +
        ` login:${durations.login}ms` +
        ` carts_list:${durations.carts_list}ms` +
        ` cart_create:${durations.cart_create}ms]`
      );
    } else {
      failedJourneys.add(1, metricTags({ flow: 'journey', step: 'full_journey' }));
      console.warn(`${ctx()} Journey FAILED  total=${totalJourney}ms`);
    }
  }

  sleep(THINK_TIME);
}

// --- Summary ---
export function handleSummary(data) {
  const getCount = (name) => data.metrics[name] && data.metrics[name].values ? data.metrics[name].values.count : 'n/a';
  const getRate = (name) => data.metrics[name] && data.metrics[name].values ? data.metrics[name].values.rate : 'n/a';
  const getAvg = (name) => data.metrics[name] && data.metrics[name].values ? data.metrics[name].values.avg : 'n/a';
  const getP95 = (name) => data.metrics[name] && data.metrics[name].values ? data.metrics[name].values['p(95)'] : 'n/a';
  const getP99 = (name) => data.metrics[name] && data.metrics[name].values ? data.metrics[name].values['p(99)'] : 'n/a';

  const line = '='.repeat(50);
  const sep  = '-'.repeat(50);

  const compactSummary = `
${line}
 FakeStore k6 HTTP Summary  |  Run: ${TEST_RUN_ID}
${line}
 Iterations:          ${getCount('iterations')}
 Checks pass rate:    ${formatPercent(getRate('checks'))}
 Login success rate:  ${formatPercent(getRate('login_success_rate'))}
 Checkout sim OK:     ${formatPercent(getRate('checkout_sim_success_rate'))}
 API error rate:      ${formatPercent(getRate('api_error_rate'))}
 Completed journeys:  ${getCount('completed_journeys')}
 Failed journeys:     ${getCount('failed_journeys')}
${sep}
 Journey avg:         ${formatNumber(getAvg('journey_duration'))} ms
 Journey p95:         ${formatNumber(getP95('journey_duration'))} ms
 Journey p99:         ${formatNumber(getP99('journey_duration'))} ms
${line}
`;

  const detailedSummary = compactSummary + `
 Step Durations (avg / p95)
${sep}
 Products List:       ${formatNumber(getAvg('api_products_list_duration'))} ms  /  ${formatNumber(getP95('api_products_list_duration'))} ms
 Categories:          ${formatNumber(getAvg('api_categories_duration'))} ms  /  ${formatNumber(getP95('api_categories_duration'))} ms
 Product Detail:      ${formatNumber(getAvg('api_product_detail_duration'))} ms  /  ${formatNumber(getP95('api_product_detail_duration'))} ms
 Login:               ${formatNumber(getAvg('api_login_duration'))} ms  /  ${formatNumber(getP95('api_login_duration'))} ms
 Carts List:          ${formatNumber(getAvg('api_carts_duration'))} ms  /  ${formatNumber(getP95('api_carts_duration'))} ms
 Cart Create:         ${formatNumber(getAvg('api_cart_create_duration'))} ms  /  ${formatNumber(getP95('api_cart_create_duration'))} ms
${line}
`;

  const output = SUMMARY_MODE === 'detailed' ? detailedSummary : compactSummary;
  return { stdout: output };
}
