# Task Hub release-readiness notes

This note is for the current `redmine_task_hub` MVP under `/opt/redmica/plugins/redmine_task_hub`. It covers only the plugin behavior shipped here, the install and upgrade path that matches this repository, and the user-facing limits that admins should communicate before release.

## Admin quick summary
- Plugin name: `redmine_task_hub`
- Supported host target declared by the plugin: Redmica/Redmine `6.0`
- Main top menu entry: `Task Hub`
- Main routes:
  - `/task_hub` for the owner-centric dashboard
  - `/tasks` for standalone tasks
  - `/issues/:issue_id/tasks` for issue-linked task endpoints and issue page task management
  - `/tasks/:id/promote` and `/issues/:issue_id/tasks/:id/promote` for promotion
- Required upgrade step after pulling changes: run plugin migrations
- Practical post-change note: if plugin CSS or JS does not appear after deploy, restart the Redmica app container or process and hard refresh the browser
- Verification limit in this shell: Ruby, Bundler, and ruby-lsp are unavailable here, so runtime verification must happen in the containerized Redmica plugin environment

## Install
1. Place this plugin at `/opt/redmica/plugins/redmine_task_hub` in the Redmica environment.
2. Install any host-side dependencies through the normal Redmica plugin workflow used by your deployment.
3. Run the plugin migration step in the Redmica runtime environment.
4. Restart Redmica or the app container so routes, hooks, assets, and plugin registration reload cleanly.
5. Open Redmica, then hard refresh the browser once if Task Hub styles or issue-page behavior look stale.

## Upgrade
1. Replace or update the plugin files in `/opt/redmica/plugins/redmine_task_hub`.
2. Run plugin migrations again. This plugin expects schema changes to be applied before use.
3. Restart the Redmica app container or server process.
4. Hard refresh the browser if Task Hub CSS or the issue-page task panel still reflects older assets.
5. Re-check the surfaces listed below with a user account that matches expected permissions.

## Migration expectations
The plugin stores records in `task_hub_tasks`.
Current migration state in this repository creates or maintains:
- task attributes such as title, notes, status, due date, assignee, project, issue link, and ordering position
- promotion metadata via `promoted_issue_id` and `promoted_at`
- indexes for owner/status access, issue ordering, due date, project, and promotion lookups

Operational expectation:
- Do not skip migrations on upgrade.
- Promotion metadata and retention behavior depend on the migrated columns existing.
- If migrations are not applied, dashboard slices, promotion backlinks, and visibility rules can break or show incomplete data.

## Plugin entry points and UI surfaces
### Native UI migration status
- Current Task Hub surfaces now render with Redmica-native structures first: `contextual`, `box`, `box tabular`, `table.list`, `p.nodata`, and host-theme typography/layout.
- Plugin-local design-system styling was removed from migrated page surfaces. `task_hub_dashboard.css` and `task_hub_standalone.css` have been removed.
- Rollout expectation: visual differences should come from the host theme, not from plugin-owned branding or alternate layout systems.

### CSS exceptions (intentional non-native behavior)
The following CSS files contain intentional exceptions that deviate from strict native Redmica styling:

- **task_hub_kanban.css** - Kanban board layout exception (non-native behavior for drag-and-drop board presentation)
- **task_hub_issue_tasks.css** - Narrow checkbox sizing exception for issue-linked task tables
- **wiki_hub_graph.css** - Graph/canvas visualization exception (in Wiki Hub, distinct from Task Hub)
- **wiki_hub_accessibility.css** - Accessibility enhancement exception (in Wiki Hub)
- **wiki_hub_autocomplete.css** - Search suggestion behavior exception (in Wiki Hub)
- **wiki_hub.css** - Toggle rotation and search positioning behavior hooks (in Wiki Hub)

### 1. Task Hub dashboard
- Route: `/task_hub`
- Added to the top menu as `Task Hub`
- Purpose: personal execution dashboard across tasks visible to the current user
- View model:
  - `dashboard` is the grouped personal execution view
  - `list` is the filterable flat worklist view
  - `kanban` is the bounded board view described below
- Main sections:
  - My Open Tasks
  - Due Today
  - Overdue
  - Recently Completed
- Grouped side sections:
  - Visible Tasks by Issue
  - Visible Tasks by Project
- Bounded behavior:
  - dashboard sections return up to 50 tasks each
  - grouped issue and project blocks return up to 20 groups
  - each grouped block returns up to 50 tasks per group
  - recently completed is capped at 10 records

### 2. Standalone tasks
- Route: `/tasks`
- Scope: lightweight tasks owned by the current user, optionally tied to a project, but not tied to an issue
- Persistence behavior shared with `/task_hub`:
  - the selected Task Hub view persists per user in `UserPreference.others[:task_hub]`
  - list filters persist alongside the selected view for later visits
  - the same bounded filter vocabulary is reused instead of introducing separate saved searches
- Main UI behaviors:
  - quick add supports title-first creation
  - optional details include project ID, assignee ID, due date, and notes
  - edit, complete, cancel, reopen, and promote actions appear when allowed
  - the standalone UI may use "archive" wording after the destroy/cancel soft-hide path, but this is UI copy for the cancelled/hidden outcome rather than a separate archive action or state
- Bounded behavior:
  - paginated in 50-row pages via `?page=`
  - supported filters are limited to status, due bucket, context, assigned-to-me, project, and title search

### 3. Issue-linked tasks
- Issue page hook: the task panel is injected on issue detail pages through `view_issues_show_details_bottom`
- API and management route family: `/issues/:issue_id/tasks`
- Scope: lightweight child tasks linked to one Redmica issue
- Main UI behaviors:
  - quick add and lightweight state changes from the issue surface
  - edit and cancel from task actions when allowed
  - promote from the issue task row when allowed
  - backlink remains after promotion
- Bounded behavior:
  - issue-linked task responses and the rendered issue panel show the first 100 tasks ordered by position
  - the issue panel explicitly warns when more tasks exist outside that slice

### 4. Kanban MVP status
- Route shape: `/task_hub?view=kanban`
- Persistence follows the same per-user `UserPreference.others[:task_hub]` contract as dashboard and list, so a user returning later lands on the last selected view.
- Intended scope is intentionally narrow:
  - four fixed status columns from `TaskHub::Task::STATUSES`
  - same underlying task query data as the other Task Hub views
  - lightweight drag and drop transitions posting into existing move endpoints
  - native structural markup with only board or card hook classes where needed
- Limits and caveats that must stay visible in rollout notes:
  - this is an MVP board, not a full planning system
  - no swimlanes, WIP controls, saved board filters, analytics, or team planning overlays
  - live browser verification on the plugin-loaded app at `http://127.0.0.1:4000` passed after the runtime restart, cache clear, and scoped asset-loading fixes landed
  - Kanban acceptance is now signed off for this environment, while the MVP scope limits above still apply

### 5. Promotion flow
- Routes:
  - `/tasks/:id/promote`
  - `/issues/:issue_id/tasks/:id/promote`
- GET opens a promotion summary page
- POST creates a native Redmica issue in a single transaction
- Promotion copies task title, notes, assignee when assignable, due date, and sets the new issue start date to the current date
- Promotion writes a reference line into the issue description: `Promoted from Task Hub task #<id>.`
- After success, the browser is redirected to the new Redmica issue

## Permissions and visibility
### Standalone tasks
- Normal users only see their own standalone tasks
- Owners can create, edit, complete, cancel, reopen, and promote their own standalone tasks when other checks pass
- Admins can see standalone tasks across users
- Promotion for standalone tasks still requires native issue creation permission in the target project

### Issue-linked tasks
- Visibility follows the linked issue project through Redmica permissions
- Users need the plugin project permissions to view or manage issue-linked tasks in that project
- If a user loses access to the linked project or issue context, Task Hub treats the task as hidden or not found rather than leaking metadata

### Promotion permission model
- Promotion does not use a custom plugin-specific promotion permission
- Promotion reuses native Redmica `:add_issues`
- A task can be promoted only when the user can already view the task and can add issues in the target project
- For issue-linked tasks, the target project must stay the parent issue project
- For standalone tasks with a project, the target project must stay that same project
- For projectless standalone tasks, the promotion page asks the user to choose a project from projects where they can add issues

## Lifecycle and retention
### Supported statuses
- `todo`
- `in_progress`
- `done`
- `cancelled`

### Reopen rules
- Open tasks are `todo` and `in_progress`
- Closed tasks are `done` and `cancelled`
- Reopen requests allow `todo` or `in_progress` as incoming intent, but cancelled tasks are model-restricted to reopen only to `todo`
- Promoted tasks cannot reopen because they become read-only records

### Promotion as a terminal state
- Promotion sets the task status to `done`
- Promotion also sets `completed_at`, `promoted_issue_id`, and `promoted_at`
- Once promoted, the task is read-only across model, service, controller, and view layers
- The promoted task remains in Task Hub only as metadata and backlink context, not as an editable work item

### Retention and active-surface behavior
- Active Task Hub surfaces retain open tasks plus promoted done tasks
- Plain done tasks without promotion are not retained on active surfaces
- Cancelled tasks are not retained on active surfaces
- There is no public archive state, archive workflow, or separate archive screen in this MVP
- The standalone UI may display "archive" wording because the destroy path currently returns archived-success copy, but the underlying behavior is still the cancelled/soft-hidden path rather than a separate stored lifecycle state or workflow

## Search and filter boundaries
This MVP intentionally keeps filtering small.

### Supported filters
- status
- due bucket
- context
- assigned-to-me
- project
- title-only text search on the standalone list

### Explicit boundaries
- Title search only matches the task title field
- Notes and description content are not full-text searched
- Issue-linked task endpoints do not expose advanced filtering, title search, or report-style querying
- There are no saved filters, exports, analytics dashboards, bulk operations, or advanced query grammar in this MVP

## User-facing MVP behavior
### What end users can expect
- Use standalone tasks for quick personal capture and lightweight follow-through
- Use issue-linked tasks for small execution items directly on an issue page
- Use the dashboard for a personal view of visible work that is open, due today, overdue, or recently completed
- Promote a task when it needs full Redmica issue workflow

### What changes after promotion
- The new issue becomes the editable record
- The original task stays visible only as a read-only backlink record
- Task Hub shows the promoted issue link and removes normal edit or completion actions for that task
- Promotion cannot be undone in this MVP

### What users should not expect from this MVP
- no public archive screen
- no recurring tasks
- no dependencies
- no comments or journal system inside Task Hub
- no attachment management UI
- no bulk promotion
- no promotion undo
- no cross-project promotion for issue-linked or project-scoped tasks
- no advanced reporting or analytics
- no broad search across notes or issue content

## Runtime and verification limits for this environment
The current shell used for documentation work does not have Ruby, Bundler, or ruby-lsp available. Because of that:
- migrations were reviewed statically, not executed here
- controller, model, and view behavior were documented from repository inspection, not live runtime execution in this shell
- `lsp_diagnostics` is not meaningful for these Markdown docs

Environment-specific rollout caveats:
- representative browser QA for the plugin-loaded app happened against `http://127.0.0.1:4000`, not a stripped-down plugin copy or a different host target
- cross-theme verification completed live with multiple selectable themes, including Bleuclair and Classic
- Task 17 sidebar or navigation refactor work and the earlier Wiki Hub index and search shell corrections are complete, so those items are no longer open blockers in this release note set

Release-readiness expectation:
- run migrations and plugin tests inside the containerized Redmica environment
- verify the top menu entry, `/task_hub`, `/tasks`, issue-page task panel rendering, dashboard or list persistence, and both promotion entry points there
- verify Kanban in the plugin-loaded app on port 4000 as part of normal browser QA, with the current expectation that the runtime restart, cache clear, and scoped asset-loading fixes have already cleared the earlier blocker
- confirm browser asset refresh after restart if styles or issue hook assets appear stale

## Admin release checklist
- plugin files deployed to `/opt/redmica/plugins/redmine_task_hub`
- plugin migrations run successfully in the Redmica runtime environment
- Redmica app or container restarted after deploy
- hard refresh performed if assets looked stale
- top menu `Task Hub` entry visible for expected users
- `/task_hub` dashboard opens and shows bounded sections
- `/tasks` standalone page opens, quick add works, and page-based slicing behaves as expected
- issue detail page shows the Task Hub panel for authorized users
- promotion works only for users with native issue creation permission in the target project
- promoted tasks stay read-only and link back to the created issue

## Compact user note for rollout
Task Hub is a lightweight MVP. Use it for quick standalone tasks, issue child tasks, and personal dashboard review. When a task needs the full Redmica issue workflow, promote it. After promotion, the issue is the live record and the original task becomes a read-only backlink. Completed or cancelled tasks without promotion are intentionally soft-hidden from active views, and advanced reporting or search is not part of this MVP.
