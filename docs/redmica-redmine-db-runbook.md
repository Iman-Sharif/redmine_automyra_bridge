# Redmica / Redmine Database Management Runbook

Last updated: 2026-04-29

## Canonical services

| Purpose | App container | URL/port | DB container | DB engine | DB name | Protected data volume |
|---|---|---:|---|---|---|---|
| Live Redmica | `redmica-app` | `http://127.0.0.1:4000` | `redmica-db` | PostgreSQL 16 | `redmica` | `migration_redmica_postgres_data` |
| Legacy Redmine source/archive | `redmine-redmine-1` | `http://127.0.0.1:4001` | `redmine-postgres-1` | PostgreSQL 16 | `redmine` | `redmine_redmine_postgres_data` |

## Critical warning

`migration_redmica_postgres_data` is the active production Redmica PostgreSQL data volume.

The name is historical from the Redmine-to-Redmica migration and recovery work. It is not disposable. Do not remove, prune, recreate, or attempt to rename it unless there is a dedicated maintenance window, a fresh verified backup, and a tested rollback path.

Never use `docker volume prune` on this host as a cleanup shortcut.

## Known-good live counts

Live Redmica should currently validate as:

| Table/check | Expected |
|---|---:|
| users | 8 |
| projects | 27 |
| issues | 25 |
| wiki_pages | 31 |
| orphan FK checks | 0 |

Legacy Redmine should currently validate as:

| Table | Expected |
|---|---:|
| projects | 26 |
| issues | 22 |
| wiki_pages | 29 |

## Required verification command

Run this before and after any Docker, database, cleanup, migration, or restore work:

```bash
/opt/redmica/scripts/verify-redmica-redmine-dbs.sh
```

The script verifies:

- required app and DB containers are running
- protected production/legacy DB volumes are mounted where expected
- Redmica `/login` responds on port `4000`
- legacy Redmine `/login` responds on port `4001`
- known-good row counts match
- Redmica orphan checks return zero

## Current Redmica DBs inside `redmica-db`

The `redmica-db` PostgreSQL server should normally retain only:

- `postgres`
- `redmica`

The temporary databases `redmica_recovery`, `redmica_staging`, and `redmica_test` were backed up under the 2026-04-29 incident evidence directory and dropped during cleanup after verification. They are not canonical live databases.

## Current Redmica-related Docker volumes

| Volume | Decision | Reason |
|---|---|---|
| `migration_redmica_postgres_data` | KEEP | Active production Redmica PostgreSQL data volume mounted by `redmica-db` |
| `redmine_redmine_postgres_data` | KEEP | Active legacy Redmine PostgreSQL data volume mounted by `redmine-postgres-1` |
| `test_redmine_wiki_hub_test_pgdata` | KEEP | Dedicated Wiki Hub regression test volume |
| `migration_redmica_db_data` | REMOVED after archive | Obsolete migration-compose volume, not mounted by any container; archived in incident evidence |
| `migration_redmica_staging_db_data` | REMOVED after archive | Obsolete migration-compose staging volume, not mounted by any container; archived in incident evidence |

## Backup commands

Create a timestamped backup directory:

```bash
BACKUP_DIR="/opt/redmica/.sisyphus/evidence/incident-20260429-redmica-db/pre-cleanup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
```

Back up live Redmica:

```bash
docker exec redmica-db pg_dump -U redmica -Fc -d redmica > "$BACKUP_DIR/redmica.dump"
```

Back up legacy Redmine:

```bash
docker exec redmine-postgres-1 pg_dump -U redmine -Fc -d redmine > "$BACKUP_DIR/redmine.dump"
```

Back up cleanup-candidate Redmica DBs before dropping them:

```bash
for db in redmica_recovery redmica_staging redmica_test; do
  if docker exec redmica-db psql -U redmica -d postgres -Atc "select 1 from pg_database where datname = '$db';" | grep -q 1; then
    docker exec redmica-db pg_dump -U redmica -Fc -d "$db" > "$BACKUP_DIR/$db.dump"
  fi
done
```

Verify backup structure:

```bash
for dump in "$BACKUP_DIR"/*.dump; do
  pg_restore -l "$dump" >/dev/null
  sha256sum "$dump"
done | tee "$BACKUP_DIR/SHA256SUMS"
```

## Cleanup policy

Before dropping a database or removing a volume, every item must have an evidence-backed decision:

| Required evidence | Why |
|---|---|
| Not referenced by any running app container | prevents deleting live data |
| Not mounted by any required stopped rollback container | preserves rollback paths |
| Not referenced by compose/env/scripts/docs as canonical | avoids breaking restart workflows |
| Fresh backup exists | provides rollback |
| Backup passes `pg_restore -l` or archive listing | ensures the backup is readable |
| `/opt/redmica/scripts/verify-redmica-redmine-dbs.sh` passes before and after | proves live systems were not damaged |

Do not remove these without a separate explicit decommissioning plan:

- `redmica-app`
- `redmica-db`
- `migration_redmica_postgres_data`
- `/opt/redmica/files`
- `/opt/redmica/plugins`
- `redmine-redmine-1`
- `redmine-postgres-1`
- `redmine_redmine_postgres_data`
- `/opt/redmine/files`
- recovery dumps under `/opt/redmica/.sisyphus/evidence/incident-20260429-redmica-db/`

## Test database naming policy

Tests and fixture loads must never use production-like database names:

- forbidden: `redmica`, `redmine`, `production`, `prod`, `redmica_production`, `redmine_production`
- required pattern: names must clearly be test-scoped, such as `wiki_hub_test`, `redmica_test`, or `test_redmica`

Wiki Hub regression uses the isolated database `wiki_hub_test` in its plugin test compose stack.

## Safe password reset checklist

Before changing users in Redmica:

1. Verify the runtime target:

```bash
docker exec redmica-app bash -lc 'cd /usr/src/redmica && bundle exec rails runner "c=ActiveRecord::Base.connection_db_config; puts({env: Rails.env, adapter: c.adapter, database: c.database, host: c.host, username: c.username}.inspect)" RAILS_ENV=production'
```

2. Confirm it says database `redmica` on host `db`.
3. Run the verification script.
4. Make the user change.
5. Run the verification script again.

## Restore outline

Prefer restoring into a candidate DB first:

1. Stop app writes if production is affected.
2. Create `redmica_restore_check` or another candidate DB.
3. Restore the dump into the candidate.
4. Validate counts and orphan checks against the candidate.
5. Promote only after validation passes.
6. Keep the broken DB renamed or dumped until the restored app is confirmed healthy.

Do not overwrite live `redmica` directly without a fresh dump of the current state.
