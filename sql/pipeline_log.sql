CREATE TABLE pipeline_log (
    run_id      BIGSERIAL PRIMARY KEY,
    ran_at      TIMESTAMPTZ DEFAULT NOW(),
    rows_311    INTEGER,
    rows_weather INTEGER
);

SELECT * FROM pipeline_log ORDER BY ran_at DESC LIMIT 5;