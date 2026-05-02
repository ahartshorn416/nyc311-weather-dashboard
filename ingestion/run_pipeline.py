import logging
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from fetch_311     import fetch_and_load_311
from fetch_weather import fetch_and_load_weather
from db            import get_connection

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

def run():
    log = logging.getLogger(__name__)
    log.info("=== Pipeline start ===")
    conn = get_connection()
    try:
        print("Fetching 311 data...")
        rows_311 = fetch_and_load_311(conn, days_back=90)

        print("Fetching weather data...")
        rows_weather = fetch_and_load_weather(conn, days_back=90)

        log.info(f"Done. 311={rows_311} rows, weather={rows_weather} rows")
        print(f"\n✅ Pipeline complete! {rows_311} complaint rows, {rows_weather} weather rows loaded.")
    except Exception as e:
        log.error(f"Pipeline failed: {e}", exc_info=True)
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    run()