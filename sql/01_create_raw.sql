-- =============================================================================
-- 01_create_raw.sql
-- Creates immutable raw tables that store data exactly as returned by the APIs.
-- These tables are never overwritten — re-ingest safely without data loss.
-- Cleaning and transformation happens downstream in staging views.
-- =============================================================================

CREATE TABLE raw_311_complaints (
    ingest_id      BIGSERIAL PRIMARY KEY,
    ingested_at    TIMESTAMPTZ DEFAULT NOW(), -- tracks when row was loaded, not created
    unique_key     TEXT,                      -- may be null or duplicate in raw data
    created_date   TEXT,                      -- raw string, not yet cast to timestamp
    closed_date    TEXT,
    complaint_type TEXT,
    descriptor     TEXT,
    borough        TEXT,                      -- dirty: 'MANHATTAN', 'MN', null, etc.
    incident_zip   TEXT,                      -- dirty: '10001', '1001', '0', null
    latitude       TEXT,                      -- stored as text — may be non-numeric
    longitude      TEXT,
    agency         TEXT,
    status         TEXT
);

CREATE TABLE raw_weather_observations (
    ingest_id    BIGSERIAL PRIMARY KEY,
    ingested_at  TIMESTAMPTZ DEFAULT NOW(),
    station_id   TEXT,     -- NOAA station ID e.g. 'USW00094728'
    station_name TEXT,     -- borough name mapped from station ID
    date         TEXT,     -- raw string 'YYYY-MM-DD'
    datatype     TEXT,     -- observation type: 'TMAX', 'TMIN', 'PRCP', 'SNOW', 'AWND'
    value        NUMERIC,  -- metric units: tenths of degrees C or tenths of mm
    attributes   TEXT      -- NOAA quality flags — kept raw for traceability
);

CREATE TABLE pipeline_log (
    run_id       BIGSERIAL PRIMARY KEY,
    ran_at       TIMESTAMPTZ DEFAULT NOW(), -- actual pipeline run time (shown in Power BI)
    rows_311     INTEGER,                   -- 311 rows loaded this run
    rows_weather INTEGER                    -- weather rows loaded this run
);