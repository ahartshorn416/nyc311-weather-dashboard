"""
fetch_weather.py
----------------
Fetches daily weather observations from the NOAA Global Historical Climatology
Network (GHCN) via the Climate Data Online (CDO) REST API and loads them into
the raw_weather_observations PostgreSQL table.

Data is fetched per station in long format (one row per datatype per day).
The stg_weather_daily SQL view later pivots this into wide format with one
row per borough per day.

Key datatypes collected: TMAX, TMIN, PRCP, SNOW, SNWD, AWND
Units: metric (degrees Celsius, millimeters)

Author: Alison Hartshorn
"""

import os
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv

# Load NOAA token from .env. Never hardcoded in source code
load_dotenv()

NOAA_TOKEN = os.getenv("NOAA_TOKEN")
BASE_URL   = "https://www.ncei.noaa.gov/cdo-web/api/v2/data"

# Primary NYC weather stations mapped to their closest borough.
# Note: No dedicated Bronx or Brooklyn stations exist in GHCND.
# These boroughs are approximated in stg_weather_daily using
# Manhattan (Bronx) and Queens (Brooklyn) data respectively.
STATIONS = {
    "USW00094728": "Manhattan",   # Central Park (most central NYC station)
    "USW00094789": "Queens",      # JFK
    "USW00014732": "Queens",      # LaGuardia Airport (averaged with JFK for Queens)
    "USW00014734": "Staten Island" # Newark (closest to Staten Island)
}

def fetch_and_load_weather(conn, days_back=5):
    """
    Fetches weather observations for all 4 NYC stations over the last
    `days_back` days and inserts them into raw_weather_observations.

    Fetches 5 days by default (vs 2 for 311) to account for NOAA's
    occasional 1-2 day reporting lag at some stations.

    Returns total number of observation rows inserted.
    """
    end_date   = datetime.now().strftime("%Y-%m-%d")
    start_date = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%d")
    total      = 0

    for station_id, borough in STATIONS.items():
        params = {
            "datasetid":  "GHCND",  # Global Historical Climatology Network Daily
            "stationid":  f"GHCND:{station_id}", # NOAA requires "GHCND:" prefix on station IDs
            "startdate":  start_date,
            "enddate":    end_date,
            "limit":      1000, # Max allowed per NOAA CDO request
            "units":      "metric"  # Returns Celsius and mm instead of Fahrenheit/inches
        }

        # NOAA CDO uses token in header rather than query param
        headers = {"token": NOAA_TOKEN}
        resp = requests.get(BASE_URL, params=params, headers=headers, timeout=60)

        if resp.status_code == 200:
            data = resp.json().get("results", [])
            insert_weather_rows(conn, data, station_id, borough)
            total += len(data)
            print(f"  {borough} ({station_id}): {len(data)} observations")
        else:
            # Non-fatal, log the warning and continue to next station
            # Common causes: station offline, rate limit hit (1,000 req/day max)
            print(f"  WARNING: {station_id} returned {resp.status_code}")

    return total

def insert_weather_rows(conn, rows, station_id, station_name):
    """
    Inserts a list of NOAA observation dicts into raw_weather_observations.
    Data is stored in long format (one row per datatype per day per station)
    exactly as returned by the API — no transformations applied here.

    The [:10] slice on date strips the time component from ISO timestamps
    e.g. '2026-04-15T00:00:00' → '2026-04-15'
    """
    with conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO raw_weather_observations
                    (station_id, station_name, date, datatype, value, attributes)
                VALUES (%s,%s,%s,%s,%s,%s)
            """, (
                station_id,
                station_name,
                r.get("date", "")[:10], # Strip time component, keep date only
                r.get("datatype"), # ex. 'TMAX', 'TMIN', 'PRCP', 'SNOW'
                r.get("value"), # Numeric value in metric units
                r.get("attributes")  # Quality flags kept raw for traceability
            ))

    # Single commit per station batch for efficiency
    conn.commit()