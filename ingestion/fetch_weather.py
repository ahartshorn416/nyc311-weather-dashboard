import os
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

NOAA_TOKEN = os.getenv("NOAA_TOKEN")
BASE_URL   = "https://www.ncei.noaa.gov/cdo-web/api/v2/data"

STATIONS = {
    "USW00094728": "Manhattan",   # Central Park
    "USW00094789": "Queens",      # JFK
    "USW00014732": "Queens",      # LaGuardia
    "USW00014734": "Staten Island" # Newark (closest to SI)
}

def fetch_and_load_weather(conn, days_back=5):
    end_date   = datetime.now().strftime("%Y-%m-%d")
    start_date = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%d")
    total      = 0

    for station_id, borough in STATIONS.items():
        params = {
            "datasetid":  "GHCND",
            "stationid":  f"GHCND:{station_id}",
            "startdate":  start_date,
            "enddate":    end_date,
            "limit":      1000,
            "units":      "metric"
        }
        headers = {"token": NOAA_TOKEN}
        resp = requests.get(BASE_URL, params=params, headers=headers, timeout=60)

        if resp.status_code == 200:
            data = resp.json().get("results", [])
            insert_weather_rows(conn, data, station_id, borough)
            total += len(data)
            print(f"  {borough} ({station_id}): {len(data)} observations")
        else:
            print(f"  WARNING: {station_id} returned {resp.status_code}")

    return total

def insert_weather_rows(conn, rows, station_id, station_name):
    with conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO raw_weather_observations
                    (station_id, station_name, date, datatype, value, attributes)
                VALUES (%s,%s,%s,%s,%s,%s)
            """, (
                station_id,
                station_name,
                r.get("date", "")[:10],
                r.get("datatype"),
                r.get("value"),
                r.get("attributes")
            ))
    conn.commit()