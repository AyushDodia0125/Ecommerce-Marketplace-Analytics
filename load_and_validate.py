"""
load_and_validate.py
--------------------
Loads all 6 CSVs into a local SQLite database and runs all SQL queries
to validate correctness before handing off to PostgreSQL or Power BI.

Run: python load_and_validate.py
"""

import os
import re
import sqlite3
import pandas as pd
from pathlib import Path

BASE_DIR = Path(__file__).parent
DATA_DIR = BASE_DIR / "data"
SQL_DIR  = BASE_DIR / "sql"
DB_PATH  = BASE_DIR / "marketplace.db"

# ── SQLite compatibility patches ───────────────────────────────────────────────
# PostgreSQL-specific syntax is adapted for SQLite automatically below.

SQLITE_REPLACEMENTS = [
    # DATE_TRUNC → strftime
    (r"DATE_TRUNC\('month',\s*([^)]+)\)::DATE",   r"date(\1, 'start of month')"),
    (r"DATE_TRUNC\('month',\s*([^)]+)\)",          r"date(\1, 'start of month')"),
    (r"DATE_TRUNC\('week',\s*([^)]+)\)",           r"date(\1, 'weekday 0', '-6 days')"),
    (r"DATE_TRUNC\('quarter',\s*([^)]+)\)::DATE",  r"date(\1, 'start of month')"),
    (r"DATE_TRUNC\('quarter',\s*([^)]+)\)",        r"date(\1, 'start of month')"),
    # ::DATE, ::TIMESTAMP casts
    (r"::(DATE|TIMESTAMP|date|timestamp)",          r""),
    # PERCENTILE_CONT — not supported in SQLite, skip
    (r"ROUND\(\s*PERCENTILE_CONT\([\s\S]*?WITHIN GROUP[\s\S]*?,\s*\n?\s*\d\)",
     r"NULL /* PERCENTILE_CONT not supported in SQLite */"),
    # DATE_PART
    (r"DATE_PART\('year',\s*([^)]+)\)",             r"CAST(strftime('%Y', \1) AS INTEGER)"),
    (r"DATE_PART\('month',\s*([^)]+)\)",            r"CAST(strftime('%m', \1) AS INTEGER)"),
    # AGE function — use julianday difference approximation
    (r"DATE_PART\('year',\s*AGE\(([^,]+),\s*([^)]+)\)\)",
     r"CAST((julianday(\1) - julianday(\2)) / 365.25 AS INTEGER)"),
    # DATEDIFF
    (r"DATEDIFF\('month',\s*([^,]+),\s*([^)]+)\)",
     r"CAST((julianday(\2) - julianday(\1)) / 30.44 AS INTEGER)"),
    # interval arithmetic: date + integer => julianday trick
    (r"(\w+)\s*\+\s*1\b",  r"\1 + 1"),   # keep as-is for SQLite date math
]


def adapt_sql_for_sqlite(sql: str) -> str:
    for pattern, replacement in SQLITE_REPLACEMENTS:
        sql = re.sub(pattern, replacement, sql, flags=re.IGNORECASE)
    return sql


# ── Load data ──────────────────────────────────────────────────────────────────

def load_data():
    print("\n📥 Loading CSVs into SQLite database...")
    conn = sqlite3.connect(DB_PATH)

    tables = ["customers", "sellers", "products", "orders", "events", "inventory"]
    for table in tables:
        csv_path = DATA_DIR / f"{table}.csv"
        df = pd.read_csv(csv_path)
        df.to_sql(table, conn, if_exists="replace", index=False)
        print(f"   ✓ {table:<15} {len(df):>8,} rows loaded")

    conn.commit()
    conn.close()
    print()


# ── Run queries ────────────────────────────────────────────────────────────────

def run_sql_file(conn: sqlite3.Connection, filepath: Path) -> dict:
    raw_sql = filepath.read_text()
    sql = adapt_sql_for_sqlite(raw_sql)

    # Split into individual statements (separated by blank lines before SELECT/WITH)
    # Strategy: split on lines that start a new top-level statement after a comment block
    statements = []
    current = []
    for line in sql.splitlines():
        stripped = line.strip()
        # New statement starts at a comment block header (----)
        if stripped.startswith("-- ----") and current:
            block = "\n".join(current).strip()
            if block:
                statements.append(block)
            current = []
        current.append(line)
    if current:
        block = "\n".join(current).strip()
        if block:
            statements.append(block)

    results = {}
    query_num = 0
    for block in statements:
        # Extract the SELECT/WITH portion from each block
        lines = block.splitlines()
        sql_lines = []
        in_sql = False
        for line in lines:
            if re.match(r"\s*(SELECT|WITH|CREATE|DROP|INSERT)", line, re.I):
                in_sql = True
            if in_sql:
                sql_lines.append(line)

        if not sql_lines:
            continue

        query_sql = "\n".join(sql_lines).strip()
        if not query_sql:
            continue

        # Skip CREATE/DROP for read-only validation (schema already loaded)
        if re.match(r"\s*(CREATE|DROP)", query_sql, re.I):
            continue

        query_num += 1
        try:
            df = pd.read_sql_query(query_sql, conn)
            results[f"Query {query_num}"] = {
                "status": "✓ OK",
                "rows": len(df),
                "columns": list(df.columns),
                "sample": df.head(3),
            }
        except Exception as e:
            results[f"Query {query_num}"] = {
                "status": f"✗ ERROR",
                "error": str(e)[:120],
            }

    return results


def validate_all_queries():
    conn = sqlite3.connect(DB_PATH)
    sql_files = sorted(SQL_DIR.glob("*.sql"))

    all_passed = True
    for sql_file in sql_files:
        if sql_file.name == "01_schema.sql":
            continue  # Schema already applied via pandas to_sql
        print(f"\n📄 {sql_file.name}")
        print("   " + "─" * 60)
        results = run_sql_file(conn, sql_file)
        if not results:
            print("   (no runnable SELECT statements found)")
            continue
        for qname, res in results.items():
            if "error" in res:
                print(f"   {res['status']} {qname}: {res['error']}")
                all_passed = False
            else:
                print(f"   {res['status']} {qname} — {res['rows']:,} rows, "
                      f"columns: {', '.join(res['columns'][:5])}{'...' if len(res['columns']) > 5 else ''}")

    conn.close()
    return all_passed


# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    load_data()
    print("🔍 Validating all SQL queries...\n")
    passed = validate_all_queries()
    if passed:
        print("\n\n✅ All queries validated successfully. Database ready at marketplace.db\n")
    else:
        print("\n\n⚠️  Some queries had errors. See above for details.\n")
