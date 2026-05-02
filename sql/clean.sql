CREATE TABLE raw_311_complaints (
    ingest_id        BIGSERIAL PRIMARY KEY,
    ingested_at      TIMESTAMPTZ DEFAULT NOW(),
    unique_key       TEXT,
    created_date     TEXT,
    closed_date      TEXT,
    complaint_type   TEXT,
    descriptor       TEXT,
    borough          TEXT,
    incident_zip     TEXT,
    latitude         TEXT,
    longitude        TEXT,
    agency           TEXT,
    status           TEXT
);

CREATE TABLE raw_weather_observations (
    ingest_id    BIGSERIAL PRIMARY KEY,
    ingested_at  TIMESTAMPTZ DEFAULT NOW(),
    station_id   TEXT,
    station_name TEXT,
    date         TEXT,
    datatype     TEXT,
    value        NUMERIC,
    attributes   TEXT
);

-- Check row counts
SELECT 'raw_311_complaints' AS table_name, COUNT(*) AS rows FROM raw_311_complaints
UNION ALL
SELECT 'raw_weather_observations', COUNT(*) FROM raw_weather_observations;

-- Preview 311 data — spot the messiness
SELECT borough, complaint_type, created_date, latitude, longitude
FROM raw_311_complaints
LIMIT 20;

-- Preview weather data
SELECT station_name, date, datatype, value
FROM raw_weather_observations
ORDER BY date DESC
LIMIT 20;

CREATE VIEW stg_weather_daily AS
SELECT
    station_name                                    AS borough,
    date::DATE                                      AS obs_date,
    MAX(CASE WHEN datatype = 'TMAX' THEN value END) AS temp_max_c,
    MAX(CASE WHEN datatype = 'TMIN' THEN value END) AS temp_min_c,
    ROUND(((MAX(CASE WHEN datatype = 'TMAX' THEN value END) +
             MAX(CASE WHEN datatype = 'TMIN' THEN value END)) / 2)::NUMERIC, 1)
                                                    AS temp_avg_c,
    MAX(CASE WHEN datatype = 'PRCP' THEN value END) AS precipitation_mm,
    MAX(CASE WHEN datatype = 'SNOW' THEN value END) AS snowfall_mm,
    MAX(CASE WHEN datatype = 'AWND' THEN value END) AS wind_speed_ms
FROM raw_weather_observations
GROUP BY station_name, date::DATE;

CREATE VIEW stg_complaints AS
WITH deduped AS (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY unique_key
               ORDER BY ingested_at DESC
           ) AS rn
    FROM raw_311_complaints
    WHERE unique_key IS NOT NULL
),
cleaned AS (
    SELECT
        unique_key,
        TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS') AS created_at,
        TO_TIMESTAMP(closed_date,  'YYYY-MM-DD"T"HH24:MI:SS.MS') AS closed_at,
        TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')::DATE AS complaint_date,

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
            ELSE 'Unknown'
        END AS borough,

        INITCAP(TRIM(complaint_type)) AS complaint_type,

        CASE WHEN incident_zip ~ '^[0-9]{5}$'
             THEN incident_zip ELSE NULL
        END AS zip_code,

        CASE WHEN latitude  ~ '^-?[0-9]+\.?[0-9]*$'
             AND longitude ~ '^-?[0-9]+\.?[0-9]*$'
             AND latitude::NUMERIC  BETWEEN 40.4 AND 41.0
             AND longitude::NUMERIC BETWEEN -74.3 AND -73.7
             THEN latitude::NUMERIC ELSE NULL
        END AS lat,

        CASE WHEN latitude  ~ '^-?[0-9]+\.?[0-9]*$'
             AND longitude ~ '^-?[0-9]+\.?[0-9]*$'
             AND latitude::NUMERIC  BETWEEN 40.4 AND 41.0
             AND longitude::NUMERIC BETWEEN -74.3 AND -73.7
             THEN longitude::NUMERIC ELSE NULL
        END AS lon,

        CASE WHEN closed_date IS NOT NULL
             AND TO_TIMESTAMP(closed_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
                 > TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
             THEN EXTRACT(EPOCH FROM (
                     TO_TIMESTAMP(closed_date,  'YYYY-MM-DD"T"HH24:MI:SS.MS') -
                     TO_TIMESTAMP(created_date, 'YYYY-MM-DD"T"HH24:MI:SS.MS')
                  )) / 3600.0
             ELSE NULL
        END AS resolution_hours

    FROM deduped WHERE rn = 1
)
SELECT * FROM cleaned
WHERE created_at IS NOT NULL
  AND created_at >= '2024-08-01';

-- Should show ~900k+ rows
SELECT COUNT(*) FROM stg_complaints;

-- Should show clean borough names only
SELECT borough, COUNT(*) FROM stg_complaints GROUP BY borough ORDER BY 2 DESC;

-- Should show pivoted weather columns
SELECT * FROM stg_weather_daily LIMIT 10;

CREATE MATERIALIZED VIEW mart_complaints_weather AS
SELECT
    c.complaint_date,
    c.borough,
    c.complaint_type,
    COUNT(*)                AS complaint_count,
    AVG(c.resolution_hours) AS avg_resolution_hrs,

    w.temp_max_c,
    w.temp_min_c,
    w.temp_avg_c,
    w.precipitation_mm,
    w.snowfall_mm,
    w.wind_speed_ms,

    CASE
        WHEN w.temp_max_c >= 32 THEN 'Extreme Heat (32°C+)'
        WHEN w.temp_max_c >= 27 THEN 'Hot (27–32°C)'
        WHEN w.temp_max_c >= 18 THEN 'Warm (18–27°C)'
        WHEN w.temp_max_c >= 5  THEN 'Cool (5–18°C)'
        ELSE                         'Cold (below 5°C)'
    END AS temp_category,

    CASE
        WHEN w.precipitation_mm > 25 THEN 'Heavy Rain'
        WHEN w.precipitation_mm > 5  THEN 'Moderate Rain'
        WHEN w.precipitation_mm > 0  THEN 'Light Rain'
        ELSE                              'Dry'
    END AS precip_category

FROM stg_complaints c
LEFT JOIN stg_weather_daily w
    ON c.complaint_date = w.obs_date
    AND c.borough       = w.borough
GROUP BY
    c.complaint_date, c.borough, c.complaint_type,
    w.temp_max_c, w.temp_min_c, w.temp_avg_c,
    w.precipitation_mm, w.snowfall_mm, w.wind_speed_ms;

	-- Row count
SELECT COUNT(*) FROM mart_complaints_weather;

-- Check weather join rate
SELECT
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END)   AS rows_with_weather,
    ROUND(100.0 * SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END) / COUNT(*), 1) AS pct_matched
FROM mart_complaints_weather;

-- Preview the data
SELECT * FROM mart_complaints_weather LIMIT 10;

-- What boroughs exist in the weather data?
SELECT DISTINCT borough, obs_date
FROM stg_weather_daily
ORDER BY obs_date DESC
LIMIT 20;

-- Add Bronx using Manhattan station (closest approximation)
-- Add Brooklyn using Queens station (closest approximation)
-- Then re-pull weather going back further

DROP VIEW stg_weather_daily CASCADE;

-- Add Bronx using Manhattan station (closest approximation)
-- Add Brooklyn using Queens station (closest approximation)
-- Then re-pull weather going back further

DROP VIEW stg_weather_daily;

CREATE VIEW stg_weather_daily AS
WITH base AS (
    SELECT
        station_name                                       AS borough,
        date::DATE                                         AS obs_date,
        MAX(CASE WHEN datatype = 'TMAX' THEN value END)   AS temp_max_c,
        MAX(CASE WHEN datatype = 'TMIN' THEN value END)   AS temp_min_c,
        ROUND(((MAX(CASE WHEN datatype = 'TMAX' THEN value END) +
                MAX(CASE WHEN datatype = 'TMIN' THEN value END)) / 2)::NUMERIC, 1)
                                                           AS temp_avg_c,
        MAX(CASE WHEN datatype = 'PRCP' THEN value END)   AS precipitation_mm,
        MAX(CASE WHEN datatype = 'SNOW' THEN value END)   AS snowfall_mm,
        MAX(CASE WHEN datatype = 'AWND' THEN value END)   AS wind_speed_ms
    FROM raw_weather_observations
    GROUP BY station_name, date::DATE
),
with_bronx AS (
    SELECT * FROM base
    UNION ALL
    SELECT 'Bronx', obs_date, temp_max_c, temp_min_c, temp_avg_c,
           precipitation_mm, snowfall_mm, wind_speed_ms
    FROM base WHERE borough = 'Manhattan'
),
with_brooklyn AS (
    SELECT * FROM with_bronx
    UNION ALL
    SELECT 'Brooklyn', obs_date, temp_max_c, temp_min_c, temp_avg_c,
           precipitation_mm, snowfall_mm, wind_speed_ms
    FROM base WHERE borough = 'Queens'
)
SELECT * FROM with_brooklyn

CREATE MATERIALIZED VIEW mart_complaints_weather AS
SELECT
    c.complaint_date,
    c.borough,
    c.complaint_type,
    COUNT(*)                AS complaint_count,
    AVG(c.resolution_hours) AS avg_resolution_hrs,
    w.temp_max_c,
    w.temp_min_c,
    w.temp_avg_c,
    w.precipitation_mm,
    w.snowfall_mm,
    w.wind_speed_ms,
    CASE
        WHEN w.temp_max_c >= 32 THEN 'Extreme Heat (32°C+)'
        WHEN w.temp_max_c >= 27 THEN 'Hot (27–32°C)'
        WHEN w.temp_max_c >= 18 THEN 'Warm (18–27°C)'
        WHEN w.temp_max_c >= 5  THEN 'Cool (5–18°C)'
        ELSE                         'Cold (below 5°C)'
    END AS temp_category,
    CASE
        WHEN w.precipitation_mm > 25 THEN 'Heavy Rain'
        WHEN w.precipitation_mm > 5  THEN 'Moderate Rain'
        WHEN w.precipitation_mm > 0  THEN 'Light Rain'
        ELSE                              'Dry'
    END AS precip_category
FROM stg_complaints c
LEFT JOIN stg_weather_daily w
    ON c.complaint_date = w.obs_date
    AND c.borough       = w.borough
GROUP BY
    c.complaint_date, c.borough, c.complaint_type,
    w.temp_max_c, w.temp_min_c, w.temp_avg_c,
    w.precipitation_mm, w.snowfall_mm, w.wind_speed_ms

SELECT
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END)   AS rows_with_weather,
    ROUND(100.0 * SUM(CASE WHEN temp_max_c IS NOT NULL THEN 1 END) / COUNT(*), 1) AS pct_matched
FROM mart_complaints_weather

SELECT borough, complaint_date, COUNT(*) AS unmatched
FROM mart_complaints_weather
WHERE temp_max_c IS NULL
GROUP BY borough, complaint_date
ORDER BY complaint_date
LIMIT 20;