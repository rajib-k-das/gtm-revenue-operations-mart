"""
Load the CRM extract (CSV files) into DuckDB as text; typing happens in dbt staging.

Input: data/raw/*.csv from generate/generate_crm.py, or the hand-built test company in tests/fixtures.
Output: raw.users, raw.accounts, raw.opportunities, raw.opportunity_history, raw.quotas

Each file's header is checked against the expected Salesforce-style columns before loading,
so a changed extract fails here with a clear message instead of producing wrong numbers later.

Usage:
    python ingest/load_crm.py                          # data/raw
    python ingest/load_crm.py --raw-dir tests/fixtures # hand-checkable test company (used in CI)
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "warehouse.duckdb"

EXPECTED = {
    "users": ["Id", "Name", "Region", "Segment", "ForecastStyle"],
    "accounts": ["Id", "Name", "Region", "Segment", "Industry", "OwnerId"],
    "opportunities": ["Id", "Name", "AccountId", "OwnerId", "Type", "StageName", "Amount", "CloseDate",
                      "ForecastCategoryName", "Probability", "CreatedDate", "IsClosed", "IsWon"],
    "opportunity_history": ["Id", "OpportunityId", "CreatedDate", "StageName", "Amount", "CloseDate",
                            "ForecastCategory", "Probability"],
    "quotas": ["OwnerId", "QuarterStartDate", "QuotaAmount"],
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw-dir", type=Path, default=ROOT / "data" / "raw")
    args = parser.parse_args()

    for table, columns in EXPECTED.items():
        path = args.raw_dir / f"{table}.csv"
        if not path.exists():
            sys.exit(f"Missing {path}. Run: python generate/generate_crm.py")
        with open(path, newline="") as f:
            header = next(csv.reader(f))
        if header != columns:
            sys.exit(f"{path.name}: unexpected columns.\n  expected {columns}\n  found    {header}")

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(DB_PATH)) as con:
        con.execute("create schema if not exists raw")
        for table in EXPECTED:
            path = (args.raw_dir / f"{table}.csv").as_posix()
            con.execute(f"create or replace table raw.{table} as "
                        f"select * from read_csv('{path}', header=true, all_varchar=true)")
            count = con.execute(f"select count(*) from raw.{table}").fetchone()[0]
            print(f"  raw.{table:<22} {count:>8,} rows")


if __name__ == "__main__":
    main()
