-- ============================================================
-- Schema Setup: Healthcare Readmissions Project
-- Run this once, after importing the 7 CSVs via DataGrip's
-- "Import Data from File" (patn, vist, diag_1, diag_2, roms, dpmt, bill)
-- ============================================================

-- Fix visit admission/discharge columns: imported as text, need TIMESTAMP
ALTER TABLE stg_ehp_vist
ALTER COLUMN vis_en TYPE TIMESTAMP USING vis_en::timestamp,
ALTER COLUMN vis_ex TYPE TIMESTAMP USING vis_ex::timestamp;

-- Fix bill table: bill_date needs TIMESTAMP, refr_no needs TEXT (was imported as integer)
ALTER TABLE stg_ehp_bill
ALTER COLUMN bill_date TYPE TIMESTAMP USING bill_date::timestamp,
ALTER COLUMN refr_no TYPE TEXT USING refr_no::text;

-- Fix diag_1: dig_seq needs INTEGER, dig_tot needs NUMERIC (was text), dig_en needs TIMESTAMP
ALTER TABLE stg_ehp_diag_1
ALTER COLUMN dig_seq TYPE INTEGER USING dig_seq::integer,
ALTER COLUMN dig_tot TYPE NUMERIC(10,2) USING dig_tot::numeric,
ALTER COLUMN dig_en TYPE TIMESTAMP USING dig_en::timestamp;

-- Fix diag_2: dig_cd needs TEXT (was imported as integer), dig_tot needs NUMERIC, dig_en needs TIMESTAMP
ALTER TABLE stg_ehp_diag_2
ALTER COLUMN dig_cd TYPE TEXT USING dig_cd::text,
ALTER COLUMN dig_tot TYPE NUMERIC(10,2) USING dig_tot::numeric,
ALTER COLUMN dig_en TYPE TIMESTAMP USING dig_en::timestamp;

-- Merge the two diagnosis halves into a single table
CREATE TABLE stg_ehp_diag AS
SELECT * FROM stg_ehp_diag_1
UNION ALL
SELECT * FROM stg_ehp_diag_2;

-- Verify nothing was lost in the merge (combined_count should equal part1 + part2)
SELECT
    (SELECT COUNT(*) FROM stg_ehp_diag_1) AS part1_count,
    (SELECT COUNT(*) FROM stg_ehp_diag_2) AS part2_count,
    (SELECT COUNT(*) FROM stg_ehp_diag)   AS combined_count;

-- Once verified, drop the two halves — stg_ehp_diag is now the single source of truth
DROP TABLE stg_ehp_diag_1;
DROP TABLE stg_ehp_diag_2;
