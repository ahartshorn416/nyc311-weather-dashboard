"""
fetch_311.py
------------
Fetches NYC 311 service request data from the NYC Open Data Socrata API
and loads it into the raw_311_complaints PostgreSQL table.

The API returns ~5,000 new records per day. This script paginates through
results in batches of 50,000 rows using $limit/$offset parameters, applies
lightweight validation before loading, and commits each batch to the database.

Author: Alison Hartshorn
"""

import os
import requests
import pandas as pd
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

APP_TOKEN = os.getenv("NYC_APP_TOKEN")
BASE_URL  = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"

def fetch_and_load_311(conn, days_back=2):
    """
    Fetches 311 complaints created within the last `days_back` days and loads
    them into raw_311_complaints. Returns total number of rows inserted.

    Uses offset pagination since the Socrata API caps each response at 50,000
    rows. Stops early if a page returns fewer rows than the limit (last page).
    """
    since = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%dT00:00:00")
    offset = 0
    limit  = 50000 # Socrata API maximum rows per request
    total  = 0

    while True:
        params = {
            "$where":     f"created_date > '{since}'",
            "$limit":     limit,
            "$offset":    offset,
            "$order":     "created_date DESC",
            "$$app_token": APP_TOKEN # Raises rate limit from 1K to unlimited req/hr
        }
        resp = requests.get(BASE_URL, params=params, timeout=60)
        resp.raise_for_status()
        rows = resp.json()

        # Empty page means it has consumed all available records
        if not rows:
            break

        # Validate and sanitize before writing to raw table
        rows = [validate_and_sanitize_311_row(r) for r in rows]
        insert_311_rows(conn, rows)
        total  += len(rows)
        offset += limit
        print(f"  Fetched {total} 311 rows so far...")

        # Partial page means this is the final batch
        if len(rows) < limit:
            break

    return total

def validate_and_sanitize_311_row(row):
    """
    Lightweight pre-load validation. SQL views handle the heavy cleaning.
    Strips whitespace, enforces field length limits, and flags records with
    suspicious dates for downstream review.

    Returns the cleaned row dict with an optional '_flag' key added.
    """
    # Strip leading/trailing whitespace from all string fields
    cleaned = {k: v.strip() if isinstance(v, str) else v for k, v in row.items()}

    # Truncate oversized text fields to prevent DB overflow because real data can be messy
    for field in ["complaint_type","descriptor","borough","agency","status","incident_zip"]:
        if cleaned.get(field) and len(cleaned[field]) > 500:
            cleaned[field] = cleaned[field][:500]

    # Flag records dated more than 1 day in the future which are likely data entry errors
    if cleaned.get("created_date"):
        try:
            created = pd.to_datetime(cleaned["created_date"])
            if created > pd.Timestamp.now() + pd.Timedelta(days=1):
                cleaned["_flag"] = "FUTURE_DATE"
        except Exception:
            # Date string couldn't be parsed at all
            cleaned["_flag"] = "UNPARSEABLE_DATE"
    return cleaned

def insert_311_rows(conn, rows):
    """
    Bulk inserts a list of sanitized 311 row dicts into raw_311_complaints.
    Commits once per batch (not per row) for performance.
    Raw table intentionally stores dirty data. Cleaning happens in SQL views.
    """
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
    # Single commit per batch much more efficient than committing row by row
    conn.commit()