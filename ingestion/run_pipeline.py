"""
run_pipeline.py
---------------
Main orchestrator for the NYC 311 + Weather ETL pipeline.
Run this script daily to ingest fresh data from both APIs and keep
the Power BI dashboard up to date.

Scheduled via Windows Task Scheduler to run at 5:00 AM daily,
one hour before the Power BI Service scheduled refresh at 6:00 AM.

Usage:
    python ingestion/run_pipeline.py

Author: Alison Hartshorn
"""
import logging
import sys
import os

# Add the ingestion/ directory to path so sibling modules can be imported
# regardless of which directory the script is called from
sys.path.insert(0, os.path.dirname(__file__))

from fetch_311     import fetch_and_load_311
from fetch_weather import fetch_and_load_weather
from db            import get_connection

# Log to console with timestamps and redirect to file in production if needed
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

def run():
    """
    Executes the full pipeline in order:
      1. Fetch last 90 days of NYC 311 complaints → raw_311_complaints
      2. Fetch last 90 days of NOAA weather data  → raw_weather_observations
      3. Log run stats to pipeline_log (visible in Power BI Pipeline Health tab)
      4. Close DB connection regardless of success or failure (finally block)

    On first run, days_back=90 performs the historical backfill.
    For daily runs, change days_back to 2 (311) and 5 (weather) to
    only fetch recent data and reduce runtime from ~20 min to ~2 min.
    """
    log = logging.getLogger(__name__)
    log.info("=== Pipeline start ===")
    conn = get_connection()
    try:
        print("Fetching 311 data...")
        rows_311 = fetch_and_load_311(conn, days_back=90)

        print("Fetching weather data...")
        rows_weather = fetch_and_load_weather(conn, days_back=90)

        # Log run metadata to pipeline_log table so Power BI can display
        # the actual last pipeline run time (more accurate than NOW())
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO pipeline_log (rows_311, rows_weather)
                VALUES (%s, %s)
            """, (rows_311, rows_weather))
        conn.commit()

        log.info(f"Done. 311={rows_311} rows, weather={rows_weather} rows")
        print(f"\n✅ Pipeline complete! {rows_311} complaint rows, {rows_weather} weather rows loaded.")

    except Exception as e:
        # Log full traceback for debugging. pipeline_log will have no entry
        # for failed runs, making failures visible in the dashboard.
        log.error(f"Pipeline failed: {e}", exc_info=True)
        raise # Re-raise so Task Scheduler registers the run as failed
    finally:
        # Always close the connection. Runs even if an exception was raised
        conn.close()

if __name__ == "__main__":
    run()