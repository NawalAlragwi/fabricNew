#!/usr/bin/env python3
import os
import re
import glob
import math
import argparse
import csv

def percentile(data, p):
    """Calculate the p-th percentile of a list of numeric values using linear interpolation."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    n = len(sorted_data)
    if n == 1:
        return sorted_data[0]
    
    k = (n - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_data[int(k)]
    d0 = sorted_data[int(f)] * (c - k)
    d1 = sorted_data[int(c)] * (k - f)
    return d0 + d1

def mean(data):
    return sum(data) / len(data) if data else 0.0

def std_dev(data):
    if len(data) <= 1:
        return 0.0
    m = mean(data)
    variance = sum((x - m) ** 2 for x in data) / (len(data) - 1)
    return math.sqrt(variance)

def parse_report(filepath):
    """Extract metrics from Caliper HTML report."""
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Extract benchmark summary table
        summary_match = re.search(r'id="benchmarksummary".*?</table>', content, re.DOTALL)
        summary_html = summary_match.group(0) if summary_match else content
        rows = re.findall(r'<tr[^>]*>(.*?)</tr>', summary_html, re.DOTALL)
        
        metrics = {}
        for row in rows:
            cells = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
            if len(cells) >= 8:
                clean = [re.sub(r'<[^>]*>', '', c).strip() for c in cells]
                name = clean[0]
                if name in ['IssueCertificate', 'VerifyCertificate']:
                    metrics[name] = {
                        'throughput': float(clean[7]),
                        'avg_latency': float(clean[6]),
                        'max_latency': float(clean[4])
                    }
        
        if 'IssueCertificate' in metrics and 'VerifyCertificate' in metrics:
            return metrics
        return None
    except Exception as e:
        print(f"Warning: Failed to parse {filepath}: {e}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Analyze Caliper HTML benchmark reports.")
    parser.add_argument("--dir", default="./reports", help="Directory containing report HTML files")
    parser.add_argument("--pattern", default="*_report.html", help="Glob pattern for report files")
    args = parser.parse_args()

    search_glob = os.path.join(args.dir, args.pattern)
    report_files = sorted(glob.glob(search_glob))

    if not report_files:
        print(f"Error: No files found matching '{search_glob}'")
        return

    print(f"Found {len(report_files)} report files matching '{args.pattern}' in '{args.dir}'")

    valid_runs = []
    for filepath in report_files:
        metrics = parse_report(filepath)
        if metrics:
            valid_runs.append({
                'filename': os.path.basename(filepath),
                'filepath': filepath,
                'metrics': metrics
            })
        else:
            print(f"Skipping {os.path.basename(filepath)}: missing required rounds (IssueCertificate, VerifyCertificate)")

    if not valid_runs:
        print("Error: No valid runs could be parsed.")
        return

    print(f"Successfully parsed {len(valid_runs)} runs.\n")

    # Define the 6 metrics we are analyzing
    metric_definitions = [
        ('IssueCertificate', 'throughput', 'Issue_TPS', 'TPS'),
        ('IssueCertificate', 'avg_latency', 'Issue_AvgLat', 's'),
        ('IssueCertificate', 'max_latency', 'Issue_MaxLat', 's'),
        ('VerifyCertificate', 'throughput', 'Verify_TPS', 'TPS'),
        ('VerifyCertificate', 'avg_latency', 'Verify_AvgLat', 's'),
        ('VerifyCertificate', 'max_latency', 'Verify_MaxLat', 's'),
    ]

    # Calculate IQR and detect outliers for each run
    outlier_runs = set()
    run_outlier_reasons = {i: [] for i in range(len(valid_runs))}
    metric_stats = {}

    for round_name, field, label, unit in metric_definitions:
        values = [r['metrics'][round_name][field] for r in valid_runs]
        
        # Calculate percentiles and IQR
        q1 = percentile(values, 25)
        q3 = percentile(values, 75)
        iqr = q3 - q1
        lower_bound = q1 - 1.5 * iqr
        upper_bound = q3 + 1.5 * iqr
        
        metric_stats[label] = {
            'values_all': values,
            'q1': q1,
            'q3': q3,
            'iqr': iqr,
            'lower': lower_bound,
            'upper': upper_bound
        }

        # Check for outliers
        for idx, r in enumerate(valid_runs):
            val = r['metrics'][round_name][field]
            if val < lower_bound or val > upper_bound:
                outlier_runs.add(idx)
                run_outlier_reasons[idx].append(
                    f"{label}={val:.4f}{unit} (out of bounds: [{lower_bound:.4f}, {upper_bound:.4f}])"
                )

    clean_runs = [r for idx, r in enumerate(valid_runs) if idx not in outlier_runs]

    # Print Summary Table Header
    print("=" * 105)
    print(f"{'STATISTICAL ANALYSIS REPORT':^105}")
    print("=" * 105)
    print(f"Total Runs: {len(valid_runs)} | Clean Runs: {len(clean_runs)} | Outliers Flagged: {len(outlier_runs)}")
    print("-" * 105)
    print(f"{'Metric':<35} | {'Mean (All)':<12} | {'CV% (All)':<10} | {'Clean Mean':<12} | {'Clean CV%':<10} | {'Min':<10} | {'Max':<10}")
    print("-" * 105)

    summary_rows = []
    
    for round_name, field, label, unit in metric_definitions:
        all_vals = metric_stats[label]['values_all']
        clean_vals = [r['metrics'][round_name][field] for r in clean_runs]
        
        mean_all = mean(all_vals)
        sd_all = std_dev(all_vals)
        cv_all = (sd_all / mean_all * 100) if mean_all else 0.0
        
        mean_clean = mean(clean_vals)
        sd_clean = std_dev(clean_vals)
        cv_clean = (sd_clean / mean_clean * 100) if mean_clean else 0.0
        
        val_min = min(all_vals)
        val_max = max(all_vals)
        
        metric_display_name = f"{round_name} {field.replace('_', ' ').title()} ({unit})"
        print(f"{metric_display_name:<35} | {mean_all:<12.4f} | {cv_all:<9.2f}% | {mean_clean:<12.4f} | {cv_clean:<9.2f}% | {val_min:<10.4f} | {val_max:<10.4f}")
        
        summary_rows.append({
            'Metric': metric_display_name,
            'Mean_All': round(mean_all, 4),
            'StdDev_All': round(sd_all, 4),
            'CV_All': f"{cv_all:.2f}%",
            'Mean_Clean': round(mean_clean, 4),
            'StdDev_Clean': round(sd_clean, 4),
            'CV_Clean': f"{cv_clean:.2f}%",
            'Min': round(val_min, 4),
            'Max': round(val_max, 4),
            'IQR_All': round(metric_stats[label]['iqr'], 4)
        })

    print("-" * 105)
    
    # Print Outliers
    if outlier_runs:
        print("\nFlagged Outlier Runs:")
        for idx in sorted(list(outlier_runs)):
            r = valid_runs[idx]
            reasons = "; ".join(run_outlier_reasons[idx])
            print(f"  • {r['filename']} (Run Index {idx + 1}): {reasons}")
    else:
        print("\nNo outlier runs detected.")
    print("=" * 105)

    # Save to summary.csv
    csv_file = "summary.csv"
    try:
        with open(csv_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            
            # Section 1: Detailed Run Data
            writer.writerow(["SECTION 1: RAW RUN DETAILS"])
            header = ["Run_Index", "Filename", "Is_Outlier", "Outlier_Reasons"]
            for _, _, label, unit in metric_definitions:
                header.append(f"{label}_{unit}")
            writer.writerow(header)
            
            for idx, r in enumerate(valid_runs):
                is_out = idx in outlier_runs
                reasons = "; ".join(run_outlier_reasons[idx]) if is_out else ""
                row = [idx + 1, r['filename'], str(is_out), reasons]
                for round_name, field, _, _ in metric_definitions:
                    row.append(r['metrics'][round_name][field])
                writer.writerow(row)
                
            writer.writerow([]) # Empty spacer
            
            # Section 2: Aggregate Statistics
            writer.writerow(["SECTION 2: AGGREGATE SUMMARY STATISTICS"])
            writer.writerow(["Metric", "Mean_All", "StdDev_All", "CV_All", "Mean_Clean", "StdDev_Clean", "CV_Clean", "Min", "Max", "IQR_All"])
            for s_row in summary_rows:
                writer.writerow([
                    s_row['Metric'],
                    s_row['Mean_All'],
                    s_row['StdDev_All'],
                    s_row['CV_All'],
                    s_row['Mean_Clean'],
                    s_row['StdDev_Clean'],
                    s_row['CV_Clean'],
                    s_row['Min'],
                    s_row['Max'],
                    s_row['IQR_All']
                ])
                
        print(f"\nAnalysis results successfully saved to {csv_file}")
    except Exception as e:
        print(f"Error saving to {csv_file}: {e}")

if __name__ == '__main__':
    main()
