"""
db.py
-----
Database connection and maintenance utilities for the NYC 311 + Weather pipeline.
Loads credentials from the .env file so no secrets are ever hardcoded.

Author: Alison Hartshorn
"""
import os
import psycopg2
from dotenv import load_dotenv

# Load environment variables from .env file (API tokens, DB credentials)
load_dotenv()

def get_connection():
    """
     Returns a live psycopg2 connection to the nyc311 PostgreSQL database.
     All credentials are pulled from environment variables — never hardcoded.
     """
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD")
    )

def refresh_materialized_views(conn):
    """
    Refreshes the mart_complaints_weather materialized view after each pipeline run.
    CONCURRENTLY allows reads during refresh — no table lock, safe for production.
    """
    with conn.cursor() as cur:
        cur.execute("REFRESH MATERIALIZED VIEW CONCURRENTLY mart_complaints_weather;")
    conn.commit()