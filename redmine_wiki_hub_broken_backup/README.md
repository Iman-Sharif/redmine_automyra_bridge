# Redmine Wiki Hub

A unified wiki hub plugin for Redmine that provides global and project-scoped knowledge entry points with advanced search, cross-project linking, and relationship visualization.

## Overview

Wiki Hub creates a centralized index of all accessible wiki pages across projects. The current native UI migration also narrowed the presentation contract so primary list and table surfaces now follow Redmica-native structures instead of plugin-local card or design-system layouts.

Current delivered outcomes:

- Fast full-text search across all accessible wiki content
- Cross-project wiki linking with bracketed wiki-link syntax like `[[@project/page]]`
- Knowledge graph visualization of page relationships
- Page categorization and tagging
- Template and lesson-learned page kinds
- User preferences for homepage integration
- Native migration of homepage, search, index, template, lesson, backlink, metadata, and admin list or table surfaces
- Explicit exception boundary for graph or canvas presentation through `wiki_hub_graph.css`

## Requirements

- Supported/tested runtime: Redmica 3.2.6 (via `my-redmica:v3.2.6-staging`)
- Supported/tested Ruby: 3.3
- Supported/tested PostgreSQL: 16 with `pg_trgm` enabled

The current compatibility gate supports only the pinned runtime above. Treat other Redmine/Redmica, Ruby, or PostgreSQL versions as unsupported until the gate is updated and passing for them.

## Pinned Compatibility Gate

This plugin uses a **pinned compatibility gate** that validates against a specific Redmica/Ruby stack before any sync or deploy is permitted.

**Pinned Runtime**:
- Redmica 3.2.6 (via `my-redmica:v3.2.6-staging`)
- Ruby 3.3 (via `RUBY_VERSION`)
- PostgreSQL 16 (via `postgres:16-bookworm`)

**Gate Enforcement**: The regression suite MUST pass before promotion:

```bash
./scripts/regression.sh --docker
```

The sync script (`sync-canonical-to-repo.sh`) blocks export if regression tests fail. Do not update Redmica or promote to new environments without a passing gate.

## Canonical Workflow

This plugin follows a **Redmica-first development model**:

| Path | Purpose |
|------|---------|
| `/opt/redmica/plugins/redmine_wiki_hub` | **Canonical writable source** - all feature work happens here |
| `/root/workspace/repos/redmine_wiki_hub` | Export/sync target - read-only reference copy |
| `/opt/redmine/plugins/redmine_wiki_hub` | Reference-only - **do NOT modify directly** |

**Rule**: Never commit directly to `/root/workspace/repos/`. Make all changes in `/opt/redmica/plugins/redmine_wiki_hub/`, then sync outward.

### Controlled Sync from Canonical (Gated)

Use the gated sync script to export from canonical to repo:

```bash
cd /opt/redmica/plugins/redmine_wiki_hub

# Check if sync is needed
./scripts/sync-canonical-to-repo.sh --verify-only

# Preview what would be synced
./scripts/sync-canonical-to-repo.sh --dry-run

# Run full gated sync (tests must pass first)
./scripts/sync-canonical-to-repo.sh
```

The sync enforces the regression gate - it will block if `./scripts/regression.sh --docker` fails.

### Manual Sync Verification

Check that the canonical and export trees are in sync:

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

### Operational Procedures

For detailed deployment, rollback, and Redmica update procedures, see `docs/runbook.md`:

- **Deploy Flow**: Complete procedure from gate → sync → boot → verification
- **Rollback Flow**: Code + schema/index rollback (not just code)
- **Redmica Update**: Promotion rules with compatibility gate enforcement

## Installation

### 1. Copy Plugin Files

**From the repo copy** (when deploying to non-canonical Redmine):

```bash
rsync -a --delete \
  --exclude .git --exclude tmp --exclude node_modules --exclude coverage \
  --exclude .github --exclude .sisyphus \
  /root/workspace/repos/redmine_wiki_hub/ \
  /opt/redmine/plugins/redmine_wiki_hub/
```

**Note**: The canonical writable source is at `/opt/redmica/plugins/redmine_wiki_hub`. All development work must happen there, not in `/opt/redmine/plugins/redmine_wiki_hub` (which is reference-only).

### 2. Install Dependencies

```bash
cd /opt/redmine
bundle install
```

### 3. Run Database Migrations

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production
```

### 4. Build Initial Index

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

### 5. Restart Redmine

Restart your application server (Apache, Nginx, Puma, etc.) to load the plugin.

**Production deployments**: Remember that `/opt/redmica/plugins/redmine_wiki_hub` is the canonical writable path. Any changes made directly to `/opt/redmine/plugins/redmine_wiki_hub` will be overwritten during sync operations.

## Usage

### Accessing Wiki Hub

Once installed, a **Wiki Hub** menu item appears in the top navigation bar. The migrated list and table surfaces now rely on host Redmica styling, so visual behavior should follow the active theme rather than plugin-owned branding.

Users can access:

- Global search across all accessible wiki pages
- Project-scoped search when viewing a project
- Native list or table driven views for templates, lessons, backlinks, metadata, and admin surfaces
- Graph visualization as the one intentional non-native presentation boundary

### Link Syntax

Wiki Hub recognizes two link formats in wiki page content:

#### Internal Links (Same Project)

Use double brackets to link to pages within the same project:

```
[[Page Title]]
```

You can also specify display text:

```
[[Page Title|Click here to read more]]
```

#### Cross-Project Links

Use `@` prefix inside wiki link brackets to link to pages in other projects:

```
[[@other-project/Page Title]]
```

Examples:

```
[[@marketing/Brand Guidelines]]
[[@engineering/API Documentation]]
```

### Page Kinds

Pages can be classified into three kinds:

| Kind | Description |
|------|-------------|
| `standard` | Regular wiki pages (default) |
| `template` | Reusable page templates |
| `lesson_learned` | Knowledge capture from project experiences |

### Default Categories

Pages can be categorized using these default categories:

- **Agreements** - Contracts, SLAs, and formal agreements
- **Competition** - Competitive analysis and market research
- **Supplier** - Vendor and supplier documentation
- **Policy** - Organizational policies and guidelines
- **Process** - Procedures and workflows
- **General** - Uncategorized content

### Search Features

The search functionality provides:

- Full-text search across page titles and content
- Fuzzy matching using PostgreSQL trigram similarity
- Results limited to **10 items** per query
- Filtering by category, page kind, and tags
- Ranking by relevance (exact match > prefix match > content match)

### Graph Visualization

Wiki Hub includes a knowledge graph showing page relationships. This page remains the explicit exception boundary in the native migration, because canvas, tooltip, legend, and control affordances still need dedicated `wiki_hub_graph.css` support while the rest of the plugin falls through to Redmica-native structures.

- Maximum **150 nodes** displayed
- Maximum **300 edges** (links) shown
- Visual representation of cross-project connections
- Navigation from graph to individual pages

### Homepage Integration

Users can opt-in to show Wiki Hub on their Redmine homepage:

1. Go to **My Account**
2. Enable the **Show Wiki Hub on homepage** preference
3. The hub will appear on your personal dashboard

This is an opt-in feature disabled by default for all users.

## Configuration

### Environment Variables

No environment variables are required. The plugin uses standard Redmine configuration.

### Database Requirements

The plugin requires the PostgreSQL `pg_trgm` extension for text search:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

This is automatically enabled during migration.

### Permission Requirements

Users need the following Redmine permissions to use Wiki Hub:

- `view_wiki_pages` - to view and search wiki content
- `edit_wiki_pages` - to create and modify pages (for hooks to work)

## Rake Tasks

### Rebuild Index

Rebuild the entire wiki hub index from current wiki pages:

```bash
bundle exec rake wiki_hub:rebuild RAILS_ENV=production
```

This task:

- Scans all wiki pages
- Extracts searchable text
- Parses and resolves page links
- Creates page profiles for new pages
- Cleans up data for deleted pages
- Updates the index run log

### Migration Tasks

Run plugin migrations:

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub RAILS_ENV=production
```

Rollback migrations:

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub VERSION=0 RAILS_ENV=production
```

## API Endpoints

Wiki Hub provides JSON API endpoints:

### Global Endpoints

- `GET /knowledge_hub` - List all accessible pages
- `GET /knowledge_hub/search?q=term` - Search pages

### Project-Scoped Endpoints

- `GET /projects/:project_id/wiki_hub` - List project pages
- `GET /projects/:project_id/wiki_hub/search?q=term` - Search within project
- `GET /projects/:project_id/wiki_hub/metadata` - Get project metadata

### Query Parameters

All list and search endpoints support:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `category` | Filter by category | `?category=Policy` |
| `page_kind` | Filter by page kind | `?page_kind=template` |
| `tag` | Filter by tag name | `?tag=documentation` |
| `limit` | Results per page (max 100) | `?limit=50` |
| `offset` | Pagination offset | `?offset=25` |
| `order` | Sort column (updated_at, title) | `?order=title` |
| `direction` | Sort direction (asc, desc) | `?direction=asc` |

## Data Model

The plugin creates the following database tables:

### wiki_hub_page_snapshots

Stores indexed wiki page content:

- `wiki_page_id` - Reference to Redmine wiki page
- `project_id` - Owning project
- `title` - Page title
- `searchable_text` - Combined title and content for search
- `current_version_id` - Latest content version

### wiki_hub_page_profiles

Stores page metadata:

- `wiki_page_id` - Reference to wiki page
- `page_kind` - Type (standard, template, lesson_learned)
- `category` - Classification category
- `lesson_date` - Date for lesson_learned pages
- `summary` - Brief description
- `featured` - Whether page is featured

### wiki_hub_page_links

Stores wiki link relationships:

- `source_page_id` - Page containing the link
- `target_page_id` - Linked page (null if unresolved)
- `target_project_id` - Project of target page
- `target_title` - Title of target page
- `resolved` - Whether link target exists
- `link_type` - Type of link (wiki)

### wiki_hub_tags

Stores tag definitions:

- `name` - Tag name (unique, case-insensitive)

### wiki_hub_taggings

Links tags to pages:

- `wiki_page_id` - Tagged page
- `tag_id` - Tag reference

### wiki_hub_user_preferences

Stores user preferences:

- `user_id` - User reference
- `homepage_enabled` - Whether to show hub on homepage

### wiki_hub_index_runs

Tracks indexing operations:

- `started_at` - Index start time
- `completed_at` - Index completion time
- `status` - pending, running, completed, failed
- `pages_processed` - Number of pages indexed
- `error_message` - Any error details

## Troubleshooting

### Search Returns No Results

1. Verify the index has been built: `bundle exec rake wiki_hub:rebuild`
2. Check that pages exist and are visible to your user
3. Confirm the `pg_trgm` extension is enabled in PostgreSQL
4. Review index run status in the database

### Links Not Resolving

1. Check that target pages exist
2. Verify the project identifier in cross-project links is correct
3. Ensure target project wiki module is enabled
4. Rebuild the index after making changes

### Slow Search Performance

1. Ensure GIN indexes were created during migration
2. Check PostgreSQL query performance
3. Consider increasing PostgreSQL work_mem for complex queries

### Migration Failures

1. Verify PostgreSQL version compatibility
2. Check that the `pg_trgm` extension is available
3. Review Redmine logs for detailed error messages
4. Ensure proper database permissions

### Missing Menu Item

1. Confirm plugin is properly installed
2. Check that migrations have been run
3. Verify Redmine has been restarted
4. Review plugin initialization in logs

## Testing

### Regression Suite (Recommended)

Run the full compatibility regression suite:

```bash
./scripts/regression.sh --docker    # Run in Docker (default)
./scripts/regression.sh --local     # Run locally (requires Redmine environment)
```

The regression script:
- Verifies plugin structure
- Runs all tests in isolated Docker environment
- Reports pass/fail with exit codes

### Manual Test Execution

Run tests directly (requires configured Redmine environment):

```bash
docker compose -f test/docker-compose.yml exec -T redmine \
  bundle exec rails test plugins/redmine_wiki_hub/test RAILS_ENV=test
```

Or locally:

```bash
cd /opt/redmine
bundle exec rails test plugins/redmine_wiki_hub/test RAILS_ENV=test
```

## Uninstallation

1. Rollback database migrations:

```bash
bundle exec rails redmine:plugins:migrate NAME=redmine_wiki_hub VERSION=0 RAILS_ENV=production
```

2. Remove plugin directory (for non-canonical Redmine only):

```bash
rm -rf /opt/redmine/plugins/redmine_wiki_hub
```

**Important**: Do NOT remove `/opt/redmica/plugins/redmine_wiki_hub` - this is the canonical writable source.

3. Restart Redmine

## Support

For issues, questions, or contributions, please refer to the project repository or documentation.

## License

This plugin is released under the same license as Redmine (GNU General Public License v2).

## Credits

Developed by OpenCode as a unified knowledge management solution for Redmine.
