# Wiki Hub Operator Runbook

This runbook provides operational procedures for managing the Redmine Wiki Hub plugin in production environments.

## Table of Contents

1. [Health Checks](#health-checks)
2. [Operational Procedures](#operational-procedures)
3. [Deployment Procedures](#deployment-procedures)
4. [Index Management](#index-management)
5. [Monitoring](#monitoring)
6. [Backup and Restore](#backup-and-restore)
7. [Incident Response](#incident-response)
8. [Performance Tuning](#performance-tuning)

## Operational Procedures

This section documents the complete operational lifecycle for the Wiki Hub plugin. All procedures assume the Redmica-first development model where `/opt/redmica/plugins/redmine_wiki_hub` is the canonical writable source.

### Pre-Flight Checklist

Before any deployment or update, verify:

1. **Canonical source is ready**: All changes committed in `/opt/redmica/plugins/redmine_wiki_hub/`
2. **Regression gate passes**: `./scripts/regression.sh --docker` exits 0
3. **Sync is clean**: `./scripts/sync-canonical-to-repo.sh --verify-only` shows no differences
4. **Database backup exists**: Current Redmine database backed up
5. **Maintenance window scheduled**: For production deployments with user impact
6. **Migration scope is understood**: native UI rollout covers list and table surfaces, while graph or canvas remains an intentional CSS exception boundary via `wiki_hub_graph.css`
7. **Environment caveat is understood**: local browser verification described in shared rollout notes used the plugin-loaded app on `http://127.0.0.1:4000`, Wiki Hub index and search native shell corrections are verified after cache clear and restart, and cross-theme comparison completed with multiple selectable themes

### Deploy Flow (Complete Procedure)

**Purpose**: Deploy new Wiki Hub code to production with full verification.

**Assumptions**: Maintenance window active; Redmine will be temporarily unavailable.

```bash
# Step 1: Run Compatibility Gate (Task 10)
# Must pass before any sync or deploy
cd /opt/redmica/plugins/redmine_wiki_hub
./scripts/regression.sh --docker
# Expected: All tests pass, exit code 0

# Step 2: Sync Canonical to Repo (Task 11)
# Only proceed if gate passed
./scripts/sync-canonical-to-repo.sh
# Expected: "Canonical sync completed successfully"

# Step 3: Verify Sync Status
diff -ruN \
  --exclude=.git --exclude=tmp --exclude=node_modules --exclude=coverage \
  --exclude=.github --exclude=.sisyphus \
  /opt/redmica/plugins/redmine_wiki_hub/ \
  /root/workspace/repos/redmine_wiki_hub/
# Expected: No output (exit code 0)

# Step 4: Deploy to Target (if deploying to non-canonical Redmine)
rsync -a --delete \
  --exclude .git --exclude tmp --exclude node_modules --exclude coverage \
  --exclude .github --exclude .sisyphus \
  /root/workspace/repos/redmine_wiki_hub/ \
  /opt/redmine/plugins/redmine_wiki_hub/

# Step 5: Install Dependencies
cd /opt/redmine
bundle install --without development test

# Step 6: Run Database Migrations
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production
# Note: Migrations may modify schema; they cannot be undone without rollback procedure

# Step 7: Rebuild Search Index
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
# Expected: "Completed in X.XXs" with 0 errors

# Step 8: Verify Health (Local Check)
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production
# Expected: Exit code 0

# Step 9: Restart Application
touch /opt/redmine/tmp/restart.txt

# Step 10: Verify Public Endpoint (unauthenticated returns 302 to login)
curl -s -o /dev/null -w "%{http_code}" https://redmica.sbg-server.com/knowledge_hub
# Expected: 302 (redirect to login) or 200 (if already authenticated)

# Step 11: Final Health Check
bundle exec rails runner "puts WikiHub::Healthcheck.call.to_json" RAILS_ENV=production
# Expected: {"status":"ok",...}
```

**Rebuild Triggers**: The index rebuild (Step 7) must run when:
- Plugin code changes affect indexing logic
- Database migrations modify Wiki Hub tables
- Links are not resolving correctly
- Search returns stale or missing results

### Rollback Flow (Complete Procedure)

**Purpose**: Revert Wiki Hub to a previous working state.

**WARNING**: Code-only rollback is NOT sufficient. Database migrations may have modified schema, and indexes may reference non-existent data.

```bash
# Step 1: Identify Rollback Target
# Determine the last known good commit or backup timestamp
ROLLBACK_COMMIT="<commit-hash-or-timestamp>"

# Step 2: Stop Application (prevent new data during rollback)
touch /opt/redmine/tmp/restart.txt  # or systemctl stop redmine

# Step 3: Rollback Database Migrations (CRITICAL)
# This reverts schema changes made by newer migrations
cd /opt/redmine
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub VERSION=0 RAILS_ENV=production
# Note: This rolls back ALL Wiki Hub migrations. If you need selective rollback,
# identify the specific version to roll back to and use that instead of VERSION=0

# Step 4: Restore Plugin Code
cd /opt/redmica/plugins/redmine_wiki_hub
git checkout "$ROLLBACK_COMMIT"  # or restore from backup tarball

# Step 5: Re-apply Compatible Migrations
# After rollback, re-run migrations for the target version
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production

# Step 6: Rebuild Index (required after schema changes)
bundle exec rake wiki_hub:rebuild RAILS_ENV=production

# Step 7: Verify Health
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production

# Step 8: Restart Application
touch /opt/redmine/tmp/restart.txt

# Step 9: Verify Public Endpoint
curl -s -o /dev/null -w "%{http_code}" https://redmica.sbg-server.com/knowledge_hub
# Expected: 302 (redirect to login) or 200 (if already authenticated)

# Optional: follow redirects and confirm login page or Wiki Hub content
curl -sL https://redmica.sbg-server.com/knowledge_hub | grep -q "Wiki Hub\|Login"
# Expected: Exit code 0

# Step 10: Post-Rollback Verification
# Check that search returns expected results
# Verify links resolve correctly
# Monitor error logs for 15 minutes
```

**Schema/Index Implications**:
- Rolling back migrations drops tables/columns added by newer versions
- Data in dropped tables is lost unless backed up separately
- GIN indexes on `pg_trgm` columns must be recreated (handled by migrations)
- Rebuild is required because snapshots reference page versions that may have changed

### Redmica Update Promotion Procedure

**Purpose**: Promote Wiki Hub to a new Redmica version.

**Rule**: The pinned compatibility gate MUST pass before any promotion.

```bash
# Step 1: Check Current Redmica Version
cd /opt/redmica
cat VERSION  # or git describe --tags

# Step 2: Review Pinned Compatibility
# Check README.md for the current pinned runtime/gate requirements

# Step 3: Run Compatibility Gate (MANDATORY)
cd /opt/redmica/plugins/redmine_wiki_hub
./scripts/regression.sh --docker
# Expected: Exit 0
# If this fails, DO NOT proceed with Redmica update

# Step 4: Update Redmica (if gate passed)
cd /opt/redmica
git fetch origin
git checkout "$TARGET_VERSION"

# Step 5: Update Plugin Dependencies
cd /opt/redmica
bundle install

# Step 6: Run Redmica Migrations
bundle exec rails db:migrate RAILS_ENV=production

# Step 7: Run Plugin Migrations
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production

# Step 8: Rebuild Index (required for Redmica updates)
bundle exec rake wiki_hub:rebuild RAILS_ENV=production

# Step 9: Full Verification
./scripts/regression.sh --docker  # Re-run gate on new Redmica version
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production

# Step 10: Restart and Verify
touch /opt/redmine/tmp/restart.txt
curl -s -o /dev/null -w "%{http_code}" https://redmica.sbg-server.com/knowledge_hub
```

**Promotion Rules**:
1. **Gate Required**: `./scripts/regression.sh --docker` must pass before updating Redmica
2. **Version Matrix**: Check supported Ruby/Redmica combinations in test/docker-compose.yml
3. **Rebuild Required**: Always rebuild index after Redmica updates (schema may have changed)
4. **Verification Required**: Re-run gate after update to confirm compatibility
5. **Rollback Plan**: Have rollback procedure ready before starting

## Health Checks

### Quick Health Check

Verify the plugin is functioning correctly:

```bash
cd /opt/redmine
bundle exec rails runner "puts WikiHub::Healthcheck.call.to_json" RAILS_ENV=production
```

Expected output:

```json
{"status":"ok","details":{"missing_tables":[],"pg_trgm_enabled":true,"recent_successful_index_run_at":"2026-04-02T10:00:00Z","errors":{}}}
```

### Database Connectivity

Check database tables exist:

```bash
cd /opt/redmine
bundle exec rails runner "
  tables = %w[wiki_hub_page_snapshots wiki_hub_page_links wiki_hub_page_profiles wiki_hub_tags wiki_hub_taggings wiki_hub_user_preferences wiki_hub_index_runs]
  tables.each do |t|
    exists = ActiveRecord::Base.connection.data_source_exists?(t)
    puts \"#{t}: #{exists ? 'OK' : 'MISSING'}\"
  end
" RAILS_ENV=production
```

### pg_trgm Extension

Verify the PostgreSQL trigram extension is enabled:

```bash
cd /opt/redmine
bundle exec rails runner "
  enabled = ActiveRecord::Base.connection.extension_enabled?('pg_trgm')
  puts \"pg_trgm extension: #{enabled ? 'ENABLED' : 'NOT ENABLED'}\"
" RAILS_ENV=production
```

### Index Status

Check the most recent index run:

```bash
cd /opt/redmine
bundle exec rails runner "
  run = WikiHub::IndexRun.order(created_at: :desc).first
  if run
    puts \"Last index run: ##{run.id}\"
    puts \"  Status: #{run.status}\"
    puts \"  Started: #{run.started_at}\"
    puts \"  Completed: #{run.completed_at || 'N/A'}\"
    puts \"  Pages processed: #{run.pages_processed}\"
    puts \"  Errors: #{run.error_message || 'None'}\"
  else
    puts 'No index runs found'
  end
" RAILS_ENV=production
```

## Canonical Workflow

This plugin follows a **Redmica-first development model**:

| Path | Purpose |
|------|---------|
| `/opt/redmica/plugins/redmine_wiki_hub` | **Canonical writable source** - all feature work happens here |
| `/root/workspace/repos/redmine_wiki_hub` | Export/sync target - read-only reference copy |
| `/opt/redmine/plugins/redmine_wiki_hub` | Reference-only - **do NOT modify directly** |

**Rule**: Never commit directly to `/root/workspace/repos/`. Make all changes in `/opt/redmica/plugins/redmine_wiki_hub/`, then sync outward.

### Controlled Sync Procedure (Gated)

Use the controlled sync script that enforces the regression gate:

```bash
# Check sync status without syncing
./scripts/sync-canonical-to-repo.sh --verify-only

# Preview what would be synced
./scripts/sync-canonical-to-repo.sh --dry-run

# Run full gated sync (runs regression tests first)
./scripts/sync-canonical-to-repo.sh
```

The sync script:
1. Verifies preconditions (directories exist)
2. Runs `./scripts/regression.sh --docker` (gate enforcement)
3. Syncs canonical to repo only if gate passes
4. Verifies post-sync state

**Exit codes**: 0 (success), 1 (gate/verification failed), 2 (preconditions not met)

### Manual Sync Verification

To manually verify sync status without the script:

```bash
diff -ruN \
  --exclude=.git --exclude=tmp --exclude=node_modules --exclude=coverage \
  --exclude=.github --exclude=.sisyphus \
  /opt/redmica/plugins/redmine_wiki_hub/ \
  /root/workspace/repos/redmine_wiki_hub/
```

Exit code 0 means trees are aligned. Any output indicates differences.

**Exclusions explained**:
- `.git/` - Repository metadata (repo-only)
- `.github/` - GitHub workflows and templates (repo-only)
- `.sisyphus/` - Project planning and notepads (repo-only)
- `tmp/`, `node_modules/`, `coverage/` - Build artifacts

## Deployment Procedures

### Fresh Installation (Non-Canonical Redmine)

For deploying to `/opt/redmine/plugins/redmine_wiki_hub` (reference-only):

1. **Verify sync from canonical source:**

```bash
diff -ruN \
  --exclude=.git --exclude=tmp --exclude=node_modules --exclude=coverage \
  --exclude=.github --exclude=.sisyphus \
  /opt/redmica/plugins/redmine_wiki_hub/ \
  /root/workspace/repos/redmine_wiki_hub/
```

2. **Deploy plugin files:**

```bash
rsync -a --delete \
  --exclude .git --exclude tmp --exclude node_modules --exclude coverage \
  --exclude .github --exclude .sisyphus \
  /root/workspace/repos/redmine_wiki_hub/ \
  /opt/redmine/plugins/redmine_wiki_hub/
```

2. **Install dependencies:**

```bash
cd /opt/redmine
bundle install --without development test
```

3. **Run migrations:**

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production
```

4. **Build initial index:**

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

5. **Restart Redmine:**

```bash
# For Passenger
touch /opt/redmine/tmp/restart.txt

# For Puma
systemctl restart redmine-puma

# For Unicorn
systemctl restart redmine-unicorn
```

### Update Deployment (Non-Canonical Redmine)

1. **Verify canonical source is in sync:**

```bash
diff -ruN \
  --exclude=.git --exclude=tmp --exclude=node_modules --exclude=coverage \
  --exclude=.github --exclude=.sisyphus \
  /opt/redmica/plugins/redmine_wiki_hub/ \
  /root/workspace/repos/redmine_wiki_hub/
```

Exit code 0 means synced—any output indicates the canonical and export trees still need sync/export.

2. **Deploy new version:**

```bash
rsync -a --delete \
  --exclude .git --exclude tmp --exclude node_modules --exclude coverage \
  --exclude .github --exclude .sisyphus \
  /root/workspace/repos/redmine_wiki_hub/ \
  /opt/redmine/plugins/redmine_wiki_hub/
```

3. **Update dependencies:**

```bash
cd /opt/redmine
bundle install --without development test
```

4. **Run migrations:**

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production
```

5. **Verify health:**

```bash
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production
```

6. **Restart if healthy:**

```bash
touch /opt/redmine/tmp/restart.txt
```

### Rollback Procedure

**WARNING**: See [Rollback Flow](#rollback-flow-complete-procedure) in Operational Procedures for the complete rollback process that handles both code and schema/index state.

Quick rollback (for emergencies only):

1. **Stop Application:**

```bash
touch /opt/redmine/tmp/restart.txt  # or systemctl stop redmine
```

2. **Rollback Database Migrations:**

```bash
cd /opt/redmine
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub VERSION=0 RAILS_ENV=production
```

3. **Restore Plugin Code:**

```bash
rm -rf /opt/redmine/plugins/redmine_wiki_hub
tar -xzf /backup/redmine_wiki_hub_TIMESTAMP.tar.gz -C /opt/redmine/plugins
```

4. **Rebuild Index (REQUIRED after rollback):**

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

5. **Restart and Verify:**

```bash
touch /opt/redmine/tmp/restart.txt
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production
```

## Index Management

### Full Rebuild

Rebuild the entire index (use during maintenance windows):

```bash
cd /opt/redmine
bundle exec rake wiki_hub:rebuild RAILS_ENV=production 2>&1 | tee /var/log/redmine/wiki_hub_rebuild_$(date +%Y%m%d_%H%M%S).log
```

Expected runtime: approximately 1-2 minutes per 1000 pages.

### Schedule Regular Rebuilds

Add to crontab for nightly rebuilds:

```bash
# Edit crontab
sudo crontab -e

# Add entry for 3 AM daily
0 3 * * * cd /opt/redmine && /usr/local/bin/bundle exec rake wiki_hub:rebuild RAILS_ENV=production >> /var/log/redmine/wiki_hub_cron.log 2>&1
```

### Monitor Index Performance

Check index run history:

```bash
cd /opt/redmine
bundle exec rails runner "
  WikiHub::IndexRun.where('created_at >= ?', 7.days.ago)
                    .order(created_at: :desc)
                    .each do |run|
    status_icon = run.status == 'completed' ? 'OK' : 'FAIL'
    puts \"#{status_icon} ##{run.id} #{run.status} | #{run.pages_processed} pages | #{run.completed_at || 'incomplete'}\"
  end
" RAILS_ENV=production
```

### Handle Index Failures

If an index run fails:

1. **Check error message:**

```bash
cd /opt/redmine
bundle exec rails runner "
  run = WikiHub::IndexRun.where(status: 'failed').order(created_at: :desc).first
  puts run&.error_message || 'No failed runs found'
" RAILS_ENV=production
```

2. **Review logs:**

```bash
tail -n 100 /opt/redmine/log/production.log | grep -i wiki_hub
```

3. **Retry rebuild:**

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

## Monitoring

### Key Metrics

Monitor these metrics for plugin health:

| Metric | Command | Warning Threshold |
|--------|---------|-------------------|
| Pages indexed | `WikiHub::PageSnapshot.count` | Should match wiki page count |
| Unresolved links | `WikiHub::PageLink.where(resolved: false).count` | >100 may indicate issues |
| Last successful index | `WikiHub::IndexRun.where(status: 'completed').maximum(:completed_at)` | >24 hours ago |
| Failed index runs | `WikiHub::IndexRun.where(status: 'failed').count` | Any in last 24 hours |

### Log Monitoring

Watch for these error patterns:

```bash
# Wiki Hub specific errors
tail -f /opt/redmine/log/production.log | grep -i "wiki_hub"

# Database errors
tail -f /opt/redmine/log/production.log | grep -i "wiki_hub.*error"

# Indexing failures
tail -f /opt/redmine/log/production.log | grep -i "reindex.*failed"
```

### Alerting Rules

Set up alerts for:

1. **No successful index in 24 hours:**

```bash
cd /opt/redmine
bundle exec rails runner "
  last_run = WikiHub::IndexRun.where(status: 'completed').maximum(:completed_at)
  if last_run.nil? || last_run < 24.hours.ago
    puts 'ALERT: No successful wiki hub index in 24 hours'
    exit 1
  end
" RAILS_ENV=production
```

2. **Failed index run:**

```bash
cd /opt/redmine
bundle exec rails runner "
  if WikiHub::IndexRun.where(status: 'failed').where('created_at >= ?', 1.hour.ago).exists?
    puts 'ALERT: Wiki hub index failed in last hour'
    exit 1
  end
" RAILS_ENV=production
```

3. **Missing database tables:**

```bash
cd /opt/redmine
bundle exec rails runner "
  required = %w[wiki_hub_page_snapshots wiki_hub_page_links wiki_hub_page_profiles wiki_hub_index_runs]
  missing = required.reject { |t| ActiveRecord::Base.connection.data_source_exists?(t) }
  if missing.any?
    puts \"ALERT: Missing tables: #{missing.join(', ')}\"
    exit 1
  end
" RAILS_ENV=production
```

## Verification Procedures

### Local Health Verification

Run these checks on the application server:

```bash
# 1. Health check status
cd /opt/redmine
bundle exec rails runner "puts WikiHub::Healthcheck.call.to_json" RAILS_ENV=production

# Expected: {"status":"ok","details":{"missing_tables":[],"pg_trgm_enabled":true,...}}

# 2. Plugin loaded correctly
bundle exec rails runner "
  plugin = Redmine::Plugin.find(:redmine_wiki_hub)
  puts \"Plugin: #{plugin.name} v#{plugin.version}\"
  puts \"Migrations: #{ActiveRecord::Base.connection.data_source_exists?('wiki_hub_page_snapshots')}\"
" RAILS_ENV=production

# 3. Index freshness
bundle exec rails runner "
  last_run = WikiHub::IndexRun.where(status: 'completed').maximum(:completed_at)
  puts \"Last successful index: #{last_run || 'Never'}\"
  puts \"Pages indexed: #{WikiHub::PageSnapshot.count}\"
" RAILS_ENV=production
```

### Public Endpoint Verification

Verify the public endpoint responds correctly:

```bash
# Check HTTP status (unauthenticated returns 302 to login)
curl -s -o /dev/null -w "%{http_code}" https://redmica.sbg-server.com/knowledge_hub
# Expected: 302 (redirect to login) or 200 (if already authenticated)

# Follow redirects and check for content (if checking anonymously)
curl -sL https://redmica.sbg-server.com/knowledge_hub | grep -q "Wiki Hub\|Login"
# Expected: Exit code 0 (found "Wiki Hub" if auth'd, or "Login" if redirected)

# Verify JSON API responds
curl -s https://redmica.sbg-server.com/knowledge_hub.json | head -1
# Expected: Valid JSON response
```

### Rebuild Verification

After running `wiki_hub:rebuild`, verify success:

```bash
# Run rebuild with logging
cd /opt/redmine
bundle exec rake wiki_hub:rebuild RAILS_ENV=production 2>&1 | tee /tmp/rebuild_$(date +%Y%m%d_%H%M%S).log

# Verify rebuild succeeded (check last few lines)
tail -5 /tmp/rebuild_*.log
# Expected: "Completed in X.XXs", "Errors: 0"

# Verify health after rebuild
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production
# Expected: Exit code 0

# Verify index run logged
bundle exec rails runner "
  run = WikiHub::IndexRun.order(created_at: :desc).first
  puts \"Latest run: #{run.status} | #{run.pages_processed} pages | #{run.completed_at}\"
" RAILS_ENV=production
```

### Maintenance Window Procedures

**When to use maintenance windows:**

1. **Plugin updates** requiring migrations
2. **Full index rebuild** on large instances (>10000 pages)
3. **Redmica version updates**
4. **Database maintenance** (vacuum, reindex)

**Pre-window checklist:**

```bash
# Verify current health
./scripts/regression.sh --docker  # If updating code
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production

# Backup database
pg_dump -h localhost -U redmine -d redmine | gzip > /backup/pre_maintenance_$(date +%Y%m%d_%H%M%S).sql.gz

# Announce maintenance to users
# (via Redmine admin interface or external notification)
```

**Post-window verification:**

```bash
# 1. Application health
bundle exec rails runner "exit WikiHub::Healthcheck.call[:status] == 'ok' ? 0 : 1" RAILS_ENV=production

# 2. Public endpoint
curl -s -o /dev/null -w "%{http_code}" https://redmica.sbg-server.com/knowledge_hub

# 3. Search functionality
curl -s "https://redmica.sbg-server.com/knowledge_hub/search?q=test" | grep -q "results"

# 4. No recent errors in logs
tail -100 /opt/redmine/log/production.log | grep -i "wiki_hub.*error" || echo "No errors found"
```

## Backup and Restore

### Backup Plugin Data

Backup all Wiki Hub tables:

```bash
pg_dump -h localhost -U redmine -d redmine \
  --table='wiki_hub_*' \
  > /backup/wiki_hub_$(date +%Y%m%d_%H%M%S).sql
```

### Backup Full Database

Include Wiki Hub in full database backup:

```bash
pg_dump -h localhost -U redmine -d redmine \
  | gzip > /backup/redmine_full_$(date +%Y%m%d_%H%M%S).sql.gz
```

### Restore Plugin Data

Restore from SQL backup:

```bash
# Restore Wiki Hub tables
psql -h localhost -U redmine -d redmine < /backup/wiki_hub_TIMESTAMP.sql

# Rebuild index after restore
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

### Verify Backup Integrity

```bash
# Check backup contains Wiki Hub tables
gunzip -c /backup/redmine_full_TIMESTAMP.sql.gz | grep -c "wiki_hub_page_snapshots"

# Should return count > 0
```

## Incident Response

### Search Returns No Results

**Symptoms:** Users report empty search results

**Diagnosis:**

```bash
# Check index status
cd /opt/redmine
bundle exec rails runner "
  puts \"Snapshots: #{WikiHub::PageSnapshot.count}\"
  puts \"Last index: #{WikiHub::IndexRun.where(status: 'completed').maximum(:completed_at)}\"
  puts \"pg_trgm: #{ActiveRecord::Base.connection.extension_enabled?('pg_trgm')}\"
" RAILS_ENV=production
```

**Resolution:**

1. If pg_trgm not enabled:

```bash
psql -h localhost -U redmine -d redmine -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

2. If index stale:

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

### High Database Load

**Symptoms:** Slow queries, high CPU on PostgreSQL

**Diagnosis:**

```bash
# Check for slow queries
psql -h localhost -U redmine -d redmine -c "
  SELECT query, calls, mean_time
  FROM pg_stat_statements
  WHERE query LIKE '%wiki_hub%'
  ORDER BY mean_time DESC
  LIMIT 10;
"
```

**Resolution:**

1. Verify indexes exist:

```bash
psql -h localhost -U redmine -d redmine -c "
  SELECT indexname, indexdef
  FROM pg_indexes
  WHERE tablename LIKE 'wiki_hub%'
  ORDER BY tablename;
"
```

2. Rebuild GIN indexes if needed:

```bash
psql -h localhost -U redmine -d redmine -c "
  REINDEX INDEX index_wiki_hub_page_snapshots_on_title_trgm;
  REINDEX INDEX index_wiki_hub_page_links_on_target_title_trgm;
"
```

### Plugin Menu Not Visible

**Symptoms:** Wiki Hub menu item missing from top navigation

**Diagnosis:**

```bash
# Check plugin loaded
cd /opt/redmine
bundle exec rails runner "
  plugin = Redmine::Plugin.find(:redmine_wiki_hub)
  puts \"Plugin: #{plugin.name} v#{plugin.version}\"
  puts \"Migrations: #{ActiveRecord::Base.connection.data_source_exists?('wiki_hub_page_snapshots')}\"
" RAILS_ENV=production
```

**Resolution:**

1. Check plugin directory exists and has correct permissions
2. Verify migrations ran successfully
3. Restart Redmine application server

### Data Inconsistency

**Symptoms:** Links showing as unresolved when targets exist

**Resolution:**

1. Run reconciliation:

```bash
cd /opt/redmine
bundle exec rails runner "
  WikiHub::Indexer.send(:reconcile_unresolved_links!)
  puts 'Unresolved links reconciled'
" RAILS_ENV=production
```

2. Full rebuild if issues persist:

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

## Performance Tuning

### Database Tuning

For high-volume installations, tune PostgreSQL:

```conf
# postgresql.conf
work_mem = 256MB                    # Increase for complex queries
maintenance_work_mem = 512MB        # For index maintenance
shared_buffers = 2GB                # Adjust based on available RAM
effective_cache_size = 6GB          # Estimate of OS cache
random_page_cost = 1.1              # For SSD storage
```

### Query Optimization

Monitor slow queries and add indexes as needed:

```sql
-- Example: Add index for frequently filtered queries
CREATE INDEX CONCURRENTLY idx_wiki_hub_snapshots_project_updated 
  ON wiki_hub_page_snapshots (project_id, updated_at DESC);
```

### Caching

Enable Rails caching for improved performance:

```yaml
# config/environments/production.yml
config.cache_store = :redis_cache_store, { url: 'redis://localhost:6379/0' }
```

## Maintenance Windows

Schedule these activities during maintenance windows:

1. **Full index rebuild** - Weekly or monthly
2. **Database vacuum** - For PostgreSQL maintenance
3. **Plugin updates** - Including migration runs
4. **Log rotation** - Archive old logs

## Support Contacts

- **Technical issues:** Development team
- **Database issues:** DBA team
- **Infrastructure issues:** Operations team
- **Emergency escalations:** On-call engineer

## Quick Reference Card

### Essential Commands

```bash
# Health check
bundle exec rails runner "puts WikiHub::Healthcheck.call.to_json" RAILS_ENV=production

# Rebuild index
bundle exec rake wiki_hub:rebuild RAILS_ENV=production

# Count indexed pages
bundle exec rails runner "puts WikiHub::PageSnapshot.count" RAILS_ENV=production

# Count unresolved links
bundle exec rails runner "puts WikiHub::PageLink.where(resolved: false).count" RAILS_ENV=production

# View recent errors
tail -n 100 /opt/redmine/log/production.log | grep -i wiki_hub

# Restart Redmine (Passenger)
touch /opt/redmine/tmp/restart.txt
```

### Gate and Sync Commands

```bash
# Run regression gate (Task 10)
./scripts/regression.sh --docker

# Sync canonical to repo (Task 11 - gated)
./scripts/sync-canonical-to-repo.sh

# Verify sync without syncing
./scripts/sync-canonical-to-repo.sh --verify-only

# Preview sync changes
./scripts/sync-canonical-to-repo.sh --dry-run
```

### File Locations

| File/Directory | Path | Notes |
|----------------|------|-------|
| Canonical source | `/opt/redmica/plugins/redmine_wiki_hub` | Writable - all development here |
| Export target | `/root/workspace/repos/redmine_wiki_hub` | Read-only reference copy |
| Plugin directory (reference) | `/opt/redmine/plugins/redmine_wiki_hub` | Read-only - do not modify directly |
| Log files | `/opt/redmine/log/production.log` | |
| Database migrations | `/opt/redmine/plugins/redmine_wiki_hub/db/migrate` | Actually stored in canonical source |
