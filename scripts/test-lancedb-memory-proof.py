#!/usr/bin/env python3
"""Read-only LanceDB memory health proof for Redmica."""
import json
import sys

import lancedb

DB_PATH = "/root/.openclaw/memory/lancedb-pro"
TABLE_NAME = "memories"
MIN_EXPECTED_ROWS = 30


def table_names(db):
    listed = db.list_tables()
    if hasattr(listed, "names"):
        return listed.names
    if isinstance(listed, dict):
        return listed.get("tables", [])
    pairs = dict(listed)
    if "tables" in pairs:
        return pairs["tables"]
    return list(listed)


try:
    db = lancedb.connect(DB_PATH)
    names = table_names(db)
    if TABLE_NAME not in names:
        print(f"✗ FAILURE: LanceDB table {TABLE_NAME!r} does not exist; found {names}")
        sys.exit(1)

    tbl = db.open_table(TABLE_NAME)
    row_count = tbl.count_rows()
    print(f"Rows: {row_count}")
    if row_count < MIN_EXPECTED_ROWS:
        print(f"✗ FAILURE: row count is below safety threshold {MIN_EXPECTED_ROWS}")
        sys.exit(1)

    columns = set(tbl.schema.names)
    required_columns = {"id", "text", "vector", "category", "scope", "importance", "timestamp", "metadata"}
    missing = required_columns.difference(columns)
    if missing:
        print(f"✗ FAILURE: missing expected columns: {sorted(missing)}")
        sys.exit(1)

    sample = tbl.search().limit(1).to_list()[0]
    metadata = sample.get("metadata")
    if isinstance(metadata, str) and metadata:
        try:
            json.loads(metadata)
        except json.JSONDecodeError as exc:
            print(f"✗ FAILURE: sample metadata is not valid JSON: {exc}")
            sys.exit(1)

    print("✓ SUCCESS: LanceDB memories table is readable and above the safety threshold")
    print(f"  Table: {TABLE_NAME}")
    print(f"  Columns: {', '.join(tbl.schema.names)}")
    sys.exit(0)

except Exception as e:
    print(f"✗ ERROR: {type(e).__name__}: {e}")
    import traceback

    traceback.print_exc()
    sys.exit(1)
