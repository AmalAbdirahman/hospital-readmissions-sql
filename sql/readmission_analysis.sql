-- ============================================================
-- Readmission Analysis: 30-Day Readmission Rate & Cost
-- by Diagnosis and Department
-- Run this after schema_setup.sql
-- ============================================================

WITH visit_gaps AS (
    -- For each patient, get the gap between one visit's admission
    -- and their previous visit's discharge
    SELECT
        pat_id,
        refr_no,
        vis_en,
        vis_ex,
        LAG(vis_ex) OVER (
            PARTITION BY pat_id
            ORDER BY vis_en
        ) AS prev_discharge
    FROM stg_ehp_vist
),

primary_diagnosis AS (
    -- One diagnosis per visit: the primary one (dig_seq = 1)
    SELECT refr_no, dig_des, rom_id
    FROM stg_ehp_diag
    WHERE dig_seq = 1
),

readmit_flags AS (
    SELECT
        vg.pat_id,
        vg.refr_no,
        pd.dig_des,
        r.dep_id,
        (vg.vis_en - vg.prev_discharge)
            BETWEEN INTERVAL '0 days' AND INTERVAL '30 days' AS is_readmission
    FROM visit_gaps vg
    JOIN primary_diagnosis pd ON pd.refr_no = vg.refr_no
    JOIN stg_ehp_roms r ON r.rom_id = pd.rom_id
    WHERE vg.prev_discharge IS NOT NULL      -- exclude each patient's first visit (nothing to compare)
      AND vg.vis_en >= vg.prev_discharge     -- exclude ~45% of pairs with impossible/overlapping timelines
                                              -- (documented data quality finding — see data_validation.sql)
)

SELECT
    rf.dig_des,
    rf.dep_id,
    COUNT(*) AS total_visits,
    SUM(CASE WHEN rf.is_readmission THEN 1 ELSE 0 END) AS readmissions,
    ROUND(100.0 * SUM(CASE WHEN rf.is_readmission THEN 1 ELSE 0 END) / COUNT(*), 1) AS readmission_rate_pct,
    ROUND(AVG(b.bill_amt), 2) AS avg_bill_amount
FROM readmit_flags rf
LEFT JOIN stg_ehp_bill b ON b.refr_no = rf.refr_no  -- LEFT JOIN: don't silently drop visits with no bill record
GROUP BY rf.dig_des, rf.dep_id
ORDER BY readmission_rate_pct DESC;
