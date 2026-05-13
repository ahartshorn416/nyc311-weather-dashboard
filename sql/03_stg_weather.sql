-- =============================================================================
-- 03_stg_weather.sql
-- Staging view that pivots NOAA weather data from long to wide format
-- and approximates missing borough coverage for Bronx and Brooklyn.
--
-- Raw data is long format: one row per datatype per station per day.
-- This view produces: one row per borough per day with all metrics as columns.
--
-- Borough approximations (no dedicated stations exist in GHCND):
--   Bronx    → Manhattan (Central Park) — geographically closest
--   Brooklyn → Queens (JFK/LaGuardia average) — geographically closest
-- =============================================================================

CREATE VIEW stg_weather_daily AS

WITH base AS (
    -- Pivot long-format observations into wide-format daily summaries per borough
    SELECT
        station_name                                       AS borough,
        date::DATE                                         AS obs_date,
        MAX(CASE WHEN datatype = 'TMAX' THEN value END)   AS temp_max_c,
        MAX(CASE WHEN datatype = 'TMIN' THEN value END)   AS temp_min_c,
        -- Average of TMAX and TMIN — NOAA doesn't provide a direct TAVG for all stations
        ROUND(((MAX(CASE WHEN datatype = 'TMAX' THEN value END) +
                MAX(CASE WHEN datatype = 'TMIN' THEN value END)) / 2)::NUMERIC, 1)
                                                           AS temp_avg_c,
        MAX(CASE WHEN datatype = 'PRCP' THEN value END)   AS precipitation_mm,
        MAX(CASE WHEN datatype = 'SNOW' THEN value END)   AS snowfall_mm,
        MAX(CASE WHEN datatype = 'AWND' THEN value END)   AS wind_speed_ms
    FROM raw_weather_observations
    GROUP BY station_name, date::DATE
),

-- Add Bronx rows using Manhattan data (no Bronx GHCND station available)
with_bronx AS (
    SELECT * FROM base
    UNION ALL
    SELECT 'Bronx', obs_date, temp_max_c, temp_min_c, temp_avg_c,
           precipitation_mm, snowfall_mm, wind_speed_ms
    FROM base WHERE borough = 'Manhattan'
),

-- Add Brooklyn rows using Queens data (no Brooklyn GHCND station available)
with_brooklyn AS (
    SELECT * FROM with_bronx
    UNION ALL
    SELECT 'Brooklyn', obs_date, temp_max_c, temp_min_c, temp_avg_c,
           precipitation_mm, snowfall_mm, wind_speed_ms
    FROM base WHERE borough = 'Queens'
)

SELECT * FROM with_brooklyn;