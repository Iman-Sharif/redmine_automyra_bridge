#!/usr/bin/env python3
import lancedb
import json
import sys
from datetime import datetime

DB_PATH = "/root/.openclaw/memory/lancedb-pro"

try:
    db = lancedb.connect(DB_PATH)
    raw_tables = db.list_tables() if hasattr(db, 'list_tables') else []
    table_names = []
    for item in raw_tables:
        if isinstance(item, tuple):
            try:
                table_names.extend(item[1])
            except (IndexError, TypeError):
                pass
        else:
            table_names.append(str(item))
    tables = table_names
    print(f"Database connected. Tables: {tables}")
    
    target = "redmine-memories"
    if target not in tables:
        print(f"Table '{target}' not found. Available: {tables}")
        sys.exit(1)

    table = db.open_table(target)
    print(f"Connected. Rows: {table.count_rows()}")
    print(f"Schema columns: {[f.name for f in table.schema]}")

    test_id = f"test_{datetime.now().strftime('%Y%m%d%H%M%S')}"
    test_text = f"Redmica Automyra memory proof test event: {test_id}"

    table.add({
        "text": test_text,
        "category": "test",
        "importance": 0.95,
        "timestamp": datetime.now().isoformat(),
        "source": "redmica_bridge_verification",
        "metadata": json.dumps({"test": True, "event_id": test_id}),
    })

    print(f"Wrote: {test_id}")

    import pandas as pd
    df = table.to_pandas()
    found = df["text"].astype(str).str.contains(test_id, case=False).any()
    print(f"Found via scan: {found}")
    sys.exit(0 if found else 1)
except Exception:
    import traceback
    traceback.print_exc()
    sys.exit(1)

