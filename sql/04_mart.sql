-- =============================================================================
-- 04_mart.sql
-- Creates the mart_complaints_weather materialized view — the main fact table
-- that Power BI connects to via DirectQuery.
--
-- Joins cleaned 311 complaints with daily weather by date + borough,
-- aggregates to one row per complaint_type per borough per day,
-- and adds derived weather bucket columns for slicer filtering in Power BI.
--
-- Refresh daily after pipeline run:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mart_complaints_weather;
-- =============================================================================

CREATE MATERIALIZED VIEW mart_complaints_weather AS
SELECT
    c.complaint_date,
    c.borough,
    c.complaint_type,
    COUNT(*)                AS complaint_count,     -- total complaints for this group
    AVG(c.resolution_hours) AS avg_resolution_hrs,  -- avg hours to close (nulls excluded)

    -- Weather metrics joined by date + borough
    w.temp_max_c,
    w.temp_min_c,
    w.temp_avg_c,
    w.precipitation_mm,
    w.snowfall_mm,
    w.wind_speed_ms,

    -- Temperature bucket for slicer filtering in Power BI Weather Correlation tab
    CASE
        WHEN w.temp_max_c >= 32 THEN 'Extreme Heat (32°C+)'
        WHEN w.temp_max_c >= 27 THEN 'Hot (27–32°C)'
        WHEN w.temp_max_c >= 18 THEN 'Warm (18–27°C)'
        WHEN w.temp_max_c >= 5  THEN 'Cool (5–18°C)'
        ELSE                         'Cold (below 5°C)'
    END AS temp_category,

    -- Precipitation bucket for slicer filtering in Power BI Weather Correlation tab
    CASE
        WHEN w.precipitation_mm > 25 THEN 'Heavy Rain'
        WHEN w.precipitation_mm > 5  THEN 'Moderate Rain'
        WHEN w.precipitation_mm > 0  THEN 'Light Rain'
        ELSE                              'Dry'
    END AS precip_category

FROM stg_complaints c

-- LEFT JOIN preserves all complaint rows even where weather data is missing
-- Unmatched rows will have NULL weather columns (visible in Pipeline Health tab)
LEFT JOIN stg_weather_daily w
    ON c.complaint_date = w.obs_date
    AND c.borough       = w.borough

-- Aggregate to one row per date + borough + complaint type combination
GROUP BY
    c.complaint_date, c.borough, c.complaint_type,
    w.temp_max_c, w.temp_min_c, w.temp_avg_c,
    w.precipitation_mm, w.snowfall_mm, w.wind_speed_ms;


-- =============================================================================
-- Data Quality Checks — run after each pipeline execution
-- =============================================================================

-- TEST 1: Verify total row count (~38K expected)
SELECT COUNT(*) FROM mart_complaints_weather;

-- TEST 2: Check weather join rate — target >95%
SELECT
    COUNT(*)                                                           AS total_rows,
    SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END)                  AS rows_with_weather,
    ROUND(100.0 * SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END)
          / COUNT(*), 1)                                               AS pct_matched
FROM mart_complaints_weather;

-- TEST 3: Identify unmatched rows by borough (should only be 'Unknown')
SELECT borough, complaint_date, COUNT(*) AS unmatched
FROM mart_complaints_weather
WHERE temp_max_c IS NULL
GROUP BY borough, complaint_date
ORDER BY complaint_date
LIMIT 20;