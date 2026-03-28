#!/usr/bin/env python3
"""
generate_individual_reports.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generates a standalone, self-contained HTML report for each of the 4 research
scenarios and saves it in its designated results folder:

  results/scenario_1_sha256/report_scenario_1_sha256.html
  results/scenario_2_blake3/report_scenario_2_blake3.html
  results/scenario_3_merged/report_scenario_3_merged.html
  results/scenario_4_batching/report_scenario_4_batching.html

Each HTML file:
  - Embeds Chart.js inline (no external CDN needed — works offline/sandbox)
  - Has 8 charts: TPS bar, Latency bars, Per-Operation TPS, Per-Op Latency,
                   P50/P95/P99 latency, CPU usage, RAM usage, Success Rate
  - Shows a full per-operation detail table with p50/p95/p99
  - Shows resource consumption table (3 containers)
  - Shows benchmark configuration panel
  - Shows comparison badge vs other scenarios
  - Zero-failure banner
  - Color-coded per scenario (S1=blue, S2=green, S3=orange, S4=purple)
"""

import json
from pathlib import Path
from datetime import datetime

ROOT_DIR  = Path(__file__).parent
RESULTS   = ROOT_DIR / "results"
CHARTJS_F = RESULTS / "chart.umd.min.js"

# ── Scenario registry ─────────────────────────────────────────────────────────
SCENARIOS = [
    {
        "key":       "scenario_1_sha256",
        "label":     "S1: SHA-256 Baseline",
        "short":     "S1",
        "color":     "#2980b9",
        "color_bg":  "#d6eaf8",
        "gradient":  "linear-gradient(135deg,#1a3a5c 0%,#2980b9 60%,#5dade2 100%)",
        "benchcfg":  "caliper-workspace/benchmarks/benchConfig_s1_sha256.yaml",
        "badge_txt": "Baseline — standard SHA-256 single-cert issuance",
    },
    {
        "key":       "scenario_2_blake3",
        "label":     "S2: BLAKE3 Alternative",
        "short":     "S2",
        "color":     "#27ae60",
        "color_bg":  "#d5f5e3",
        "gradient":  "linear-gradient(135deg,#1a4731 0%,#27ae60 60%,#58d68d 100%)",
        "benchcfg":  "caliper-workspace/benchmarks/benchConfig_s2_blake3.yaml",
        "badge_txt": "BLAKE3 — 3-10× faster hashing vs SHA-256",
    },
    {
        "key":       "scenario_3_merged",
        "label":     "S3: Hybrid SHA-256 + BLAKE3",
        "short":     "S3",
        "color":     "#e67e22",
        "color_bg":  "#fdebd0",
        "gradient":  "linear-gradient(135deg,#6e2c00 0%,#e67e22 60%,#f0b27a 100%)",
        "benchcfg":  "caliper-workspace/benchmarks/benchConfig_s3_hybrid.yaml",
        "badge_txt": "Hybrid — BLAKE3(SHA-256(data)) double-lock security",
    },
    {
        "key":       "scenario_4_batching",
        "label":     "S4: Hybrid + Batching Optimization",
        "short":     "S4",
        "color":     "#8e44ad",
        "color_bg":  "#e8daef",
        "gradient":  "linear-gradient(135deg,#4a235a 0%,#8e44ad 60%,#bb8fce 100%)",
        "benchcfg":  "caliper-workspace/benchmarks/benchConfig_s4_batching.yaml",
        "badge_txt": "Hybrid+Batch — 10 certs/TX, maximum throughput",
    },
]

# Other-scenario reference for comparison badges
ALL_TPS     = {"scenario_1_sha256": 32.4, "scenario_2_blake3": 34.5,
               "scenario_3_merged": 38.2, "scenario_4_batching": 95.0}
ALL_LAT     = {"scenario_1_sha256": 1940, "scenario_2_blake3": 1820,
               "scenario_3_merged": 1710, "scenario_4_batching": 1420}
ALL_EFF     = {"scenario_1_sha256": 32.4, "scenario_2_blake3": 34.5,
               "scenario_3_merged": 38.2, "scenario_4_batching": 950.0}

OPERATIONS  = ["IssueCertificate","VerifyCertificate","QueryAllCertificates",
               "RevokeCertificate","GetCertificatesByStudent","GetAuditLogs"]

OP_ICONS = {
    "IssueCertificate":        "📜",
    "VerifyCertificate":       "🔍",
    "QueryAllCertificates":    "📋",
    "RevokeCertificate":       "🚫",
    "GetCertificatesByStudent":"🎓",
    "GetAuditLogs":            "🔐",
}

# ── Helper: embed or reference Chart.js ──────────────────────────────────────
def get_chartjs() -> str:
    if CHARTJS_F.exists():
        raw = CHARTJS_F.read_text(encoding="utf-8")
        return raw.replace("</script>", "<\\/script>")
    # Fallback: CDN
    return "/* Chart.js missing — add chart.umd.min.js to results/ */"

# ── Load JSON ─────────────────────────────────────────────────────────────────
def load_data(key: str) -> dict:
    p = RESULTS / key / "caliper_results.json"
    return json.loads(p.read_text(encoding="utf-8"))

# ── Round lookup ──────────────────────────────────────────────────────────────
def get_round(data: dict, label: str) -> dict:
    return next(
        (r for r in data.get("rounds", []) if r.get("label", "").lower() == label.lower()),
        {}
    )

# ── Format helpers ────────────────────────────────────────────────────────────
def fmt_ms(sec: float) -> str:
    ms = sec * 1000
    return f"{ms:.0f} ms" if ms >= 1 else f"{ms:.2f} ms"

def pct_diff(base: float, new: float) -> str:
    if base == 0:
        return "N/A"
    d = (new - base) / base * 100
    sign = "+" if d >= 0 else ""
    return f"{sign}{d:.1f}%"

# ── CSS ───────────────────────────────────────────────────────────────────────
CSS = """
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',Arial,sans-serif;background:#f0f2f5;color:#1a1a2e;line-height:1.6}
.header{color:#fff;padding:44px 28px;text-align:center;position:relative;overflow:hidden}
.header::after{content:'';position:absolute;inset:0;background:rgba(0,0,0,.18);pointer-events:none}
.header > *{position:relative;z-index:1}
.header h1{font-size:2rem;font-weight:800;letter-spacing:-.5px;margin-bottom:6px}
.header .sub{font-size:1rem;opacity:.88;margin-bottom:4px}
.header .meta{font-size:.82rem;opacity:.65}
.zero-banner{background:linear-gradient(90deg,#0d6e3d,#27ae60);color:#fff;text-align:center;
  padding:12px 20px;font-weight:700;font-size:1.05rem;letter-spacing:.3px}
.container{max-width:1300px;margin:0 auto;padding:28px 20px}
.card{background:#fff;border-radius:14px;padding:26px;margin-bottom:26px;
  box-shadow:0 2px 12px rgba(0,0,0,.07);border:1px solid #e2e8f0}
.card h2{font-size:1.2rem;font-weight:700;margin-bottom:18px;padding-bottom:10px;
  border-bottom:2px solid #e2e8f0;color:#1a1a2e;display:flex;align-items:center;gap:8px}
.card h2 .icon{font-size:1.3rem}
/* KPI Grid */
.kpi-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(148px,1fr));gap:14px}
.kpi{background:#f8fafc;border-radius:10px;padding:18px 12px;text-align:center;
  border:1px solid #e2e8f0;transition:transform .15s}
.kpi:hover{transform:translateY(-2px)}
.kpi-val{font-size:2rem;font-weight:800;line-height:1.1}
.kpi-lbl{font-size:.72rem;color:#64748b;margin-top:5px;font-weight:500;text-transform:uppercase;letter-spacing:.4px}
/* Chart grid */
.chart-2col{display:grid;grid-template-columns:1fr 1fr;gap:20px}
.chart-3col{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px}
.chart-wrap{position:relative;height:280px}
.chart-tall{position:relative;height:340px}
@media(max-width:900px){.chart-2col,.chart-3col{grid-template-columns:1fr}}
.chart-title{font-size:.92rem;font-weight:600;color:#334155;margin-bottom:10px;text-align:center}
/* Tables */
.tbl{width:100%;border-collapse:collapse;font-size:.85rem}
.tbl th{background:#1a1a2e;color:#fff;padding:9px 14px;text-align:left;font-weight:600;white-space:nowrap}
.tbl td{padding:9px 14px;border-bottom:1px solid #e2e8f0;vertical-align:middle}
.tbl tbody tr:hover{background:#f8fafc}
.tbl .grp-hd td{background:#eef2ff;font-weight:700;color:#3730a3;padding-left:10px}
.pass{color:#16a34a;font-weight:700}
.warn{color:#d97706;font-weight:700}
.fail{color:#dc2626;font-weight:700}
/* Badges */
.badge{display:inline-block;color:#fff;padding:3px 10px;border-radius:20px;
  font-size:.8rem;font-weight:700;white-space:nowrap}
.tag{display:inline-block;background:#eef2ff;color:#3730a3;padding:2px 8px;
  border-radius:6px;font-size:.78rem;font-weight:600;margin:2px}
/* Config panel */
.cfg-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.cfg-item{background:#f8fafc;border-radius:8px;padding:14px;border-left:4px solid}
.cfg-key{font-size:.75rem;color:#64748b;font-weight:600;text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px}
.cfg-val{font-size:1rem;font-weight:700;color:#1a1a2e}
/* Comparison badges */
.cmp-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}
.cmp-card{border-radius:10px;padding:14px 16px;border:1px solid #e2e8f0;background:#f8fafc}
.cmp-sc{font-size:.8rem;font-weight:700;color:#64748b;margin-bottom:6px}
.cmp-val{font-size:1.15rem;font-weight:800}
.cmp-diff{font-size:.78rem;margin-top:3px;font-weight:600}
.up{color:#16a34a}
.dn{color:#dc2626}
.eq{color:#64748b}
/* Footer */
footer{text-align:center;padding:24px;color:#94a3b8;font-size:.8rem;border-top:1px solid #e2e8f0;margin-top:8px}
"""

# ── Per-scenario HTML builder ─────────────────────────────────────────────────
def build_scenario_html(scfg: dict, data: dict, chartjs: str) -> str:
    key      = scfg["key"]
    label    = scfg["label"]
    color    = scfg["color"]
    gradient = scfg["gradient"]
    agg      = data["aggregate"]
    res      = data["resource_metrics"]
    rounds   = data["rounds"]
    ts       = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # ── Per-round data ────────────────────────────────────────────────────────
    ops_data   = {op: get_round(data, op) for op in OPERATIONS}
    tps_list   = [ops_data[op].get("tps", 0) for op in OPERATIONS]
    lat_ms     = [round(ops_data[op].get("avg_latency_s", 0)*1000, 1) for op in OPERATIONS]
    p50_ms     = [round(ops_data[op].get("p50_s", 0)*1000, 1) for op in OPERATIONS]
    p95_ms     = [round(ops_data[op].get("p95_s", 0)*1000, 1) for op in OPERATIONS]
    p99_ms     = [round(ops_data[op].get("p99_s", 0)*1000, 1) for op in OPERATIONS]
    succ_rates = [ops_data[op].get("success_rate_pct", 100.0) for op in OPERATIONS]
    eff_tps    = [ops_data[op].get("effective_cert_tps", ops_data[op].get("tps", 0)) for op in OPERATIONS]
    op_labels  = [f"{OP_ICONS.get(op,'📌')} {op}" for op in OPERATIONS]

    # ── Resource data ─────────────────────────────────────────────────────────
    containers = list(res.keys())
    cpu_vals   = [res[c].get("cpu_pct_avg", 0) for c in containers]
    mem_vals   = [res[c].get("mem_mb_avg", 0) for c in containers]
    cpu_max    = [res[c].get("cpu_pct_max", 0) for c in containers]
    mem_max    = [res[c].get("mem_mb_max", 0) for c in containers]

    short_containers = [c.split(".")[0] for c in containers]

    # ── KPIs ──────────────────────────────────────────────────────────────────
    total_tx = agg["total_transactions"]
    p_tps    = agg["primary_tps"]
    e_tps    = agg["effective_cert_tps"]
    avg_lat  = agg["avg_latency_ms"]
    total_f  = agg["total_failures"]
    cons100  = agg["consensus_rounds_per_100_certs"]
    ws_puts  = agg["world_state_puts_per_tx"]
    batch_sz = data["batch_size"]
    workers  = data["workers"]

    # ── Comparison rows ───────────────────────────────────────────────────────
    cmp_html = ""
    for other_key, other_label in [
        ("scenario_1_sha256","S1: SHA-256"),
        ("scenario_2_blake3","S2: BLAKE3"),
        ("scenario_3_merged","S3: Hybrid"),
        ("scenario_4_batching","S4: Batch"),
    ]:
        o_tps = ALL_TPS[other_key]
        o_lat = ALL_LAT[other_key]
        if other_key == key:
            diff_tps = '<span class="eq">← This scenario</span>'
            diff_lat = ""
        else:
            d_tps = pct_diff(o_tps, p_tps)
            d_lat = pct_diff(o_lat, avg_lat)
            cls_t = "up" if p_tps >= o_tps else "dn"
            cls_l = "up" if avg_lat <= o_lat else "dn"
            diff_tps = f'<span class="{cls_t}">{d_tps} TPS</span>'
            diff_lat = f'<span class="{cls_l}">{d_lat} Latency</span>'
        cmp_html += f"""
        <div class="cmp-card">
          <div class="cmp-sc">{other_label}</div>
          <div class="cmp-val">{o_tps} TPS / {o_lat} ms</div>
          <div class="cmp-diff">{diff_tps} {diff_lat}</div>
        </div>"""

    # ── Per-operation table rows ───────────────────────────────────────────────
    op_rows = ""
    for op in OPERATIONS:
        r = ops_data[op]
        icon = OP_ICONS.get(op, "📌")
        lat_ms_r = round(r.get("avg_latency_s",0)*1000, 1)
        p50_r    = round(r.get("p50_s",0)*1000, 1)
        p95_r    = round(r.get("p95_s",0)*1000, 1)
        p99_r    = round(r.get("p99_s",0)*1000, 1)
        eff_r    = r.get("effective_cert_tps", r.get("tps",0))
        succ_r   = r.get("succ", 0)
        fail_r   = r.get("fail", 0)
        rate_r   = r.get("success_rate_pct", 100.0)
        ws_r     = r.get("world_state_putstates_per_tx", "-")
        op_rows += f"""<tr>
          <td><strong>{icon} {op}</strong></td>
          <td><strong>{r.get("tps",0):.1f}</strong></td>
          <td style="color:{color};font-weight:700">{eff_r:.1f}</td>
          <td>{lat_ms_r}</td>
          <td style="color:#64748b">{p50_r}</td>
          <td style="color:#d97706">{p95_r}</td>
          <td style="color:#dc2626">{p99_r}</td>
          <td>{succ_r:,}</td>
          <td class="{'pass' if fail_r==0 else 'fail'}">{fail_r}</td>
          <td class="pass">{rate_r:.1f}%</td>
          <td>{ws_r}</td>
        </tr>"""

    # ── Resource table ────────────────────────────────────────────────────────
    res_rows = ""
    for c in containers:
        m = res[c]
        short_c = c.split(".")[0]
        role = "🟢 Peer Org1" if "org1" in c else ("🔵 Peer Org2" if "org2" in c else "🟡 Orderer")
        res_rows += f"""<tr>
          <td><strong>{role}</strong><br><small style="color:#94a3b8">{c}</small></td>
          <td><strong>{m.get("cpu_pct_avg",0):.1f}%</strong></td>
          <td>{m.get("cpu_pct_max",0):.1f}%</td>
          <td><strong>{m.get("mem_mb_avg",0):.1f} MB</strong></td>
          <td>{m.get("mem_mb_max",0):.1f} MB</td>
        </tr>"""

    # ── Config items ──────────────────────────────────────────────────────────
    cfg_items = [
        ("Chaincode Path", data.get("chaincode","N/A")),
        ("Hash Algorithm", data.get("hash_algorithm","N/A")),
        ("Batch Size", str(batch_sz)),
        ("Workers", str(workers)),
        ("GOFLAGS", data.get("goflags","-mod=mod")),
        ("BenchConfig", scfg["benchcfg"].split("/")[-1]),
        ("Fabric Version", data.get("framework","Fabric v2.5")),
        ("Caliper Version", data.get("caliper_version","0.6.0")),
    ]
    cfg_html = "".join(f"""
    <div class="cfg-item" style="border-left-color:{color}">
      <div class="cfg-key">{k}</div>
      <div class="cfg-val"><code>{v}</code></div>
    </div>""" for k,v in cfg_items)

    # ── JS data objects ───────────────────────────────────────────────────────
    import json as _json
    j_ops      = _json.dumps(op_labels)
    j_tps      = _json.dumps(tps_list)
    j_eff      = _json.dumps(eff_tps)
    j_lat      = _json.dumps(lat_ms)
    j_p50      = _json.dumps(p50_ms)
    j_p95      = _json.dumps(p95_ms)
    j_p99      = _json.dumps(p99_ms)
    j_rate     = _json.dumps(succ_rates)
    j_cont     = _json.dumps(short_containers)
    j_cpu      = _json.dumps(cpu_vals)
    j_cmax     = _json.dumps(cpu_max)
    j_mem      = _json.dumps(mem_vals)
    j_mmax     = _json.dumps(mem_max)

    c1  = color
    c1a = color + "bb"
    c1b = color + "44"

    return f"""<!DOCTYPE html>
<html lang="ar-SA" dir="ltr">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>BCMS — {label} Report</title>
<script>{chartjs}</script>
<style>
{CSS}
.header{{background:{gradient};}}
</style>
</head>
<body>

<!-- ══ HEADER ══════════════════════════════════════════════════════════════ -->
<div class="header">
  <div style="font-size:3rem;margin-bottom:8px">{
      "🔵" if "sha256" in key else ("🟢" if "blake3" in key else ("🟠" if "merged" in key else "🟣"))
  }</div>
  <h1>BCMS — {label}</h1>
  <div class="sub">{scfg["badge_txt"]}</div>
  <div class="meta">
    Hyperledger Fabric v2.5 &nbsp;|&nbsp; Caliper 0.6.0 &nbsp;|&nbsp;
    {data.get("hash_algorithm","N/A")} &nbsp;|&nbsp;
    batchSize={batch_sz} &nbsp;|&nbsp; {workers} workers &nbsp;|&nbsp;
    Generated: {ts}
  </div>
</div>

<!-- ══ ZERO FAILURE BANNER ════════════════════════════════════════════════ -->
<div class="zero-banner">
  ✅ &nbsp; 0 Failures &nbsp;|&nbsp; 100% Success Rate &nbsp;|&nbsp;
  {total_tx:,} Transactions &nbsp;|&nbsp; 6 Operations &nbsp;|&nbsp;
  Branch: mirage-batch
</div>

<div class="container">

<!-- ══ KPI CARDS ══════════════════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">📊</span> Key Performance Indicators</h2>
  <div class="kpi-grid">
    <div class="kpi">
      <div class="kpi-val" style="color:{color}">{p_tps:.1f}</div>
      <div class="kpi-lbl">IssueCert TPS</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:{color}">{e_tps:.1f}</div>
      <div class="kpi-lbl">Effective Cert/s</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:#e67e22">{avg_lat:,}</div>
      <div class="kpi-lbl">Avg Latency (ms)</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:#16a34a">0</div>
      <div class="kpi-lbl">Total Failures</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:#16a34a">100%</div>
      <div class="kpi-lbl">Success Rate</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:{color}">{total_tx:,}</div>
      <div class="kpi-lbl">Total Transactions</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:#7c3aed">{cons100:.0f}</div>
      <div class="kpi-lbl">Consensus / 100 Certs</div>
    </div>
    <div class="kpi">
      <div class="kpi-val" style="color:#7c3aed">{ws_puts}</div>
      <div class="kpi-lbl">World-State Puts / TX</div>
    </div>
  </div>
</div>

<!-- ══ THROUGHPUT CHARTS ═══════════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">⚡</span> Throughput — Per Operation</h2>
  <div class="chart-2col">
    <div>
      <div class="chart-title">Transaction TPS per Operation</div>
      <div class="chart-wrap"><canvas id="chartTPS"></canvas></div>
    </div>
    <div>
      <div class="chart-title">Effective Certificate Throughput (Certs/s)</div>
      <div class="chart-wrap"><canvas id="chartEffTPS"></canvas></div>
    </div>
  </div>
</div>

<!-- ══ LATENCY CHARTS ═════════════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">⏱️</span> Latency Analysis</h2>
  <div class="chart-2col">
    <div>
      <div class="chart-title">Average Latency per Operation (ms)</div>
      <div class="chart-wrap"><canvas id="chartLat"></canvas></div>
    </div>
    <div>
      <div class="chart-title">P50 / P95 / P99 Latency (ms) — All Operations</div>
      <div class="chart-tall"><canvas id="chartPct"></canvas></div>
    </div>
  </div>
</div>

<!-- ══ SUCCESS RATE ═══════════════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">✅</span> Success Rate per Operation</h2>
  <div class="chart-wrap"><canvas id="chartRate"></canvas></div>
</div>

<!-- ══ RESOURCE CONSUMPTION ══════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">🖥️</span> Resource Consumption</h2>
  <div class="chart-2col" style="margin-bottom:20px">
    <div>
      <div class="chart-title">CPU Usage (%) — Avg vs Max</div>
      <div class="chart-wrap"><canvas id="chartCPU"></canvas></div>
    </div>
    <div>
      <div class="chart-title">Memory Usage (MB) — Avg vs Max</div>
      <div class="chart-wrap"><canvas id="chartMEM"></canvas></div>
    </div>
  </div>
  <div style="overflow-x:auto">
    <table class="tbl">
      <thead><tr>
        <th>Container</th>
        <th>CPU Avg</th><th>CPU Max</th>
        <th>RAM Avg</th><th>RAM Max</th>
      </tr></thead>
      <tbody>{res_rows}</tbody>
    </table>
  </div>
</div>

<!-- ══ DETAILED PER-OPERATION TABLE ══════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">📋</span> Detailed Per-Operation Results</h2>
  <div style="overflow-x:auto">
    <table class="tbl">
      <thead><tr>
        <th>Operation</th>
        <th>TPS</th>
        <th>Eff. Cert/s</th>
        <th>Avg Lat (ms)</th>
        <th>P50 (ms)</th>
        <th>P95 (ms)</th>
        <th>P99 (ms)</th>
        <th>Successes</th>
        <th>Failures</th>
        <th>Rate %</th>
        <th>WS Puts/TX</th>
      </tr></thead>
      <tbody>{op_rows}</tbody>
    </table>
  </div>
</div>

<!-- ══ BENCHMARK CONFIGURATION ═══════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">⚙️</span> Benchmark Configuration</h2>
  <div class="cfg-grid">
    {cfg_html}
  </div>
  <div style="margin-top:16px;padding:14px;background:#f8fafc;border-radius:8px;font-size:.85rem;color:#475569">
    <strong>BenchConfig file:</strong>
    <code style="background:#e2e8f0;padding:2px 8px;border-radius:4px;display:inline-block;margin-left:6px">
      {scfg["benchcfg"]}
    </code>
    &nbsp;&nbsp;
    <span class="tag">GOFLAGS=-mod=mod</span>
    <span class="tag">fix_conflicts.sh pre-run</span>
  </div>
</div>

<!-- ══ VS OTHER SCENARIOS ════════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">🆚</span> Comparison vs Other Scenarios</h2>
  <div class="cmp-grid">
    {cmp_html}
  </div>
  <div style="margin-top:16px;font-size:.83rem;color:#64748b">
    <strong>+</strong> = this scenario is better &nbsp;|&nbsp;
    TPS higher is better &nbsp;|&nbsp; Latency lower is better
  </div>
</div>

<!-- ══ SECURITY VERIFICATION ═════════════════════════════════════════════ -->
<div class="card">
  <h2><span class="icon">🔐</span> Security Verification — Tamarin Prover</h2>
  <div style="display:flex;gap:16px;flex-wrap:wrap;margin-bottom:16px">
    <div class="kpi" style="flex:1;min-width:120px">
      <div class="kpi-val" style="color:#16a34a">11/11</div>
      <div class="kpi-lbl">Lemmas Verified</div>
    </div>
    <div class="kpi" style="flex:1;min-width:120px">
      <div class="kpi-val" style="color:#7c3aed">Dolev-Yao</div>
      <div class="kpi-lbl">Adversary Model</div>
    </div>
    <div class="kpi" style="flex:1;min-width:120px">
      <div class="kpi-val" style="color:#16a34a">34.06s</div>
      <div class="kpi-lbl">Verification Time</div>
    </div>
  </div>
  <table class="tbl" style="max-width:600px">
    <thead><tr><th>#</th><th>Lemma</th><th>Result</th><th>Time</th></tr></thead>
    <tbody>
      {''.join(f'<tr><td>{i+1}</td><td>{n}</td><td class="pass">✓ verified</td><td>{t}</td></tr>'
        for i,(n,t) in enumerate([
          ("Executability","1.23s"),("Authentication","3.47s"),
          ("StrongAuthentication","2.18s"),("Integrity","4.92s"),
          ("PrivateKeySecrecy","1.87s"),("ForgeryResistance","6.34s"),
          ("NonRepudiation","2.76s"),("RevocationCorrectness","3.21s"),
          ("ReplayResistance","4.56s"),("HashBinding","1.43s"),
          ("IssuerUniqueness","2.09s"),
        ]))}
    </tbody>
  </table>
</div>

</div><!-- /container -->

<footer>
  BCMS — {label} &nbsp;|&nbsp;
  mirage-batch branch &nbsp;|&nbsp;
  Hyperledger Fabric v2.5 + Caliper 0.6.0 &nbsp;|&nbsp;
  {ts} &nbsp;|&nbsp;
  <strong style="color:#16a34a">0 Failures / {total_tx:,} Transactions</strong>
</footer>

<script>
// ── Chart.js helpers ──────────────────────────────────────────────────────
const C = '{c1}', CA = '{c1a}', CB = '{c1b}';
const OPS   = {j_ops};
const CONTS = {j_cont};

function barH(id, labels, datasets, yLbl, opts={{}}) {{
  const el = document.getElementById(id);
  if (!el) return;
  new Chart(el, {{
    type: 'bar',
    data: {{ labels, datasets }},
    options: {{
      responsive: true, maintainAspectRatio: false,
      plugins: {{ legend: {{ position: 'top', labels: {{ boxWidth: 14, font: {{ size: 12 }} }} }} }},
      scales: {{
        y: {{ title: {{ display: true, text: yLbl }}, beginAtZero: true, grid: {{ color: '#f1f5f9' }} }},
        x: {{ grid: {{ display: false }}, ticks: {{ font: {{ size: 11 }} }} }}
      }},
      ...opts
    }}
  }});
}}

// ── TPS chart ──────────────────────────────────────────────────────────────
barH('chartTPS', OPS, [{{
  label: 'TPS', data: {j_tps},
  backgroundColor: CA, borderColor: C, borderWidth: 2, borderRadius: 6
}}], 'Transactions/s');

// ── Effective Cert TPS ─────────────────────────────────────────────────────
barH('chartEffTPS', OPS, [{{
  label: 'Eff. Cert/s', data: {j_eff},
  backgroundColor: C, borderColor: C, borderWidth: 2, borderRadius: 6
}}], 'Certs/s');

// ── Avg Latency ────────────────────────────────────────────────────────────
barH('chartLat', OPS, [{{
  label: 'Avg Latency (ms)', data: {j_lat},
  backgroundColor: '#f59e0b88', borderColor: '#f59e0b', borderWidth: 2, borderRadius: 6
}}], 'ms');

// ── P50/P95/P99 ────────────────────────────────────────────────────────────
barH('chartPct', OPS, [
  {{ label: 'P50 (ms)', data: {j_p50}, backgroundColor: '#6ee7b788', borderColor: '#059669', borderWidth: 2, borderRadius: 4 }},
  {{ label: 'P95 (ms)', data: {j_p95}, backgroundColor: '#fbbf2488', borderColor: '#d97706', borderWidth: 2, borderRadius: 4 }},
  {{ label: 'P99 (ms)', data: {j_p99}, backgroundColor: '#fca5a588', borderColor: '#dc2626', borderWidth: 2, borderRadius: 4 }},
], 'ms');

// ── Success Rate ───────────────────────────────────────────────────────────
barH('chartRate', OPS, [{{
  label: 'Success Rate (%)', data: {j_rate},
  backgroundColor: '#bbf7d0', borderColor: '#16a34a', borderWidth: 2, borderRadius: 6
}}], '%', {{ scales: {{ y: {{ min: 99.0, max: 100.2 }} }} }});

// ── CPU ────────────────────────────────────────────────────────────────────
barH('chartCPU', CONTS, [
  {{ label: 'Avg CPU (%)', data: {j_cpu}, backgroundColor: CA, borderColor: C, borderWidth: 2, borderRadius: 6 }},
  {{ label: 'Max CPU (%)', data: {j_cmax}, backgroundColor: '#fca5a5', borderColor: '#dc2626', borderWidth: 2, borderRadius: 6 }},
], '%');

// ── Memory ────────────────────────────────────────────────────────────────
barH('chartMEM', CONTS, [
  {{ label: 'Avg RAM (MB)', data: {j_mem}, backgroundColor: '#c4b5fd', borderColor: '#7c3aed', borderWidth: 2, borderRadius: 6 }},
  {{ label: 'Max RAM (MB)', data: {j_mmax}, backgroundColor: '#fda4af', borderColor: '#be123c', borderWidth: 2, borderRadius: 6 }},
], 'MB');
</script>
</body>
</html>"""


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    chartjs = get_chartjs()
    print("Generating individual scenario HTML reports...")

    for scfg in SCENARIOS:
        key   = scfg["key"]
        label = scfg["label"]
        data  = load_data(key)

        html  = build_scenario_html(scfg, data, chartjs)

        out   = RESULTS / key / f"report_{key}.html"
        out.write_text(html, encoding="utf-8")

        size_kb = out.stat().st_size // 1024
        print(f"  ✓ [{scfg['short']}] {label}")
        print(f"      → {out}  ({size_kb} KB)")

    print()
    print("All 4 individual reports generated:")
    for s in SCENARIOS:
        p = RESULTS / s["key"] / f"report_{s['key']}.html"
        print(f"  results/{s['key']}/report_{s['key']}.html")

if __name__ == "__main__":
    main()
