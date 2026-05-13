# 🗽 NYC 311 + Weather Correlation Dashboard

> A production-grade ETL pipeline and interactive Power BI dashboard exploring how weather drives civic complaints across New York City boroughs.

![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Automated](https://img.shields.io/badge/Refresh-Daily%20at%205AM-success?style=for-the-badge)

---

## 🔗 Live Dashboard

👉 **[View the live dashboard here](https://app.powerbi.com/view?r=eyJrIjoiNDYwZTJkMjYtN2E5ZS00MTUxLWJlNzMtOTE1NjQ4ZDBiODVhIiwidCI6IjQ5NTcyY2FlLWNlMDAtNGRmNi1iYjRhLThkZTg3ZGY0YTE2ZSJ9)**

*No Power BI account required · Updates daily at 6:00 AM EST*

---

## 📊 Dashboard Preview

| Tab | Description |
|-----|-------------|
| Executive Summary | 942K complaints · borough breakdown · daily trend |
| Weather Correlation | Temperature & rainfall vs complaint volume |
| Borough Deep Dive | Interactive slicer · resolution times · day of week |
| Complaint Type Explorer | Full matrix across all 5 boroughs · slowest to resolve |
| Pipeline Health | Ingestion stats · join rate · last pipeline run timestamp |

---

## 💡 Core Question

> **How do weather conditions (temperature, precipitation) drive the volume and type of 311 complaints filed across NYC boroughs?**

Key findings:
- 🚗 **Illegal Parking** is the #1 complaint across every borough
- 🌡️ **Cool weather (5–18°C)** drives the most complaints — heating failures, snow/ice issues
- 🏙️ **Brooklyn** leads all boroughs with 288K complaints over 90 days
- ⏱️ **Food Establishments** take the longest to resolve (~1,000+ hours avg)
- 📅 **Tuesday** is consistently the busiest complaint day

---

## 🏗️ Architecture

```
NYC Open Data API (311)  ──┐
                           ├──► Python Ingestion ──► Raw PostgreSQL ──► SQL Cleaning ──► Materialized Views ──► Power BI
NOAA Weather API       ──┘                                                                                         │
                                                                                                                   │
Windows Task Scheduler (5:00 AM daily) ──────────────────────────────────────────────────────────────────────────►│
```

### Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Ingestion | Python 3.11 + requests | API polling, pagination, raw load |
| Raw Storage | PostgreSQL 15 | Immutable raw tables |
| Cleaning | SQL CTEs + window functions | Dedup, normalize, type-cast |
| Serving | PostgreSQL materialized views | Pre-aggregated for fast BI queries |
| Visualization | Power BI Desktop + Service | Interactive 5-tab dashboard |
| Scheduling | Windows Task Scheduler | Runs pipeline at 5:00 AM daily |

---

## 📁 Folder Structure

```
nyc311-weather-dashboard/
├── ingestion/
│   ├── fetch_311.py          # NYC Open Data API client
│   ├── fetch_weather.py      # NOAA CDO API client
│   ├── db.py                 # PostgreSQL connection helper
│   └── run_pipeline.py       # Daily orchestrator
├── sql/
│   ├── 01_create_raw.sql     # Raw table DDL
│   ├── 02_stg_complaints.sql # Cleaning + dedup view
│   ├── 03_stg_weather.sql    # Weather pivot + borough mapping
│   └── 04_mart.sql           # Joined materialized view
├── powerbi/
│   └── nyc311_dashboard.pbix # Power BI file
├── .env.example              # Copy to .env and fill in credentials
├── requirements.txt
└── README.md
```

---

## 🚀 Getting Started

### 1. Prerequisites

- Python 3.8+ (Anaconda recommended)
- PostgreSQL 15+
- Power BI Desktop (free)
- Free API tokens (see below)

### 2. Get API Tokens

| Token | URL | Notes |
|-------|-----|-------|
| NYC Open Data | https://data.cityofnewyork.us/signup | Free, instant |
| NOAA CDO | https://www.ncdc.noaa.gov/cdo-web/token | Free, arrives by email |

### 3. Clone & Configure

```bash
git clone https://github.com/ahartshorn416/nyc311-weather-dashboard.git
cd nyc311-weather-dashboard
pip install -r requirements.txt
```

Copy `.env.example` to `.env` and fill in your credentials:

```
NYC_APP_TOKEN=your_nyc_token_here
NOAA_TOKEN=your_noaa_token_here
DB_HOST=localhost
DB_PORT=5432
DB_NAME=nyc311
DB_USER=postgres
DB_PASSWORD=your_pg_password_here
```

### 4. Set Up the Database

In pgAdmin or psql:

```sql
CREATE DATABASE nyc311;
```

Then run the SQL files in order:

```bash
psql -U postgres -d nyc311 -f sql/01_create_raw.sql
psql -U postgres -d nyc311 -f sql/02_stg_complaints.sql
psql -U postgres -d nyc311 -f sql/03_stg_weather.sql
psql -U postgres -d nyc311 -f sql/04_mart.sql
```

### 5. Run the Pipeline

```bash
python ingestion/run_pipeline.py
```

This pulls the last 90 days of data. Expect ~15–20 minutes on first run.

### 6. Connect Power BI

1. Open `powerbi/nyc311_dashboard.pbix`
2. Update the PostgreSQL connection to point to your local instance
3. Refresh the data

---

## 🗄️ Database Schema

### Raw Layer (Immutable)

```sql
raw_311_complaints       -- Exactly as returned by the API
raw_weather_observations -- NOAA station observations (long format)
pipeline_log             -- Run timestamps and row counts
```

### Staging Layer (Cleaned)

```sql
stg_complaints     -- Deduped, borough normalized, coordinates validated
stg_weather_daily  -- Pivoted to wide format, Bronx/Brooklyn approximated
```

### Mart Layer (Power BI Source)

```sql
mart_complaints_weather  -- Joined fact table: complaints + weather by date/borough
```

---

## 🧹 Data Quality

Real-world messiness this pipeline handles:

- ✅ Borough names: `MANHATTAN`, `MN`, `Manhattan` → normalized to `Manhattan`
- ✅ Duplicate submissions → deduplicated via `ROW_NUMBER()` window function
- ✅ Invalid coordinates → validated against NYC bounding box (40.4–41.0°N, 73.7–74.3°W)
- ✅ Malformed zip codes → regex validated to 5-digit format
- ✅ Temporal paradoxes → closed dates before open dates → set to NULL
- ✅ Missing boroughs (Bronx/Brooklyn) in weather → approximated from nearest station

### Quality Metrics Achieved

| Metric | Target | Actual |
|--------|--------|--------|
| Null borough rate | < 1% | 0.1% |
| Weather join rate | > 95% | 96.1% |
| Clean rows loaded | — | 941,876 |

---

## ⚙️ Automation

The pipeline runs automatically every morning:

```
5:00 AM  →  Windows Task Scheduler triggers run_pipeline.py
             Fetches last 2 days of 311 data
             Fetches last 5 days of weather data
             Refreshes materialized view
             Logs run to pipeline_log table

6:00 AM  →  Power BI Service scheduled refresh
             Pulls latest data from PostgreSQL
             Dashboard updates automatically
```

To set up the Task Scheduler:

```cmd
schtasks /create /tn "NYC311Pipeline" /tr "C:\Users\YourName\anaconda3\python.exe C:\path\to\ingestion\run_pipeline.py" /sc daily /st 05:00
```

---

## 📈 Key DAX Measures

```dax
-- Rolling 7-day average
Complaints 7D Avg =
AVERAGEX(
    DATESINPERIOD(dates[date], LASTDATE(dates[date]), -7, DAY),
    [Total Complaints]
)

-- Weather-adjusted complaint index
Weather Complaint Index =
DIVIDE(
    [Total Complaints],
    AVERAGEX(
        FILTER(mart_complaints_weather,
               mart_complaints_weather[temp_category]
               = SELECTEDVALUE(mart_complaints_weather[temp_category])),
        mart_complaints_weather[complaint_count]
    )
)

-- Last pipeline run timestamp
Last Pipeline Run =
FORMAT(MAXX(pipeline_log, pipeline_log[ran_at]), "MM/DD/YYYY HH:MM:SS")
```

---

## 🔮 Extensions / Next Steps

- [ ] Sentiment analysis on complaint descriptor text using a lightweight NLP model
- [ ] Add US Census demographic data to explore complaint disparities by income level
- [ ] Prophet time-series forecasting for complaint volume prediction
- [ ] Migrate to Azure SQL or Snowflake for cloud-native ETL
- [ ] dbt models with full data lineage documentation (`dbt docs generate`)
- [ ] Docker container for fully reproducible pipeline runs

---

## 📚 Data Sources

| Source | Dataset | URL |
|--------|---------|-----|
| NYC Open Data | 311 Service Requests (2010–present) | [data.cityofnewyork.us](https://data.cityofnewyork.us/resource/erm2-nwe9.json) |
| NOAA CDO | GHCND Daily Summaries | [ncei.noaa.gov](https://www.ncei.noaa.gov/cdo-web/api/v2/data) |

**Stations used:**
- `USW00094728` — Central Park (Manhattan)
- `USW00094789` — JFK Airport (Queens)
- `USW00014732` — LaGuardia Airport (Queens)
- `USW00014734` — Newark Airport (Staten Island proxy)

---

## ⚠️ Important

Never commit your `.env` file. It is listed in `.gitignore` by default. Use `.env.example` as a template.

---

## 📄 License

MIT License — free to use, modify, and distribute with attribution.

---

*Built with real NYC Open Data and NOAA weather observations · Automated daily refresh · Power BI NYC theme*
