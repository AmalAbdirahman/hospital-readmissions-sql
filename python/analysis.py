from sqlalchemy import create_engine
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

engine = create_engine("postgresql://postgres:****/healthcare_db")

query = """
WITH visit_gaps AS (
    SELECT
        pat_id, refr_no, vis_en, vis_ex,
        LAG(vis_ex) OVER (PARTITION BY pat_id ORDER BY vis_en) AS prev_discharge
    FROM stg_ehp_vist
),
primary_diagnosis AS (
    SELECT refr_no, dig_des, rom_id
    FROM stg_ehp__diag
    WHERE dig_seq = 1
),
readmit_flags AS (
    SELECT
        vg.pat_id, vg.refr_no, pd.dig_des, r.dep_id,
        (vg.vis_en - vg.prev_discharge) BETWEEN INTERVAL '0 days' AND INTERVAL '30 days' AS is_readmission
    FROM visit_gaps vg
    JOIN primary_diagnosis pd ON pd.refr_no = vg.refr_no
    JOIN stg_ehp_roms r ON r.rom_id = pd.rom_id
    WHERE vg.prev_discharge IS NOT NULL
      AND vg.vis_en >= vg.prev_discharge
)
SELECT
    rf.dig_des, rf.dep_id,
    COUNT(*) AS total_visits,
    SUM(CASE WHEN rf.is_readmission THEN 1 ELSE 0 END) AS readmissions,
    ROUND(100.0 * SUM(CASE WHEN rf.is_readmission THEN 1 ELSE 0 END) / COUNT(*), 1) AS readmission_rate_pct,
    ROUND(AVG(b.bill_amt), 2) AS avg_bill_amount
FROM readmit_flags rf
LEFT JOIN stg_ehp_bill b ON b.refr_no = rf.refr_no
GROUP BY rf.dig_des, rf.dep_id
ORDER BY readmission_rate_pct DESC;
"""

df = pd.read_sql(query, engine)

# ── validate before charting ──
print(df.shape)
print(df["total_visits"].describe())
# set your real cutoff based on what describe() actually shows —
# 100 was calibrated on stale numbers, confirm this is still right
CUTOFF = 100
df_reliable = df[df["total_visits"] >= CUTOFF].copy()
print(f"Kept {len(df_reliable)} of {len(df)} rows at cutoff={CUTOFF}")

# ── Chart 1: bubble scatter, full data, sized by sample size ──
plt.figure(figsize=(9, 6))
sns.scatterplot(
    data=df, x="readmission_rate_pct", y="avg_bill_amount",
    size="total_visits", sizes=(20, 300), alpha=0.6, legend="brief"
)
plt.xlabel("30-Day Readmission Rate (%)")
plt.ylabel("Average Bill Amount ($)")
plt.title("Readmission Rate vs Average Cost (bubble size = sample size)")
plt.tight_layout()
plt.savefig("readmission_vs_cost.png", dpi=150)
plt.show()

corr = df["readmission_rate_pct"].corr(df["avg_bill_amount"])
print(f"Correlation between readmission rate and avg cost: {corr:.2f}")

# ── Chart 2: top 15 diagnosis/department combos ──
top15 = df_reliable.nlargest(15, "readmission_rate_pct")
top15["label"] = top15["dig_des"] + " (" + top15["dep_id"] + ")"

plt.figure(figsize=(10, 7))
sns.barplot(data=top15, y="label", x="readmission_rate_pct", hue="label", legend=False, palette="Reds_r")
plt.xlabel("30-Day Readmission Rate (%)")
plt.ylabel("")
plt.title(f"Top 15 Diagnosis/Department Combinations by Readmission Rate\n(min. {CUTOFF} visits)")
plt.tight_layout()
plt.savefig("readmission_top15.png", dpi=150)
plt.show()

# ── Chart 3: readmission rate by department, aggregated ──
dept_summary = (
    df_reliable.groupby("dep_id")
    .agg(total_visits=("total_visits", "sum"), readmissions=("readmissions", "sum"))
    .reset_index()
)
dept_summary["readmission_rate_pct"] = round(100 * dept_summary["readmissions"] / dept_summary["total_visits"], 1)
dept_summary = dept_summary.sort_values("readmission_rate_pct", ascending=False).head(15)

plt.figure(figsize=(10, 6))
sns.barplot(data=dept_summary, y="dep_id", x="readmission_rate_pct", hue="dep_id", legend=False, palette="Blues_r")
plt.xlabel("30-Day Readmission Rate (%)")
plt.ylabel("Department")
plt.title("Readmission Rate by Department (aggregated across diagnoses)")
plt.tight_layout()
plt.savefig("readmission_by_dept.png", dpi=150)
plt.show()

# ── export summary table ──
df_reliable.to_csv("readmission_summary.csv", index=False)
print("Saved: readmission_vs_cost.png, readmission_top15.png, readmission_by_dept.png, readmission_summary.csv")

