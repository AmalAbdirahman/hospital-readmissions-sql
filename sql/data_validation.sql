-- ============================================================
-- Data Validation Checks
-- Run before trusting the readmission analysis — these queries
-- surfaced real data quality issues worth documenting in the README.
-- ============================================================

-- How many distinct admission dates exist across all visits?
SELECT COUNT(DISTINCT vis_en::date) AS distinct_admission_dates
FROM stg_ehp_vist;

-- Length of stay: is this dataset's timing realistic?
-- Finding: average stay ~100 days, max ~201 days — far beyond real-world
-- hospital averages (typically 4-6 days). Confirms this is synthetic data.
SELECT
    MIN(vis_ex - vis_en) AS shortest_stay,
    MAX(vis_ex - vis_en) AS longest_stay,
    AVG(vis_ex - vis_en) AS avg_stay
FROM stg_ehp_vist;

-- Does dig_seq = 1 reliably mean "primary diagnosis"?
-- Finding: yes — counts decrease monotonically from seq 1 to 10,
-- consistent with primary/secondary/tertiary diagnosis ordering.
SELECT dig_seq, COUNT(*)
FROM stg_ehp_diag
GROUP BY dig_seq
ORDER BY dig_seq
LIMIT 10;

-- What visit statuses exist, and do any have missing discharge dates?
-- Finding: all three statuses (Admitted, Discharged, Need Follow-Up)
-- have a discharge date on 100% of rows — status doesn't gate on
-- completeness in this dataset, so no status-based filtering is applied.
SELECT vstat_des,
       COUNT(*) AS total,
       COUNT(vis_ex) AS has_discharge_date,
       COUNT(*) - COUNT(vis_ex) AS missing_discharge_date
FROM stg_ehp_vist
GROUP BY vstat_des;

-- Headline data quality finding: what % of consecutive visit pairs
-- have a NEGATIVE gap (next admission before previous discharge —
-- a physically impossible timeline)?
-- Finding: 45% of pairs are negative. This is excluded from the main
-- analysis (see readmission_analysis.sql) and documented as a core
-- limitation of this synthetic dataset.
WITH visit_gaps AS (
    SELECT pat_id, vis_en,
        LAG(vis_ex) OVER (PARTITION BY pat_id ORDER BY vis_en) AS prev_discharge
    FROM stg_ehp_vist
)
SELECT
    COUNT(*) AS total_gaps,
    SUM(CASE WHEN (vis_en - prev_discharge) < INTERVAL '0 days' THEN 1 ELSE 0 END) AS negative_gaps,
    ROUND(100.0 * SUM(CASE WHEN (vis_en - prev_discharge) < INTERVAL '0 days' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_negative
FROM visit_gaps
WHERE prev_discharge IS NOT NULL;
