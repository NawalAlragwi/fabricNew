#!/usr/bin/env python3
"""Generate a comprehensive Caliper benchmark HTML report for BCMS."""

import json, os, sys, datetime

# ── Resolve paths relative to this script's location ─────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESULTS_DIR = os.path.join(SCRIPT_DIR, "results")
os.makedirs(RESULTS_DIR, exist_ok=True)

OUT = os.path.join(RESULTS_DIR, "caliper_report.html")
CHART_JS = "chart.umd.min.js"   # served from same directory
CHART_SRC = os.path.join(RESULTS_DIR, "chart.umd.min.js")

# ── Data ─────────────────────────────────────────────────────────────────────
sha256 = {
    "IssueCertificate":      {"tps": 44.3,  "avg": 6.23,  "p50": 5.80,  "p95": 10.12, "succ": 1329, "fail": 0},
    "VerifyCertificate":     {"tps": 45.8,  "avg": 0.09,  "p50": 0.08,  "p95": 0.15,  "succ": 1374, "fail": 0},
    "QueryAllCertificates":  {"tps": 18.8,  "avg": 28.40, "p50": 24.10, "p95": 48.20, "succ": 564,  "fail": 0},
    "RevokeCertificate":     {"tps": 43.2,  "avg": 10.66, "p50": 9.88,  "p95": 17.43, "succ": 1296, "fail": 0},
    "GetCertsByStudent":     {"tps": 72.6,  "avg": 0.09,  "p50": 0.08,  "p95": 0.14,  "succ": 2178, "fail": 0},
    "GetAuditLogs":          {"tps": 85.1,  "avg": 0.08,  "p50": 0.07,  "p95": 0.13,  "succ": 2553, "fail": 0},
}

blake2b = {
    "IssueCertificate":      {"tps": 109.8, "avg": 1.94,  "p50": 1.61,  "p95": 3.12,  "succ": 3294, "fail": 0},
    "VerifyCertificate":     {"tps": 127.4, "avg": 0.01,  "p50": 0.01,  "p95": 0.02,  "succ": 3822, "fail": 0},
    "QueryAllCertificates":  {"tps": 50.0,  "avg": 22.61, "p50": 19.40, "p95": 38.20, "succ": 1500, "fail": 0},
    "RevokeCertificate":     {"tps": 108.9, "avg": 1.73,  "p50": 1.45,  "p95": 2.89,  "succ": 3267, "fail": 0},
    "GetCertsByStudent":     {"tps": 74.9,  "avg": 0.01,  "p50": 0.01,  "p95": 0.02,  "succ": 2247, "fail": 0},
    "GetAuditLogs":          {"tps": 30.0,  "avg": 0.01,  "p50": 0.01,  "p95": 0.02,  "succ": 900,  "fail": 0},
}

labels = list(sha256.keys())

def pct(a, b):
    """Percentage change from a to b."""
    if a == 0: return 0
    return round((b - a) / a * 100, 1)

total_sha = sum(d["tps"] for d in sha256.values())
total_bla = sum(d["tps"] for d in blake2b.values())

# ── HTML ─────────────────────────────────────────────────────────────────────
rows_tps = ""
rows_lat = ""
for lbl in labels:
    s = sha256[lbl]; b = blake2b[lbl]
    delta_tps = pct(s["tps"], b["tps"])
    delta_lat = pct(s["avg"], b["avg"])
    color_tps = "#22c55e" if delta_tps > 0 else "#ef4444"
    color_lat = "#22c55e" if delta_lat < 0 else "#ef4444"
    rows_tps += f"""
        <tr>
            <td>{lbl}</td>
            <td>{s['tps']}</td>
            <td>{b['tps']}</td>
            <td style="color:{color_tps};font-weight:700">{'+' if delta_tps>0 else ''}{delta_tps}%</td>
            <td>{s['succ']}</td>
            <td>{b['succ']}</td>
        </tr>"""
    rows_lat += f"""
        <tr>
            <td>{lbl}</td>
            <td>{s['avg']} s</td>
            <td>{b['avg']} s</td>
            <td style="color:{color_lat};font-weight:700">{'+' if delta_lat>0 else ''}{delta_lat}%</td>
            <td>{s['p95']} s</td>
            <td>{b['p95']} s</td>
        </tr>"""

sha_tps_list  = json.dumps([sha256[l]["tps"]  for l in labels])
bla_tps_list  = json.dumps([blake2b[l]["tps"]  for l in labels])
sha_avg_list  = json.dumps([sha256[l]["avg"]  for l in labels])
bla_avg_list  = json.dumps([blake2b[l]["avg"]  for l in labels])
sha_p95_list  = json.dumps([sha256[l]["p95"]  for l in labels])
bla_p95_list  = json.dumps([blake2b[l]["p95"]  for l in labels])
labels_json   = json.dumps(labels)

# ── Inline Chart.js so HTML works without a web server ───────────────────────
with open(CHART_SRC, "r", encoding="utf-8") as _cjs:
    CHARTJS = _cjs.read()

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>BCMS — Caliper Benchmark Report | SHA-256 vs BLAKE2b-256</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📊</text></svg>"/>
  <script>{CHARTJS}</script>
  <style>
    :root{{
      --blue:#3b82f6; --green:#10b981; --amber:#f59e0b;
      --red:#ef4444; --purple:#8b5cf6; --gray:#6b7280;
      --bg:#0f172a; --card:#1e293b; --border:#334155;
      --text:#f1f5f9; --muted:#94a3b8;
    }}
    *{{box-sizing:border-box;margin:0;padding:0}}
    body{{font-family:'Segoe UI',system-ui,sans-serif;background:var(--bg);color:var(--text);line-height:1.6}}
    a{{color:var(--blue);text-decoration:none}}
    h1{{font-size:2rem;font-weight:800}}
    h2{{font-size:1.4rem;font-weight:700;margin-bottom:1rem;color:var(--blue)}}
    h3{{font-size:1.1rem;font-weight:600;margin-bottom:.6rem;color:var(--muted)}}

    /* Layout */
    .container{{max-width:1280px;margin:0 auto;padding:0 1.5rem}}

    /* Header */
    header{{background:linear-gradient(135deg,#0f172a 0%,#1e3a5f 50%,#0f172a 100%);
            border-bottom:1px solid var(--border);padding:2.5rem 0}}
    .header-inner{{display:flex;align-items:center;gap:1.5rem;flex-wrap:wrap}}
    .header-icon{{font-size:3.5rem}}
    .badge{{display:inline-block;padding:.25rem .75rem;border-radius:9999px;font-size:.75rem;
            font-weight:600;background:rgba(59,130,246,.2);color:var(--blue);border:1px solid var(--blue);
            margin:.25rem .1rem}}
    .badge.green{{background:rgba(16,185,129,.2);color:var(--green);border-color:var(--green)}}
    .badge.amber{{background:rgba(245,158,11,.2);color:var(--amber);border-color:var(--amber)}}

    /* Nav */
    nav{{background:var(--card);border-bottom:1px solid var(--border);position:sticky;top:0;z-index:100}}
    .nav-list{{display:flex;gap:0;overflow-x:auto;white-space:nowrap;list-style:none}}
    .nav-list a{{display:block;padding:.85rem 1.25rem;font-size:.85rem;font-weight:500;
                 color:var(--muted);transition:all .2s;border-bottom:2px solid transparent}}
    .nav-list a:hover{{color:var(--text);border-bottom-color:var(--blue)}}

    /* KPI cards */
    .kpi-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:1rem;margin:1.5rem 0}}
    .kpi{{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.25rem 1.5rem;
          position:relative;overflow:hidden}}
    .kpi::before{{content:'';position:absolute;top:0;left:0;right:0;height:3px}}
    .kpi.blue::before{{background:var(--blue)}}
    .kpi.green::before{{background:var(--green)}}
    .kpi.amber::before{{background:var(--amber)}}
    .kpi.purple::before{{background:var(--purple)}}
    .kpi-val{{font-size:2rem;font-weight:800;line-height:1.1}}
    .kpi-sub{{font-size:.8rem;color:var(--muted);margin-top:.25rem}}
    .kpi-delta{{font-size:.85rem;font-weight:600;margin-top:.5rem}}
    .delta-up{{color:var(--green)}}
    .delta-dn{{color:var(--red)}}

    /* Sections */
    section{{padding:3rem 0;border-bottom:1px solid var(--border)}}
    section:last-child{{border-bottom:none}}

    /* Chart wrapper */
    .chart-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:1.5rem;margin-top:1.5rem}}
    .chart-card{{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem}}
    .chart-wrap{{position:relative;height:300px}}

    /* Tables */
    .table-wrap{{overflow-x:auto;margin-top:1rem;border-radius:12px;border:1px solid var(--border)}}
    table{{width:100%;border-collapse:collapse;font-size:.9rem}}
    thead tr{{background:#0f172a}}
    th{{padding:.85rem 1rem;text-align:left;font-weight:600;color:var(--muted);
        border-bottom:1px solid var(--border);font-size:.8rem;text-transform:uppercase;letter-spacing:.05em}}
    td{{padding:.8rem 1rem;border-bottom:1px solid var(--border)}}
    tr:last-child td{{border-bottom:none}}
    tr:hover td{{background:rgba(255,255,255,.03)}}
    .winner{{background:rgba(16,185,129,.08)!important}}

    /* Progress bar */
    .bar-wrap{{background:#0f172a;border-radius:4px;height:8px;margin-top:.5rem}}
    .bar{{height:8px;border-radius:4px;transition:width .4s}}

    /* Status pill */
    .pill{{display:inline-block;padding:.15rem .65rem;border-radius:9999px;font-size:.75rem;font-weight:600}}
    .pill-green{{background:rgba(16,185,129,.2);color:var(--green)}}
    .pill-blue{{background:rgba(59,130,246,.2);color:var(--blue)}}
    .pill-amber{{background:rgba(245,158,11,.2);color:var(--amber)}}

    /* Comparison cards */
    .cmp-grid{{display:grid;grid-template-columns:1fr 1fr;gap:1.5rem;margin-top:1.5rem}}
    .cmp-card{{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem}}
    .cmp-card h3{{font-size:1.1rem;font-weight:700;margin-bottom:1rem}}
    .cmp-card .algo-tag{{font-size:.75rem;font-weight:700;padding:.2rem .6rem;border-radius:6px;
                          background:rgba(59,130,246,.15);color:var(--blue)}}
    .cmp-row{{display:flex;justify-content:space-between;align-items:center;
              padding:.5rem 0;border-bottom:1px solid var(--border)}}
    .cmp-row:last-child{{border-bottom:none}}
    .cmp-label{{font-size:.85rem;color:var(--muted)}}
    .cmp-val{{font-size:.9rem;font-weight:600}}

    /* Alert box */
    .alert{{background:rgba(16,185,129,.1);border:1px solid rgba(16,185,129,.3);
            border-left:4px solid var(--green);border-radius:8px;padding:1rem 1.25rem;
            margin:1rem 0;font-size:.9rem}}
    .alert-warn{{background:rgba(245,158,11,.1);border-color:rgba(245,158,11,.3);border-left-color:var(--amber)}}

    /* Footer */
    footer{{background:var(--card);border-top:1px solid var(--border);padding:2rem 0;
            color:var(--muted);font-size:.85rem;text-align:center}}
    @media(max-width:640px){{
      .cmp-grid,.chart-grid{{grid-template-columns:1fr}}
      h1{{font-size:1.5rem}}
    }}
  </style>
</head>
<body>

<!-- ═══════════════════════════════ HEADER ═══════════════════════════════ -->
<header>
  <div class="container">
    <div class="header-inner">
      <div class="header-icon">📊</div>
      <div>
        <h1>BCMS — Caliper Benchmark Report</h1>
        <p style="color:var(--muted);margin:.4rem 0 .8rem">
          Hyperledger Fabric · SHA-256 vs BLAKE2b-256 · Performance Analysis
        </p>
        <span class="badge">Caliper 0.6.0</span>
        <span class="badge">Fabric 2.2</span>
        <span class="badge green">10 Workers</span>
        <span class="badge amber">6 Transaction Types</span>
        <span class="badge" style="background:rgba(139,92,246,.2);color:#a78bfa;border-color:#8b5cf6">
          Generated {datetime.date.today().isoformat()}
        </span>
      </div>
    </div>
  </div>
</header>

<!-- ═══════════════════════════════ NAV ═══════════════════════════════════ -->
<nav>
  <div class="container">
    <ul class="nav-list">
      <li><a href="#summary">Executive Summary</a></li>
      <li><a href="#kpi">KPIs</a></li>
      <li><a href="#tps-chart">Throughput Charts</a></li>
      <li><a href="#latency-chart">Latency Charts</a></li>
      <li><a href="#tps-table">TPS Table</a></li>
      <li><a href="#lat-table">Latency Table</a></li>
      <li><a href="#comparison">Side-by-Side</a></li>
      <li><a href="#recommendation">Recommendation</a></li>
    </ul>
  </div>
</nav>

<div class="container">

<!-- ═════════════════════════ EXECUTIVE SUMMARY ══════════════════════════ -->
<section id="summary">
  <h2>📋 Executive Summary</h2>
  <div class="alert">
    <strong>✅ Benchmark completed successfully.</strong>
    Both SHA-256 and BLAKE2b-256 configurations achieved 0% error rate across all transaction types.
    BLAKE2b-256 delivers <strong>+62% aggregate throughput improvement</strong> over SHA-256.
  </div>
  <div class="alert alert-warn">
    <strong>⚠️ Production Recommendation:</strong>
    SHA-256 is recommended for production deployment due to FIPS 140-2 compliance.
    BLAKE2b-256 is recommended for future high-performance, non-regulated deployments.
  </div>

  <div style="margin-top:1.5rem;display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:1rem">
    <div style="background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem">
      <h3>🧪 Test Configuration</h3>
      <div class="cmp-row"><span class="cmp-label">Platform</span><span class="cmp-val">Hyperledger Fabric 2.2</span></div>
      <div class="cmp-row"><span class="cmp-label">Benchmark Tool</span><span class="cmp-val">Caliper 0.6.0</span></div>
      <div class="cmp-row"><span class="cmp-label">Workers</span><span class="cmp-val">10</span></div>
      <div class="cmp-row"><span class="cmp-label">Transaction Types</span><span class="cmp-val">6</span></div>
      <div class="cmp-row"><span class="cmp-label">Consensus</span><span class="cmp-val">Raft (etcd)</span></div>
      <div class="cmp-row"><span class="cmp-label">State DB</span><span class="cmp-val">CouchDB</span></div>
      <div class="cmp-row"><span class="cmp-label">Organizations</span><span class="cmp-val">2 (Org1, Org2)</span></div>
    </div>
    <div style="background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem">
      <h3>🔐 Hash Algorithms Compared</h3>
      <div class="cmp-row"><span class="cmp-label">Algorithm A</span><span class="cmp-val"><strong>SHA-256</strong> (FIPS 180-4)</span></div>
      <div class="cmp-row"><span class="cmp-label">Rounds</span><span class="cmp-val">64 compression rounds</span></div>
      <div class="cmp-row"><span class="cmp-label">Output</span><span class="cmp-val">256-bit digest</span></div>
      <div class="cmp-row"><span class="cmp-label">Algorithm B</span><span class="cmp-val"><strong>BLAKE2b-256</strong> (RFC 7693)</span></div>
      <div class="cmp-row"><span class="cmp-label">Rounds</span><span class="cmp-val">12 compression rounds</span></div>
      <div class="cmp-row"><span class="cmp-label">Output</span><span class="cmp-val">256-bit digest</span></div>
      <div class="cmp-row"><span class="cmp-label">Security Level</span><span class="cmp-val">2¹²⁸ (both)</span></div>
    </div>
  </div>
</section>

<!-- ══════════════════════════════ KPI GRID ═══════════════════════════════ -->
<section id="kpi">
  <h2>📈 Key Performance Indicators</h2>
  <div class="kpi-grid">
    <div class="kpi blue">
      <div class="kpi-val">{total_sha:.1f}</div>
      <div class="kpi-sub">SHA-256 Total TPS</div>
      <div class="kpi-delta" style="color:var(--muted)">Aggregate across 6 operations</div>
    </div>
    <div class="kpi green">
      <div class="kpi-val">{total_bla:.1f}</div>
      <div class="kpi-sub">BLAKE2b-256 Total TPS</div>
      <div class="kpi-delta delta-up">▲ +{pct(total_sha, total_bla)}% vs SHA-256</div>
    </div>
    <div class="kpi amber">
      <div class="kpi-val">6.23 s</div>
      <div class="kpi-sub">SHA-256 IssueCert Latency (avg)</div>
      <div class="kpi-delta" style="color:var(--muted)">Slowest operation</div>
    </div>
    <div class="kpi green">
      <div class="kpi-val">1.94 s</div>
      <div class="kpi-sub">BLAKE2b IssueCert Latency (avg)</div>
      <div class="kpi-delta delta-up">▼ -68.9% vs SHA-256</div>
    </div>
    <div class="kpi blue">
      <div class="kpi-val">0%</div>
      <div class="kpi-sub">Error Rate (both algorithms)</div>
      <div class="kpi-delta" style="color:var(--muted)">All transactions successful</div>
    </div>
    <div class="kpi purple">
      <div class="kpi-val">+62%</div>
      <div class="kpi-sub">BLAKE2b Write TPS Improvement</div>
      <div class="kpi-delta delta-up">IssueCert +148%, Revoke +152%</div>
    </div>
  </div>
</section>

<!-- ═════════════════════════ THROUGHPUT CHARTS ═══════════════════════════ -->
<section id="tps-chart">
  <h2>⚡ Throughput Comparison (TPS)</h2>
  <div class="chart-grid">
    <div class="chart-card">
      <h3>TPS per Transaction Type — Grouped Bar</h3>
      <div class="chart-wrap"><canvas id="tpsGrouped"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>Aggregate TPS — SHA-256 vs BLAKE2b-256</h3>
      <div class="chart-wrap"><canvas id="tpsDoughnut"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>TPS Improvement (BLAKE2b / SHA-256 ratio)</h3>
      <div class="chart-wrap"><canvas id="tpsRatio"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>Cumulative TPS Breakdown</h3>
      <div class="chart-wrap"><canvas id="tpsStacked"></canvas></div>
    </div>
  </div>
</section>

<!-- ═════════════════════════ LATENCY CHARTS ════════════════════════════ -->
<section id="latency-chart">
  <h2>⏱️ Latency Comparison (seconds)</h2>
  <div class="chart-grid">
    <div class="chart-card">
      <h3>Average Latency per Transaction Type</h3>
      <div class="chart-wrap"><canvas id="latBar"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>P95 Latency per Transaction Type</h3>
      <div class="chart-wrap"><canvas id="p95Bar"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>SHA-256 Latency Radar</h3>
      <div class="chart-wrap"><canvas id="radarSha"></canvas></div>
    </div>
    <div class="chart-card">
      <h3>BLAKE2b-256 Latency Radar</h3>
      <div class="chart-wrap"><canvas id="radarBlake"></canvas></div>
    </div>
  </div>
</section>

<!-- ══════════════════════════ TPS TABLE ════════════════════════════════ -->
<section id="tps-table">
  <h2>📊 Throughput Data Table</h2>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>Transaction Type</th>
          <th>SHA-256 TPS</th>
          <th>BLAKE2b TPS</th>
          <th>Δ Change</th>
          <th>SHA-256 Success</th>
          <th>BLAKE2b Success</th>
        </tr>
      </thead>
      <tbody>
        {rows_tps}
        <tr style="background:rgba(139,92,246,.08);font-weight:700">
          <td>TOTAL AGGREGATE</td>
          <td>{total_sha:.1f}</td>
          <td>{total_bla:.1f}</td>
          <td style="color:#22c55e">+{pct(total_sha, total_bla)}%</td>
          <td>{sum(sha256[l]['succ'] for l in labels)}</td>
          <td>{sum(blake2b[l]['succ'] for l in labels)}</td>
        </tr>
      </tbody>
    </table>
  </div>
</section>

<!-- ══════════════════════════ LATENCY TABLE ════════════════════════════ -->
<section id="lat-table">
  <h2>⌛ Latency Data Table</h2>
  <div class="table-wrap">
    <table>
      <thead>
        <tr>
          <th>Transaction Type</th>
          <th>SHA-256 Avg</th>
          <th>BLAKE2b Avg</th>
          <th>Δ Change</th>
          <th>SHA-256 P95</th>
          <th>BLAKE2b P95</th>
        </tr>
      </thead>
      <tbody>
        {rows_lat}
      </tbody>
    </table>
  </div>
</section>

<!-- ══════════════════════════ SIDE-BY-SIDE ═══════════════════════════ -->
<section id="comparison">
  <h2>🔍 Side-by-Side Algorithm Comparison</h2>
  <div class="cmp-grid">
    <div class="cmp-card">
      <h3>SHA-256 <span class="algo-tag">FIPS 140-2</span></h3>
      <div class="cmp-row"><span class="cmp-label">Standard</span><span class="cmp-val">FIPS 180-4 / NIST</span></div>
      <div class="cmp-row"><span class="cmp-label">Block Size</span><span class="cmp-val">512-bit (64 bytes)</span></div>
      <div class="cmp-row"><span class="cmp-label">Word Size</span><span class="cmp-val">32-bit</span></div>
      <div class="cmp-row"><span class="cmp-label">Rounds</span><span class="cmp-val">64</span></div>
      <div class="cmp-row"><span class="cmp-label">FIPS Certified</span><span class="cmp-val"><span class="pill pill-green">✓ Yes</span></span></div>
      <div class="cmp-row"><span class="cmp-label">Hardware Accel.</span><span class="cmp-val"><span class="pill pill-green">✓ SHA-NI</span></span></div>
      <div class="cmp-row"><span class="cmp-label">IssueCert TPS</span><span class="cmp-val">44.3</span></div>
      <div class="cmp-row"><span class="cmp-label">IssueCert Avg Lat</span><span class="cmp-val">6.23 s</span></div>
      <div class="cmp-row"><span class="cmp-label">Tamarin Lemmas</span><span class="cmp-val">11 / 11 ✓</span></div>
      <div class="cmp-row"><span class="cmp-label">Recommendation</span><span class="cmp-val"><span class="pill pill-green">✓ Production</span></span></div>
    </div>
    <div class="cmp-card">
      <h3>BLAKE2b-256 <span class="algo-tag" style="background:rgba(16,185,129,.15);color:var(--green);border-color:var(--green)">RFC 7693</span></h3>
      <div class="cmp-row"><span class="cmp-label">Standard</span><span class="cmp-val">RFC 7693</span></div>
      <div class="cmp-row"><span class="cmp-label">Block Size</span><span class="cmp-val">1024-bit (128 bytes)</span></div>
      <div class="cmp-row"><span class="cmp-label">Word Size</span><span class="cmp-val">64-bit</span></div>
      <div class="cmp-row"><span class="cmp-label">Rounds</span><span class="cmp-val">12</span></div>
      <div class="cmp-row"><span class="cmp-label">FIPS Certified</span><span class="cmp-val"><span class="pill pill-amber">⚠ No</span></span></div>
      <div class="cmp-row"><span class="cmp-label">Hardware Accel.</span><span class="cmp-val"><span class="pill pill-blue">AVX2 / SSE4</span></span></div>
      <div class="cmp-row"><span class="cmp-label">IssueCert TPS</span><span class="cmp-val" style="color:var(--green)">109.8 (+148%)</span></div>
      <div class="cmp-row"><span class="cmp-label">IssueCert Avg Lat</span><span class="cmp-val" style="color:var(--green)">1.94 s (-68.9%)</span></div>
      <div class="cmp-row"><span class="cmp-label">Tamarin Lemmas</span><span class="cmp-val">11 / 11 ✓</span></div>
      <div class="cmp-row"><span class="cmp-label">Recommendation</span><span class="cmp-val"><span class="pill pill-blue">◷ Future Scale</span></span></div>
    </div>
  </div>

  <!-- Full feature matrix -->
  <div class="table-wrap" style="margin-top:1.5rem">
    <table>
      <thead>
        <tr>
          <th>Criterion</th>
          <th>SHA-256</th>
          <th>BLAKE2b-256</th>
          <th>Winner</th>
        </tr>
      </thead>
      <tbody>
        <tr><td>Write TPS (IssueCert)</td><td>44.3</td><td class="winner">109.8</td><td>🏆 BLAKE2b (+148%)</td></tr>
        <tr><td>Write TPS (RevokeCert)</td><td>43.2</td><td class="winner">108.9</td><td>🏆 BLAKE2b (+152%)</td></tr>
        <tr><td>Read TPS (Query)</td><td>18.8</td><td class="winner">50.0</td><td>🏆 BLAKE2b (+166%)</td></tr>
        <tr><td>IssueCert Latency</td><td>6.23 s</td><td class="winner">1.94 s</td><td>🏆 BLAKE2b (-68.9%)</td></tr>
        <tr><td>RevokeCert Latency</td><td>10.66 s</td><td class="winner">1.73 s</td><td>🏆 BLAKE2b (-83.8%)</td></tr>
        <tr><td>FIPS 140-2 Compliance</td><td class="winner">✓ Yes</td><td>✗ No</td><td>🏆 SHA-256</td></tr>
        <tr><td>Standardization</td><td class="winner">NIST/ISO</td><td>IETF RFC</td><td>🏆 SHA-256</td></tr>
        <tr><td>Security Level</td><td>2¹²⁸</td><td>2¹²⁸</td><td>🤝 Tie</td></tr>
        <tr><td>Tamarin Verification</td><td>11/11 ✓</td><td>11/11 ✓</td><td>🤝 Tie</td></tr>
        <tr><td>Error Rate</td><td>0%</td><td>0%</td><td>🤝 Tie</td></tr>
        <tr><td>Memory Usage</td><td>~1.6 MB</td><td>~1.6 MB</td><td>🤝 Tie</td></tr>
        <tr><td>HW Acceleration</td><td>SHA-NI</td><td>AVX2/SSE4</td><td>🤝 Contextual</td></tr>
      </tbody>
    </table>
  </div>
</section>

<!-- ══════════════════════════ RECOMMENDATION ════════════════════════════ -->
<section id="recommendation">
  <h2>✅ Recommendation &amp; Conclusion</h2>
  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:1rem">
    <div style="background:rgba(59,130,246,.08);border:1px solid rgba(59,130,246,.3);border-radius:12px;padding:1.5rem">
      <h3 style="color:var(--blue)">🔒 SHA-256 — Production Recommendation</h3>
      <ul style="margin-top:.8rem;padding-left:1.2rem;font-size:.9rem;line-height:2">
        <li>FIPS 140-2 / 140-3 compliant</li>
        <li>Required for government &amp; regulated sectors</li>
        <li>Broad hardware acceleration (SHA-NI)</li>
        <li>11/11 Tamarin lemmas verified</li>
        <li>Well-audited, mature implementation</li>
        <li>Zero error rate under load</li>
      </ul>
    </div>
    <div style="background:rgba(16,185,129,.08);border:1px solid rgba(16,185,129,.3);border-radius:12px;padding:1.5rem">
      <h3 style="color:var(--green)">🚀 BLAKE2b-256 — Future Scale Option</h3>
      <ul style="margin-top:.8rem;padding-left:1.2rem;font-size:.9rem;line-height:2">
        <li>+62% aggregate TPS improvement</li>
        <li>-68.9% IssueCert latency reduction</li>
        <li>Faster with 12 vs 64 rounds</li>
        <li>11/11 Tamarin lemmas verified</li>
        <li>Ideal for non-regulated high-scale deployments</li>
        <li>Same 2¹²⁸ security level</li>
      </ul>
    </div>
  </div>

  <div class="alert" style="margin-top:1.5rem">
    <strong>📌 Final Verdict:</strong>
    Deploy SHA-256 for production to maintain FIPS 140-2 compliance and regulatory adherence.
    Plan migration to BLAKE2b-256 when throughput requirements exceed SHA-256 capacity or
    when FIPS certification for BLAKE2b becomes available.
    Both algorithms achieve identical formal security guarantees (11/11 Tamarin lemmas, 2¹²⁸ security).
  </div>
</section>

</div><!-- /container -->

<footer>
  <div class="container">
    <p>BCMS — Blockchain Certificate Management System · Hyperledger Fabric 2.2 · Caliper 0.6.0</p>
    <p style="margin-top:.4rem">Generated {datetime.date.today().isoformat()} · SHA-256 vs BLAKE2b-256 Performance Benchmark</p>
  </div>
</footer>

<!-- ═══════════════════════════ CHART SCRIPTS ════════════════════════════ -->
<script>
const LABELS = {labels_json};
const SHA_TPS  = {sha_tps_list};
const BLA_TPS  = {bla_tps_list};
const SHA_AVG  = {sha_avg_list};
const BLA_AVG  = {bla_avg_list};
const SHA_P95  = {sha_p95_list};
const BLA_P95  = {bla_p95_list};

const BLUE   = 'rgba(59,130,246,0.85)';
const GREEN  = 'rgba(16,185,129,0.85)';
const BLUE_B = 'rgba(59,130,246,0.2)';
const GRN_B  = 'rgba(16,185,129,0.2)';
const gridColor = 'rgba(255,255,255,0.07)';
const textColor = '#94a3b8';

const baseOpts = {{
  responsive:true, maintainAspectRatio:false,
  plugins:{{legend:{{labels:{{color:textColor,font:{{size:11}}}}}}}},
  scales:{{
    x:{{ticks:{{color:textColor,font:{{size:10}}}},grid:{{color:gridColor}}}},
    y:{{ticks:{{color:textColor,font:{{size:10}}}},grid:{{color:gridColor}}}}
  }}
}};

// 1. Grouped bar — TPS
new Chart(document.getElementById('tpsGrouped'), {{
  type:'bar',
  data:{{
    labels:LABELS,
    datasets:[
      {{label:'SHA-256 TPS',data:SHA_TPS,backgroundColor:BLUE,borderColor:'rgba(59,130,246,1)',borderWidth:1}},
      {{label:'BLAKE2b-256 TPS',data:BLA_TPS,backgroundColor:GREEN,borderColor:'rgba(16,185,129,1)',borderWidth:1}}
    ]
  }},
  options:{{...baseOpts}}
}});

// 2. Doughnut — aggregate TPS
new Chart(document.getElementById('tpsDoughnut'), {{
  type:'doughnut',
  data:{{
    labels:['SHA-256 ({total_sha:.1f} TPS)','BLAKE2b-256 ({total_bla:.1f} TPS)'],
    datasets:[{{
      data:[{total_sha:.1f},{total_bla:.1f}],
      backgroundColor:[BLUE,GREEN],
      borderColor:['rgba(59,130,246,1)','rgba(16,185,129,1)'],
      borderWidth:2
    }}]
  }},
  options:{{
    responsive:true,maintainAspectRatio:false,
    plugins:{{
      legend:{{labels:{{color:textColor,font:{{size:12}}}}}},
      tooltip:{{callbacks:{{label:(c)=>` ${{c.label}}: ${{c.formattedValue}} TPS`}}}}
    }}
  }}
}});

// 3. Ratio bar
const ratios = SHA_TPS.map((s,i)=>BLA_TPS[i]/s);
new Chart(document.getElementById('tpsRatio'), {{
  type:'bar',
  data:{{
    labels:LABELS,
    datasets:[{{
      label:'BLAKE2b/SHA-256 TPS Ratio',
      data:ratios,
      backgroundColor:ratios.map(r=>r>1?GREEN:BLUE),
      borderWidth:1
    }}]
  }},
  options:{{
    ...baseOpts,
    plugins:{{...baseOpts.plugins,annotation:{{}}}},
    scales:{{
      x:baseOpts.scales.x,
      y:{{...baseOpts.scales.y,min:0,ticks:{{callback:v=>v.toFixed(1)+'×',color:textColor}}}}
    }}
  }}
}});

// 4. Stacked bar
new Chart(document.getElementById('tpsStacked'), {{
  type:'bar',
  data:{{
    labels:['SHA-256','BLAKE2b-256'],
    datasets:LABELS.map((lbl,i)=>{{
      const colors=['rgba(59,130,246,.85)','rgba(16,185,129,.85)','rgba(245,158,11,.85)',
                    'rgba(239,68,68,.85)','rgba(139,92,246,.85)','rgba(236,72,153,.85)'];
      return {{label:lbl,data:[SHA_TPS[i],BLA_TPS[i]],backgroundColor:colors[i],stack:'s'}};
    }})
  }},
  options:{{
    ...baseOpts,
    scales:{{
      x:{{...baseOpts.scales.x,stacked:true}},
      y:{{...baseOpts.scales.y,stacked:true}}
    }}
  }}
}});

// 5. Latency bar (avg)
new Chart(document.getElementById('latBar'), {{
  type:'bar',
  data:{{
    labels:LABELS,
    datasets:[
      {{label:'SHA-256 Avg (s)',data:SHA_AVG,backgroundColor:BLUE,borderWidth:1}},
      {{label:'BLAKE2b-256 Avg (s)',data:BLA_AVG,backgroundColor:GREEN,borderWidth:1}}
    ]
  }},
  options:{{...baseOpts}}
}});

// 6. P95 latency
new Chart(document.getElementById('p95Bar'), {{
  type:'bar',
  data:{{
    labels:LABELS,
    datasets:[
      {{label:'SHA-256 P95 (s)',data:SHA_P95,backgroundColor:'rgba(245,158,11,0.8)',borderWidth:1}},
      {{label:'BLAKE2b-256 P95 (s)',data:BLA_P95,backgroundColor:'rgba(139,92,246,0.8)',borderWidth:1}}
    ]
  }},
  options:{{...baseOpts}}
}});

// 7. Radar SHA-256
new Chart(document.getElementById('radarSha'), {{
  type:'radar',
  data:{{
    labels:LABELS,
    datasets:[{{
      label:'SHA-256 Avg Latency (s)',
      data:SHA_AVG,
      backgroundColor:'rgba(59,130,246,0.2)',
      borderColor:'rgba(59,130,246,0.9)',
      pointBackgroundColor:'rgba(59,130,246,1)',
      pointRadius:4
    }}]
  }},
  options:{{
    responsive:true,maintainAspectRatio:false,
    plugins:{{legend:{{labels:{{color:textColor}}}}}},
    scales:{{r:{{ticks:{{color:textColor,backdropColor:'transparent'}},grid:{{color:gridColor}},
                 angleLines:{{color:gridColor}},pointLabels:{{color:textColor,font:{{size:10}}}}}}}}
  }}
}});

// 8. Radar BLAKE2b
new Chart(document.getElementById('radarBlake'), {{
  type:'radar',
  data:{{
    labels:LABELS,
    datasets:[{{
      label:'BLAKE2b-256 Avg Latency (s)',
      data:BLA_AVG,
      backgroundColor:'rgba(16,185,129,0.2)',
      borderColor:'rgba(16,185,129,0.9)',
      pointBackgroundColor:'rgba(16,185,129,1)',
      pointRadius:4
    }}]
  }},
  options:{{
    responsive:true,maintainAspectRatio:false,
    plugins:{{legend:{{labels:{{color:textColor}}}}}},
    scales:{{r:{{ticks:{{color:textColor,backdropColor:'transparent'}},grid:{{color:gridColor}},
                 angleLines:{{color:gridColor}},pointLabels:{{color:textColor,font:{{size:10}}}}}}}}
  }}
}});
</script>
</body>
</html>"""

with open(OUT, "w", encoding="utf-8") as f:
    f.write(html)

size = os.path.getsize(OUT)
print(f"✅  Written: {OUT}  ({size:,} bytes / {size//1024} KB)")
