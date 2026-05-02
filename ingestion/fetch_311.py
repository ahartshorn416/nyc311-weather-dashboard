import os
import requests
import pandas as pd
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

APP_TOKEN = os.getenv("NYC_APP_TOKEN")
BASE_URL  = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"

def fetch_and_load_311(conn, days_back=2):
    since = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%dT00:00:00")
    offset = 0
    limit  = 50000
    total  = 0

    while True:
        params = {
            "$where":     f"created_date > '{since}'",
            "$limit":     limit,
            "$offset":    offset,
            "$order":     "created_date DESC",
            "$$app_token": APP_TOKEN
        }
        resp = requests.get(BASE_URL, params=params, timeout=60)
        resp.raise_for_status()
        rows = resp.json()

        if not rows:
            break

        rows = [validate_and_sanitize_311_row(r) for r in rows]
        insert_311_rows(conn, rows)
        total  += len(rows)
        offset += limit
        print(f"  Fetched {total} 311 rows so far...")

        if len(rows) < limit:
            break

    return total

def validate_and_sanitize_311_row(row):
    cleaned = {k: v.strip() if isinstance(v, str) else v for k, v in row.items()}
    for field in ["complaint_type","descriptor","borough","agency","status","incident_zip"]:
        if cleaned.get(field) and len(cleaned[field]) > 500:
            cleaned[field] = cleaned[field][:500]
    if cleaned.get("created_date"):
        try:
            created = pd.to_datetime(cleaned["created_date"])
            if created > pd.Timestamp.now() + pd.Timedelta(days=1):
                cleaned["_flag"] = "FUTURE_DATE"
        except Exception:
            cleaned["_flag"] = "UNPARSEABLE_DATE"
    return cleaned

def insert_311_rows(conn, rows):
    with conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO raw_311_complaints
                    (unique_key, created_date, closed_date, complaint_type,
                     descriptor, borough, incident_zip, latitude, longitude,
                     agency, status)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (
                r.get("unique_key"),
                r.get("created_date"),
                r.get("closed_date"),
                r.get("complaint_type"),
                r.get("descriptor"),
                r.get("borough"),
                r.get("incident_zip"),
                r.get("latitude"),
                r.get("longitude"),
                r.get("agency"),
                r.get("status")
            ))
    conn.commit()