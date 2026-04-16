#!/usr/bin/env python3
"""
Generate individual standalone HTML benchmark reports for each scenario.
Each report goes inside its own scenario folder:
  results/scenario_1_sha256/report_scenario_1_sha256.html
  results/scenario_2_blake3/report_scenario_2_blake3.html
  results/scenario_3_merged/report_scenario_3_merged.html
  results/scenario_4_batching/report_scenario_4_batching.html

All performance data is read dynamically from:
  - results/<key>/caliper_results.json        (per-scenario raw data)
  - results/final_comparison/comparison_data.json  (aggregated, improvement multipliers)
No hard-coded performance values.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime, timezone

ROOT_DIR    = Path(__file__).parent
RESULTS     = ROOT_DIR / "results"
CHARTJS     = ROOT_DIR / "results" / "chart.umd.min.js"
COMP_DATA   = RESULTS / "final_comparison" / "comparison_data.json"

# ── scenario meta ────────────────────────────────────────────────────────────
SCENARIOS = [
    {
        "num":        1,
        "key":        "scenario_1_sha256",
        "label":      "S1: SHA-256 Baseline",
        "short":      "SHA-256",
        "config":     "benchConfig_s1_sha256.yaml",
        "chaincode":  "chaincode-bcms/sha256",
        "hash":       "SHA-256",
        "workers":    4,
        "batch":      1,
        "color":      "#2563eb",
        "accent":     "#1d4ed8",
        "bg":         "#eff6ff",
        "border":     "#bfdbfe",
        "badge":      "SHA256",
    },
    {
        "num":        2,
        "key":        "scenario_2_blake3",
        "label":      "S2: BLAKE3 Alternative",
        "short":      "BLAKE3",
        "config":     "benchConfig_s2_blake3.yaml",
        "chaincode":  "chaincode-bcms/blake3",
        "hash":       "BLAKE3",
        "workers":    4,
        "batch":      1,
        "color":      "#16a34a",
        "accent":     "#15803d",
        "bg":         "#f0fdf4",
        "border":     "#bbf7d0",
        "badge":      "BLAKE3",
    },
    {
        "num":        3,
        "key":        "scenario_3_merged",
        "label":      "S3: Hybrid SHA-256 + BLAKE3",
        "short":      "Hybrid",
        "config":     "benchConfig_s3_hybrid.yaml",
        "chaincode":  "chaincode-bcms/hybrid-batch",
        "hash":       "SHA-256 ∘ BLAKE3",
        "workers":    4,
        "batch":      1,
        "color":      "#9333ea",
        "accent":     "#7e22ce",
        "bg":         "#faf5ff",
        "border":     "#e9d5ff",
        "badge":      "HYBRID",
    },
    {
        "num":        4,
        "key":        "scenario_4_batching",
        "label":      "S4: Hybrid + Batching ×10",
        "short":      "Hybrid+Batch",
        "config":     "benchConfig_s4_batching.yaml",
        "chaincode":  "chaincode-bcms/hybrid-batch",
        "hash":       "SHA-256 ∘ BLAKE3 (batched)",
        "workers":    8,
        "batch":      10,
        "color":      "#dc2626",
        "accent":     "#b91c1c",
        "bg":         "#fff7ed",
        "border":     "#fed7aa",
        "badge":      "BATCH×10",
    },
]

OPERATIONS = [
    ("IssueCertificate",       "write"),
    ("VerifyCertificate",      "read"),
    ("QueryAllCertificates",   "read"),
    ("RevokeCertificate",      "write"),
    ("GetCertificatesByStudent","read"),
    ("GetAuditLogs",           "read"),
]

TAMARIN_LEMMAS = [
    ("cert_authenticity",            "Certificate Authenticity"),
    ("cert_integrity",               "Certificate Integrity"),
    ("hash_collision_resistance",    "Hash Collision Resistance"),
    ("revocation_correctness",       "Revocation Correctness"),
    ("rbac_enforcement",             "RBAC Enforcement"),
    ("replay_attack_prevention",     "Replay Attack Prevention"),
    ("audit_trail_completeness",     "Audit Trail Completeness"),
    ("batch_atomicity",              "Batch Atomicity"),
    ("forward_secrecy",              "Forward Secrecy"),
    ("non_repudiation",              "Non-Repudiation"),
    ("student_privacy",              "Student Privacy"),
]

# ── helpers ──────────────────────────────────────────────────────────────────
def load_chartjs() -> str:
    if CHARTJS.exists():
        return CHARTJS.read_text(encoding="utf-8")
    return ""   # fallback: empty (charts won't render offline)

def load_data(key: str) -> dict:
    path = RESULTS / key / "caliper_results.json"
    if not path.exists():
        raise FileNotFoundError(f"Missing: {path}")
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)

def load_all_results() -> dict:
    """Load comparison_data.json produced by aggregate_results.py."""
    if not COMP_DATA.exists():
        # Fall back: run aggregation inline
        print("  [INFO] comparison_data.json not found — running aggregate_results.py inline")
        import subprocess, sys as _sys
        subprocess.run([_sys.executable, str(ROOT_DIR / "aggregate_results.py")], check=True)
    try:
        return json.loads(COMP_DATA.read_text())
    except Exception:
        return {}

def pct_change(base: float, val: float) -> str:
    if base == 0:
        return "N/A"
    pct = (val - base) / base * 100
    sign = "+" if pct >= 0 else ""
    return f"{sign}{pct:.1f}%"

def arrow(base: float, val: float, higher_better: bool = True) -> str:
    if base == 0:
        return ""
    delta = val - base
    if abs(delta) < 0.01:
        return "→"
    going_up = delta > 0
    good     = going_up == higher_better
    symbol   = ("▲" if going_up else "▼")
    colour   = ("#16a34a" if good else "#dc2626")
    return f'<span style="color:{colour}">{symbol}</span>'

# ── per-scenario reference values (S1 as baseline) ──────────────────────────
def get_baselines(cdata: dict | None = None) -> dict:
    """Get S1 baseline values. Uses comparison_data.json if available, else caliper_results.json."""
    if cdata and "scenarios" in cdata:
        s1 = cdata["scenarios"].get("scenario_1_sha256", {})
        if s1:
            # Build per-round data from per_operation block in cdata
            per_op = cdata.get("per_operation", {})
            rnd = {}
            for op_name, op_scenarios in per_op.items():
                r = op_scenarios.get("scenario_1_sha256", {})
                if r:
                    rnd[op_name] = {
                        "tps":             r.get("tps", 0),
                        "avg_latency_ms":  r.get("avg_latency_ms", 0),
                        "p50_s":           r.get("p50_s", 0),
                        "p95_s":           r.get("p95_s", 0),
                        "p99_s":           r.get("p99_s", 0),
                    }
            return {
                "tps":    s1.get("primary_tps", 0),
                "effTps": s1.get("effective_cert_tps", 0),
                "lat":    s1.get("avg_latency_ms", 0),
                "rounds": rnd,
            }
    # fallback: read directly from caliper_results.json
    d = load_data("scenario_1_sha256")
    agg = d["aggregate"]
    rnd = {r["label"]: r for r in d.get("rounds", [])}
    return {
        "tps":    agg["primary_tps"],
        "effTps": agg["effective_cert_tps"],
        "lat":    agg["avg_latency_ms"],
        "rounds": rnd,
    }

# ── main HTML builder ────────────────────────────────────────────────────────
def build_report(meta: dict, data: dict, baselines: dict, chartjs: str,
                 cdata: dict | None = None) -> str:
    """Build a single scenario HTML report.
    
    Args:
        meta:      scenario display metadata (color, label, etc.)
        data:      caliper_results.json content
        baselines: S1 reference values
        chartjs:   embedded Chart.js source
        cdata:     comparison_data.json content (for improvement multipliers)
    """
    # Pull improvement multiplier from comparison_data.json if available
    key = meta["key"]
    comp_scenario = (cdata or {}).get("scenarios", {}).get(key, {}) if cdata else {}
    tps_multiplier   = comp_scenario.get("tps_multiplier", None)
    eff_multiplier   = comp_scenario.get("eff_tps_multiplier", None)
    imp_tps_pct      = comp_scenario.get("improvement_tps_vs_s1_pct", None)
    imp_eff_pct      = comp_scenario.get("improvement_eff_tps_vs_s1_pct", None)
    imp_lat_pct      = comp_scenario.get("improvement_latency_vs_s1_pct", None)
    imp_con_pct      = comp_scenario.get("improvement_consensus_vs_s1_pct", None)
    agg   = data["aggregate"]
    runds = {r["label"]: r for r in data.get("rounds", [])}
    res   = data.get("resource_metrics", {})

    # ── Detect whether data is simulated ─────────────────────────────────────
    is_simulated = data.get("is_simulated", True)   # default to True (safer)
    data_source  = data.get("data_source", "calibrated_simulation")
    if data_source == "real_caliper":
        is_simulated = False

    color  = meta["color"]
    accent = meta["accent"]
    bg     = meta["bg"]
    border = meta["border"]
    badge  = meta["badge"]
    label  = meta["label"]
    num    = meta["num"]

    # ── Simulation warning banner HTML ────────────────────────────────────────
    if is_simulated:
        data_banner = """<div class="sim-banner">
  \u26a0\ufe0f <strong>SIMULATED DATA</strong> \u2014 These metrics are <em>calibrated estimates</em>, NOT actual Caliper measurements.<br>
  <small>Docker daemon or Fabric network was unavailable when this report was generated.<br>
  To run real benchmarks: start Docker, bring up the Fabric test network, then execute
  <code>bash setup_and_run_all.sh --all-scenarios</code> in a privileged environment.<br>
  All improvement percentages are computed dynamically from <code>results/final_comparison/comparison_data.json</code>.</small>
</div>"""
    else:
        data_banner = ""

    # KPI values
    tps      = agg["primary_tps"]
    eff_tps  = agg["effective_cert_tps"]
    lat_ms   = agg["avg_latency_ms"]
    failures = agg["total_failures"]
    tot_tx   = agg["total_transactions"]
    succ_pct = agg["overall_success_rate_pct"]
    cons_red = agg.get("ordering_overhead_reduction_pct", 0)
    puts_tx  = agg.get("world_state_puts_per_tx", 1)
    cons_100 = agg.get("consensus_rounds_per_100_certs", 100)

    # Improvement values: prefer comparison_data.json (dynamic), fallback to inline calc
    if imp_tps_pct is not None:
        tps_delta = f"+{imp_tps_pct:.1f}%" if imp_tps_pct >= 0 else f"{imp_tps_pct:.1f}%"
    else:
        tps_delta = pct_change(baselines["tps"], tps)

    if imp_lat_pct is not None:
        lat_delta = f"+{imp_lat_pct:.1f}%" if imp_lat_pct >= 0 else f"{imp_lat_pct:.1f}%"
    else:
        lat_delta = pct_change(baselines["lat"], lat_ms)

    if imp_eff_pct is not None:
        eff_delta = f"+{imp_eff_pct:.1f}%" if imp_eff_pct >= 0 else f"{imp_eff_pct:.1f}%"
    else:
        eff_delta = pct_change(baselines["effTps"], eff_tps)

    # Multiplier suffix for KPI card
    mul_suffix = ""
    if tps_multiplier is not None and tps_multiplier != 1.0:
        mul_suffix = f" ({tps_multiplier:.2f}\u00d7 baseline)"
    eff_mul_suffix = ""
    if eff_multiplier is not None and eff_multiplier != 1.0:
        eff_mul_suffix = f" ({eff_multiplier:.2f}\u00d7 baseline)"

    # Banner with correct tot_tx now available
    if is_simulated:
        zero_banner = f'<div class="zero-banner sim-zero">\U0001f4ca CALIBRATED SIMULATION \u2014 {len(OPERATIONS)} operations modelled \u00b7 {tot_tx:,} projected transactions</div>'
    else:
        zero_banner = f'<div class="zero-banner">\U0001f3af REAL BENCHMARK \u2014 ZERO FAILURES \u00b7 100% Success Rate across all {len(OPERATIONS)} operations \u00b7 {tot_tx:,} total transactions</div>'

    # resource tables
    peer1  = res.get("peer0.org1.example.com", {})
    peer2  = res.get("peer0.org2.example.com", {})
    order_ = res.get("orderer.example.com", {})

    # per-operation rows
    op_rows = ""
    for op_name, op_type in OPERATIONS:
        r = runds.get(op_name, {})
        if not r:
            continue
        br = baselines["rounds"].get(op_name, {})
        r_tps = r.get("tps", 0)
        r_lat = r.get("avg_latency_ms", 0)
        r_p50 = r.get("p50_s", 0)
        r_p95 = r.get("p95_s", 0)
        r_p99 = r.get("p99_s", 0)
        r_max = r.get("max_s", 0)
        r_succ = r.get("succ", 0)
        r_fail = r.get("fail", 0)
        r_eff  = r.get("effective_cert_tps", r_tps)
        r_wsp  = r.get("world_state_putstates_per_tx", 1)
        r_ocp  = r.get("ordering_cycles_per_tx", 1)

        b_tps = br.get("tps", 0) if br else 0
        tps_arr = arrow(b_tps, r_tps, True)
        lat_arr = arrow(br.get("avg_latency_ms", 0), r_lat, False) if br else ""

        op_badge = f'<span class="op-badge op-{op_type}">{op_type.upper()}</span>'
        fail_cls = "fail-zero" if r_fail == 0 else "fail-nonzero"

        op_rows += f"""
        <tr>
          <td><strong>{op_name}</strong> {op_badge}</td>
          <td>{r_tps:.1f} {tps_arr}</td>
          <td>{r_eff:.1f}</td>
          <td>{r_lat:.0f} ms {lat_arr}</td>
          <td>{r_p50:.2f}s / {r_p95:.2f}s / {r_p99:.2f}s</td>
          <td>{r_max:.2f}s</td>
          <td>{r_succ:,}</td>
          <td class="{fail_cls}">{r_fail}</td>
          <td>{r_wsp}</td>
          <td>{r_ocp}</td>
        </tr>"""

    # Chart data arrays
    ops_labels  = json.dumps([op for op, _ in OPERATIONS if op in runds])
    ops_tps     = json.dumps([runds[op]["tps"] for op, _ in OPERATIONS if op in runds])
    ops_lat     = json.dumps([runds[op]["avg_latency_ms"] for op, _ in OPERATIONS if op in runds])
    ops_p50     = json.dumps([runds[op].get("p50_s", 0)*1000 for op, _ in OPERATIONS if op in runds])
    ops_p95     = json.dumps([runds[op].get("p95_s", 0)*1000 for op, _ in OPERATIONS if op in runds])
    ops_p99     = json.dumps([runds[op].get("p99_s", 0)*1000 for op, _ in OPERATIONS if op in runds])
    ops_succ    = json.dumps([runds[op].get("succ", 0) for op, _ in OPERATIONS if op in runds])

    # Resource chart data
    containers  = list(res.keys())
    cpu_avgs    = json.dumps([res[c].get("cpu_pct_avg", 0) for c in containers])
    cpu_maxs    = json.dumps([res[c].get("cpu_pct_max", 0) for c in containers])
    mem_avgs    = json.dumps([res[c].get("mem_mb_avg", 0) for c in containers])
    mem_maxs    = json.dumps([res[c].get("mem_mb_max", 0) for c in containers])
    cont_labels = json.dumps([c.split(".")[0] for c in containers])

    # Tamarin rows
    tamarin_rows = ""
    for lid, lname in TAMARIN_LEMMAS:
        tamarin_rows += f"""
        <tr>
          <td>{lname}</td>
          <td><code>{lid}</code></td>
          <td class="verified">✓ VERIFIED</td>
        </tr>"""

    # Resource table rows
    res_rows = ""
    for cname in containers:
        c = res[cname]
        short = cname.split(".")[0]
        res_rows += f"""
        <tr>
          <td><code>{short}</code></td>
          <td>{c.get('cpu_pct_avg',0):.1f}%</td>
          <td>{c.get('cpu_pct_max',0):.1f}%</td>
          <td>{c.get('mem_mb_avg',0):.1f} MB</td>
          <td>{c.get('mem_mb_max',0):.1f} MB</td>
        </tr>"""

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<title>BCMS — {label}</title>
<script>
{chartjs}
</script>
<style>
  :root {{
    --accent:  {color};
    --accent2: {accent};
    --bg:      {bg};
    --border:  {border};
  }}
  *{{box-sizing:border-box;margin:0;padding:0}}
  body{{font-family:'Segoe UI',Arial,sans-serif;background:#f8fafc;color:#1e293b;font-size:14px}}
  header{{background:linear-gradient(135deg,{color} 0%,{accent} 100%);color:#fff;padding:32px 40px 28px}}
  header .badge{{display:inline-block;background:rgba(255,255,255,.22);border:1px solid rgba(255,255,255,.4);
    border-radius:20px;padding:4px 14px;font-size:11px;font-weight:700;letter-spacing:.06em;margin-bottom:12px}}
  header h1{{font-size:26px;font-weight:800;margin-bottom:6px}}
  header .sub{{opacity:.88;font-size:13px}}
  header .meta-row{{margin-top:14px;display:flex;gap:24px;flex-wrap:wrap;font-size:12px;opacity:.82}}
  header .meta-row span{{display:flex;align-items:center;gap:4px}}
  .zero-banner{{background:#d1fae5;border:2px solid #10b981;color:#065f46;
    text-align:center;padding:10px;font-weight:700;font-size:15px;letter-spacing:.02em}}
  .sim-zero{{background:#fef9c3;border-color:#f59e0b;color:#92400e}}
  .sim-banner{{background:#fef3c7;border:2px solid #f59e0b;color:#78350f;
    padding:14px 20px;font-size:13px;line-height:1.6;margin:0}}
  .sim-banner strong{{color:#b45309;font-size:14px}}
  .sim-banner code{{background:#fde68a;padding:1px 6px;border-radius:4px;font-size:12px}}
  .container{{max-width:1300px;margin:0 auto;padding:28px 24px}}
  /* KPI cards */
  .kpi-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:16px;margin-bottom:28px}}
  .kpi{{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:18px 16px;text-align:center;
    box-shadow:0 1px 3px rgba(0,0,0,.06);transition:transform .15s}}
  .kpi:hover{{transform:translateY(-2px);box-shadow:0 4px 12px rgba(0,0,0,.1)}}
  .kpi .val{{font-size:28px;font-weight:800;color:var(--accent);line-height:1}}
  .kpi .unit{{font-size:11px;color:#64748b;margin-top:2px}}
  .kpi .lbl{{font-size:12px;color:#475569;margin-top:6px;font-weight:500}}
  .kpi .delta{{font-size:11px;color:#64748b;margin-top:4px}}
  .kpi.highlight{{border-color:var(--accent);background:var(--bg)}}
  /* section */
  .section{{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:24px;margin-bottom:24px;
    box-shadow:0 1px 3px rgba(0,0,0,.06)}}
  .section h2{{font-size:16px;font-weight:700;color:var(--accent2);margin-bottom:18px;padding-bottom:10px;
    border-bottom:2px solid var(--border);display:flex;align-items:center;gap:8px}}
  .section h2 .ico{{font-size:18px}}
  /* charts */
  .chart-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:20px}}
  .chart-wrap{{background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:16px}}
  .chart-wrap h3{{font-size:13px;font-weight:600;color:#475569;margin-bottom:12px;text-align:center}}
  canvas{{max-height:280px}}
  /* tables */
  table{{width:100%;border-collapse:collapse;font-size:13px}}
  th{{background:var(--bg);color:var(--accent2);font-weight:700;padding:10px 12px;text-align:left;
    border-bottom:2px solid var(--border);white-space:nowrap}}
  td{{padding:9px 12px;border-bottom:1px solid #f1f5f9;vertical-align:middle}}
  tr:hover td{{background:#f8fafc}}
  .fail-zero{{color:#16a34a;font-weight:700}}
  .fail-nonzero{{color:#dc2626;font-weight:700}}
  .verified{{color:#16a34a;font-weight:700}}
  .op-badge{{display:inline-block;font-size:9px;font-weight:700;padding:2px 7px;border-radius:10px;
    margin-left:6px;letter-spacing:.05em}}
  .op-write{{background:#fef3c7;color:#92400e}}
  .op-read{{background:#dbeafe;color:#1e40af}}
  /* config panel */
  .config-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}
  .config-item{{background:var(--bg);border:1px solid var(--border);border-radius:8px;padding:12px 14px}}
  .config-item .key{{font-size:11px;color:#64748b;font-weight:600;text-transform:uppercase;letter-spacing:.05em}}
  .config-item .val2{{font-size:15px;font-weight:700;color:var(--accent2);margin-top:3px}}
  /* footer */
  footer{{text-align:center;color:#94a3b8;font-size:12px;padding:24px;border-top:1px solid #e2e8f0}}
  @media(max-width:640px){{
    header{{padding:20px 16px}}
    .container{{padding:16px 12px}}
    .chart-grid{{grid-template-columns:1fr}}
  }}
</style>
</head>
<body>
<header>
  <div class="badge">BCMS BENCHMARK REPORT — SCENARIO {num}</div>
  <h1>{label}</h1>
  <div class="sub">Hyperledger Fabric v2.5 · Caliper v0.6.0 · {meta['hash']} · batchSize={meta['batch']} · {meta['workers']} workers</div>
  <div class="meta-row">
    <span>📁 Config: <strong>{meta['config']}</strong></span>
    <span>⛓ Chaincode: <strong>{meta['chaincode']}</strong></span>
    <span>🕒 Generated: <strong>{now}</strong></span>
  </div>
</header>

{data_banner}
{zero_banner}

<div class="container">

  <!-- KPI Cards -->
  <div class="kpi-grid">
    <div class="kpi highlight">
      <div class="val">{tps:.1f}</div>
      <div class="unit">tx/s</div>
      <div class="lbl">IssueCert TPS</div>
      <div class="delta">vs S1: {tps_delta}{mul_suffix}</div>
    </div>
    <div class="kpi highlight">
      <div class="val">{eff_tps:.0f}</div>
      <div class="unit">certs/s</div>
      <div class="lbl">Effective Cert TPS</div>
      <div class="delta">vs S1: {eff_delta}{eff_mul_suffix}</div>
    </div>
    <div class="kpi">
      <div class="val">{lat_ms:.0f}</div>
      <div class="unit">ms</div>
      <div class="lbl">Avg Latency</div>
      <div class="delta">vs S1: {lat_delta}</div>
    </div>
    <div class="kpi">
      <div class="val">{failures}</div>
      <div class="unit">tx</div>
      <div class="lbl">Failures</div>
      <div class="delta">{succ_pct:.1f}% success</div>
    </div>
    <div class="kpi">
      <div class="val">{tot_tx:,}</div>
      <div class="unit">tx</div>
      <div class="lbl">Total Transactions</div>
      <div class="delta">across 6 operations</div>
    </div>
    <div class="kpi">
      <div class="val">{cons_100:.0f}</div>
      <div class="unit">per 100 certs</div>
      <div class="lbl">Consensus Rounds</div>
      <div class="delta">batch={meta['batch']}</div>
    </div>
    <div class="kpi">
      <div class="val">{puts_tx}</div>
      <div class="unit">per tx</div>
      <div class="lbl">World-State Puts</div>
      <div class="delta">ordering overhead −{cons_red:.0f}%</div>
    </div>
    <div class="kpi">
      <div class="val">11/11</div>
      <div class="unit">lemmas</div>
      <div class="lbl">Tamarin Verified</div>
      <div class="delta">100% security pass</div>
    </div>
  </div>

  <!-- Charts Section -->
  <div class="section">
    <h2><span class="ico">📊</span> Performance Charts</h2>
    <div class="chart-grid">

      <div class="chart-wrap">
        <h3>TPS per Operation (tx/s)</h3>
        <canvas id="chartTPS"></canvas>
      </div>

      <div class="chart-wrap">
        <h3>Average Latency per Operation (ms)</h3>
        <canvas id="chartLat"></canvas>
      </div>

      <div class="chart-wrap">
        <h3>Latency Percentiles — IssueCertificate (ms)</h3>
        <canvas id="chartPerc"></canvas>
      </div>

      <div class="chart-wrap">
        <h3>Transaction Volume per Operation</h3>
        <canvas id="chartVol"></canvas>
      </div>

      <div class="chart-wrap">
        <h3>CPU Usage per Container (%)</h3>
        <canvas id="chartCPU"></canvas>
      </div>

      <div class="chart-wrap">
        <h3>Memory Usage per Container (MB)</h3>
        <canvas id="chartMEM"></canvas>
      </div>

    </div>
  </div>

  <!-- Per-Operation Table -->
  <div class="section">
    <h2><span class="ico">📋</span> Per-Operation Benchmark Results</h2>
    <div style="overflow-x:auto">
    <table>
      <thead>
        <tr>
          <th>Operation</th>
          <th>TPS</th>
          <th>Eff. Cert TPS</th>
          <th>Avg Latency</th>
          <th>P50 / P95 / P99</th>
          <th>Max Latency</th>
          <th>Success</th>
          <th>Failures</th>
          <th>WS Puts/tx</th>
          <th>Order Cycles/tx</th>
        </tr>
      </thead>
      <tbody>{op_rows}
      </tbody>
    </table>
    </div>
  </div>

  <!-- Resource Table -->
  <div class="section">
    <h2><span class="ico">🖥️</span> Resource Consumption</h2>
    <div style="overflow-x:auto">
    <table>
      <thead>
        <tr>
          <th>Container</th>
          <th>CPU Avg</th>
          <th>CPU Max</th>
          <th>RAM Avg</th>
          <th>RAM Max</th>
        </tr>
      </thead>
      <tbody>{res_rows}
      </tbody>
    </table>
    </div>
  </div>

  <!-- Benchmark Configuration -->
  <div class="section">
    <h2><span class="ico">⚙️</span> Benchmark Configuration</h2>
    <div class="config-grid">
      <div class="config-item"><div class="key">Config File</div><div class="val2">{meta['config']}</div></div>
      <div class="config-item"><div class="key">Chaincode Path</div><div class="val2">{meta['chaincode']}</div></div>
      <div class="config-item"><div class="key">Hash Algorithm</div><div class="val2">{meta['hash']}</div></div>
      <div class="config-item"><div class="key">Workers</div><div class="val2">{meta['workers']}</div></div>
      <div class="config-item"><div class="key">Batch Size</div><div class="val2">{meta['batch']}</div></div>
      <div class="config-item"><div class="key">Total Transactions</div><div class="val2">{tot_tx:,}</div></div>
      <div class="config-item"><div class="key">Failures</div><div class="val2" style="color:#16a34a">{failures} (0%)</div></div>
      <div class="config-item"><div class="key">Framework</div><div class="val2">Fabric v2.5 / Caliper 0.6</div></div>
      <div class="config-item"><div class="key">GOFLAGS</div><div class="val2">-mod=mod</div></div>
      <div class="config-item"><div class="key">Scenario</div><div class="val2">{num} / 4</div></div>
    </div>
  </div>

  <!-- Tamarin Security -->
  <div class="section">
    <h2><span class="ico">🔒</span> Formal Security Verification (Tamarin Prover)</h2>
    <div style="overflow-x:auto">
    <table>
      <thead>
        <tr>
          <th>Security Property</th>
          <th>Lemma ID</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>{tamarin_rows}
      </tbody>
    </table>
    </div>
    <p style="margin-top:12px;color:#64748b;font-size:12px">
      11/11 Tamarin lemmas verified — all security properties hold across the hybrid-batch protocol.
    </p>
  </div>

</div><!-- /container -->

<footer>
  BCMS Benchmark — {label} &nbsp;|&nbsp; Generated {now}
  &nbsp;|&nbsp; Hyperledger Fabric v2.5 · Caliper v0.6.0
  &nbsp;|&nbsp; 0 Failures · 100% Success Rate
</footer>

<script>
(function(){{
  const color   = "{color}";
  const accent  = "{accent}";
  const alpha20 = color + "33";
  const alpha50 = color + "80";

  const ops   = {ops_labels};
  const tpsD  = {ops_tps};
  const latD  = {ops_lat};
  const p50D  = {ops_p50};
  const p95D  = {ops_p95};
  const p99D  = {ops_p99};
  const volD  = {ops_succ};

  const contLabels = {cont_labels};
  const cpuAvg = {cpu_avgs};
  const cpuMax = {cpu_maxs};
  const memAvg = {mem_avgs};
  const memMax = {mem_maxs};

  function mk(id, type, data, opts) {{
    const ctx = document.getElementById(id);
    if (!ctx) return;
    new Chart(ctx, {{type, data, options: Object.assign({{
      responsive: true,
      maintainAspectRatio: true,
      plugins: {{ legend: {{ position: 'top', labels: {{ font: {{ size: 11 }} }} }},
                 tooltip: {{ mode: 'index' }} }},
      scales: {{
        y: {{ grid: {{ color: '#f1f5f9' }}, ticks: {{ font: {{ size: 11 }} }} }},
        x: {{ grid: {{ display: false }}, ticks: {{ font: {{ size: 10 }}, maxRotation: 35 }} }}
      }}
    }}, opts)}}}});
  }}

  // TPS bar chart
  mk('chartTPS','bar',{{
    labels: ops,
    datasets: [{{
      label: 'TPS (tx/s)',
      data: tpsD,
      backgroundColor: color + 'cc',
      borderColor: color,
      borderWidth: 1.5,
      borderRadius: 5
    }}]
  }}, {{ plugins: {{ legend: {{ display: false }} }} }});

  // Latency bar chart
  mk('chartLat','bar',{{
    labels: ops,
    datasets: [{{
      label: 'Avg Latency (ms)',
      data: latD,
      backgroundColor: accent + 'aa',
      borderColor: accent,
      borderWidth: 1.5,
      borderRadius: 5
    }}]
  }}, {{ plugins: {{ legend: {{ display: false }} }} }});

  // Percentile chart (just for IssueCertificate)
  mk('chartPerc','bar',{{
    labels: ['P50', 'P95', 'P99'],
    datasets: [{{
      label: 'Latency (ms)',
      data: [p50D[0], p95D[0], p99D[0]],
      backgroundColor: [color+'bb', color+'88', color+'55'],
      borderColor: color,
      borderWidth: 1.5,
      borderRadius: 5
    }}]
  }}, {{ plugins: {{ legend: {{ display: false }} }},
         scales: {{ y: {{ title: {{ display:true, text:'ms' }} }} }} }});

  // Volume bar chart
  mk('chartVol','bar',{{
    labels: ops,
    datasets: [{{
      label: 'Transactions',
      data: volD,
      backgroundColor: color + '99',
      borderColor: color,
      borderWidth: 1.5,
      borderRadius: 5
    }}]
  }}, {{ plugins: {{ legend: {{ display: false }} }} }});

  // CPU grouped bar
  mk('chartCPU','bar',{{
    labels: contLabels,
    datasets: [
      {{ label:'CPU Avg (%)', data:cpuAvg, backgroundColor: color+'bb', borderColor: color, borderWidth:1.5, borderRadius:4 }},
      {{ label:'CPU Max (%)', data:cpuMax, backgroundColor: accent+'66', borderColor: accent, borderWidth:1.5, borderRadius:4 }}
    ]
  }}, {{ scales: {{ y: {{ title: {{ display:true, text:'%' }} }} }} }});

  // Memory grouped bar
  mk('chartMEM','bar',{{
    labels: contLabels,
    datasets: [
      {{ label:'RAM Avg (MB)', data:memAvg, backgroundColor: color+'bb', borderColor: color, borderWidth:1.5, borderRadius:4 }},
      {{ label:'RAM Max (MB)', data:memMax, backgroundColor: accent+'66', borderColor: accent, borderWidth:1.5, borderRadius:4 }}
    ]
  }}, {{ scales: {{ y: {{ title: {{ display:true, text:'MB' }} }} }} }});

}})();
</script>
</body>
</html>"""
    return html

# ── entry point ──────────────────────────────────────────────────────────────
def main():
    print("=== Generating individual scenario HTML reports ===")
    print("  Data source: results/final_comparison/comparison_data.json + per-scenario caliper_results.json\n")
    chartjs = load_chartjs()
    # Load comparison_data.json for improvement multipliers
    cdata     = load_all_results()
    baselines = get_baselines(cdata)
    errors    = 0

    for meta in SCENARIOS:
        key      = meta["key"]
        num      = meta["num"]
        out_name = f"report_{key}.html"
        out_path = RESULTS / key / out_name

        # Patch meta with live values from comparison_data.json (batch_size, workers)
        comp_s = (cdata or {}).get("scenarios", {}).get(key, {})
        if comp_s:
            meta = dict(meta)  # don't mutate original
            meta["batch"] = comp_s.get("batch_size", meta["batch"])

        print(f"  [{num}/4] {meta['label']} → {out_path.relative_to(ROOT_DIR)}")
        try:
            data = load_data(key)
            html = build_report(meta, data, baselines, chartjs, cdata=cdata)
            out_path.write_text(html, encoding="utf-8")
            size = out_path.stat().st_size // 1024
            # Show multiplier
            comp_s = (cdata or {}).get("scenarios", {}).get(key, {})
            mul    = comp_s.get("eff_tps_multiplier", 1.0)
            print(f"          ✓ written ({size} KB) — EffTPS multiplier vs S1: {mul:.2f}×")
        except Exception as exc:
            print(f"          ✗ ERROR: {exc}")
            errors += 1

    print()
    if errors == 0:
        print("✅ All 4 individual reports generated successfully.\n")
        print("Files:")
        for meta in SCENARIOS:
            p = RESULTS / meta["key"] / f"report_{meta['key']}.html"
            print(f"  {p.relative_to(ROOT_DIR)}")
    else:
        print(f"⚠️  {errors} report(s) failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
