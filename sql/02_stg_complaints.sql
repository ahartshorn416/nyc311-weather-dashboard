-- =============================================================================
-- 02_stg_complaints.sql
-- Staging view that cleans and standardizes raw 311 complaint data.
-- Handles: deduplication, borough normalization, timestamp casting,
--          coordinate validation, zip validation, and resolution time calc.
-- =============================================================================

CREATE VIEW stg_complaints AS

-- Step 1: Deduplicate by unique_key, keeping the most recently ingested version
WITH deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY unique_key
               ORDER BY ingested_at DESC  -- latest ingestion wins
           ) AS rn
    FROM raw_311_complaints
    WHERE unique_key IS NOT NULL          -- exclude rows with no identifier
),

cleaned AS (
    SELECT
        unique_key,

        -- Cast raw date strings to proper timestamps
        -- Format: '2026-01-15T08:30:00.000'
        TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS') AS created_at,
        TO_TIMESTAMP(closed_date,  'YYYY-MM-DD"T"HH24:MI:SS.MS') AS closed_at,
        TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')::DATE AS complaint_date,

        -- Normalize inconsistent borough names to standard values.
        -- Raw data contains: 'MANHATTAN', 'MN', 'manhattan', nulls, etc.
        CASE UPPER(TRIM(borough))
            WHEN 'MANHATTAN'     THEN 'Manhattan'
            WHEN 'MN'            THEN 'Manhattan'
            WHEN 'BRONX'         THEN 'Bronx'
            WHEN 'BX'            THEN 'Bronx'
            WHEN 'BROOKLYN'      THEN 'Brooklyn'
            WHEN 'BK'            THEN 'Brooklyn'
            WHEN 'QUEENS'        THEN 'Queens'
            WHEN 'QN'            THEN 'Queens'
            WHEN 'STATEN ISLAND' THEN 'Staten Island'
            WHEN 'SI'            THEN 'Staten Island'
            ELSE 'Unknown'        -- flagged in Pipeline Health dashboard tab
        END AS borough,

        -- Standardize complaint type casing e.g. 'NOISE - RESIDENTIAL' → 'Noise - Residential'
        INITCAP(TRIM(complaint_type)) AS complaint_type,

        -- Validate zip: must be exactly 5 digits — rejects '1001', '100011', nulls
        CASE WHEN incident_zip ~ '^[0-9]{5}$'
             THEN incident_zip ELSE NULL
        END AS zip_code,

        -- Validate coordinates: must be numeric AND within NYC bounding box
        -- Rejects coordinates from other cities, oceans, or data entry errors
        CASE WHEN latitude  ~ '^-?[0-9]+\.?[0-9]*$'
             AND longitude ~ '^-?[0-9]+\.?[0-9]*$'
             AND latitude::NUMERIC  BETWEEN 40.4 AND 41.0   -- NYC lat range
             AND longitude::NUMERIC BETWEEN -74.3 AND -73.7 -- NYC lon range
             THEN latitude::NUMERIC ELSE NULL
        END AS lat,

        CASE WHEN latitude  ~ '^-?[0-9]+\.?[0-9]*$'
             AND longitude ~ '^-?[0-9]+\.?[0-9]*$'
             AND latitude::NUMERIC  BETWEEN 40.4 AND 41.0
             AND longitude::NUMERIC BETWEEN -74.3 AND -73.7
             THEN longitude::NUMERIC ELSE NULL
        END AS lon,

        -- Resolution time in hours.
        -- NULL if: no closed date, or closed date is before created date (data error)
        CASE WHEN closed_date IS NOT NULL
             AND TO_TIMESTAMP(closed_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
                 > TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
             THEN EXTRACT(EPOCH FROM (
                     TO_TIMESTAMP(closed_date,  'YYYY-MM-DD"T"HH24:MI:SS.MS') -
                     TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
                  )) / 3600.0
             ELSE NULL
        END AS resolution_hours

    FROM deduped
    WHERE rn = 1  -- keep only the most recent ingestion of each unique_key
)

SELECT * FROM cleaned
WHERE created_at IS NOT NULL    -- drop rows where date string couldn't be parsed
  AND created_at >= '2024-08-01'; -- project scope: data from Aug 2024 onward