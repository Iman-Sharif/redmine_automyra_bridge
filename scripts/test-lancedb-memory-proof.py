#!/usr/bin/env python3
"""Test LanceDB direct memory write + readback for Redmica proof."""
import lancedb, json, sys, uuid
from datetime import datetime, timezone

DB_PATH = "/root/.openclaw/memory/lancedb-pro"
TABLE_NAME = "redmine-memories"
TEST_ID = str(uuid.uuid4())[:8]

try:
    db = lancedb.connect(DB_PATH)
    tbl = db.open_table(TABLE_NAME)
    initial_count = tbl.count_rows()
    print(f"Initial rows: {initial_count}")

    entry = {
        "id": str(uuid.uuid4()),
        "type": "task_action",
        "project_id": "1",
        "project_name": "Automyra Verification",
        "issue_id": None,
        "wiki_page_id": None,
        "subject": None,
        "title": f"Redmica Memory Proof Test {TEST_ID}",
        "content": json.dumps({"action": "cancel_task", "task_id": 999, "user": "iman.sharif", "source": "redmica_bridge"}),
        "author": "Automyra Bridge",
        "author_id": 9,
        "created_on": datetime.now(timezone.utc),
        "updated_on": datetime.now(timezone.utc),
        "status": "synced",
        "priority": None,
        "tracker": None,
        "url": None,
        "parent_id": None,
        "journal_id": None,
        "version": 1,
        "vector": None,
    }

    tbl.add([entry])
    after_count = tbl.count_rows()
    print(f"After write: {after_count} (+{after_count - initial_count})")
    assert after_count > initial_count, "Write did not increase row count"

    df = tbl.to_pandas()
    matches = df[df["title"].str.contains(f"Proof Test {TEST_ID}", na=False)]
    if len(matches) == 0:
        print("✗ FAILURE: Entry not found via scan")
        sys.exit(1)

    row = matches.iloc[0]
    parsed = json.loads(row["content"])
    print(f"✓ SUCCESS: Entry '{row['title']}' retrievable from LanceDB")
    print(f"  Content: {parsed}")
    print(f"  Status: {row['status']}")
    print(f"  Created: {row['created_on']}")
    sys.exit(0)

except Exception as e:
    print(f"✗ ERROR: {type(e).__name__}: {e}")
    import traceback; traceback.print_exc()
    sys.exit(1)
