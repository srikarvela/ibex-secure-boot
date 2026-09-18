"""Build reports/ppa.csv and docs/ppa_table.md from committed Vivado reports.

Every number is parsed from reports/<block>/utilization.rpt and
timing_summary.rpt (written by tcl/rot_synth.tcl). Nothing is entered by hand,
so the table and the .rpt files cannot disagree -- the honesty rule from the
sibling repos. If no reports exist yet (no Vivado run has happened), it says so
and writes nothing, rather than inventing rows.
"""
import csv, glob, os, re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
UTIL = {"LUT": "Slice LUTs", "LUT_logic": "LUT as Logic", "LUT_mem": "LUT as Memory",
        "FF": "Slice Registers", "CARRY4": "CARRY4", "DSP": "DSPs", "BRAM": "Block RAM Tile"}

def util_field(text, name):
    m = re.search(r"^\|\s*" + re.escape(name) + r"\s*\|\s*(\d+)\s*\|", text, re.M)
    return int(m.group(1)) if m else None

def slack(text, kind):  # kind: 'setup' or 'hold' -> (WNS/WHS, failing endpoints)
    lab = "WNS" if kind == "setup" else "WHS"
    m = re.search(lab + r"\(ns\).*?\n.*?(-?\d+\.\d+)\s+(\d+)", text, re.S)
    return (float(m.group(1)), int(m.group(2))) if m else (None, None)

def main():
    rows = []
    for d in sorted(glob.glob(os.path.join(ROOT, "reports", "*"))):
        up = os.path.join(d, "utilization.rpt"); tp = os.path.join(d, "timing_summary.rpt")
        if not (os.path.isfile(up) and os.path.isfile(tp)):
            continue
        ut = open(up).read(); tt = open(tp).read()
        wns, wnf = slack(tt, "setup"); whs, whf = slack(tt, "hold")
        row = {"block": os.path.basename(d)}
        for k, name in UTIL.items():
            row[k] = util_field(ut, name)
        row.update(WNS=wns, WNS_fail=wnf, WHS=whs, WHS_fail=whf)
        rows.append(row)
    if not rows:
        print("no committed Vivado reports yet -- run `make vm-synth` first; "
              "nothing written (no numbers are invented).")
        return
    cols = ["block","LUT","LUT_logic","LUT_mem","FF","CARRY4","DSP","BRAM",
            "WNS","WNS_fail","WHS","WHS_fail"]
    with open(os.path.join(ROOT, "reports", "ppa.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(rows)
    with open(os.path.join(ROOT, "docs", "ppa_table.md"), "w") as f:
        f.write("| " + " | ".join(cols) + " |\n|" + "---|"*len(cols) + "\n")
        for r in rows:
            f.write("| " + " | ".join(str(r.get(c, "")) for c in cols) + " |\n")
    print(f"wrote reports/ppa.csv and docs/ppa_table.md ({len(rows)} blocks)")

if __name__ == "__main__":
    main()
