# Task Hub MVP UI Surface Map

## Purpose
This document defines the MVP user-facing surfaces for Task Hub so later implementation stays Redmica-native, execution-focused, and lighter than issue tracking. It now reflects the shipped dashboard, list, and bounded Kanban views, plus the minimum copy and state catalog needed to keep those surfaces consistent.

## Redmica-native UI principles
- Use standard Redmica structures and classes first: `contextual`, `box`, `tabular`, `table.list`, `p.nodata`, standard flash classes, and locale-backed labels.
- Follow the host theme instead of introducing plugin branding, custom illustration systems, or bespoke layout language.
- Keep each surface partial-friendly, especially issue-page integrations, so the plugin fits existing Redmica page structure instead of replacing it.
- Prefer lightweight badges/chips for state and due cues; do not create dense issue-style meta panels.
- Copy should stay short and execution-focused: create, do, complete, reopen, cancel, promote.
- Mobile behavior must be first-class, not a desktop-only surface squeezed later.

## MVP surfaces

### Shared view-selector and persistence contract
- `/task_hub` now hosts three user-selectable views: `dashboard`, `list`, and `kanban`.
- The selected view persists per user through `UserPreference.others[:task_hub]`.
- List filters persist alongside the selected view so the user returns to the same bounded worklist state on the next visit.
- The allowed persisted filter vocabulary stays intentionally small: status, due bucket, context, assigned-to-me, project, and title search.
- Persistence is per user preference state, not a shared team board setting and not a saved-filter framework.

### 1. Standalone quick capture + lightweight list
**Primary goal**
- Let the current user capture and work through lightweight tasks faster than creating an issue.

**Placement / page role**
- Main Task Hub entry surface available from the site-level Task Hub navigation.
- Serves as the fastest owner-centric entry point for standalone tasks.

**Primary regions**
1. **Contextual header**
   - Page title: `Task Hub`
   - Optional lightweight filter/actions area in a standard `contextual` block.
2. **Quick capture box**
   - A compact `box tabular` area at the top of the page.
   - Default interaction is title-first creation.
   - Optional secondary fields may be progressively disclosed later in implementation, but must not block title-only create.
3. **Task list**
   - Lightweight task rows beneath capture.
   - Prefer simple stacked rows or a light `table.list`; avoid issue-index density.
   - Each row should support quick scan of title, state, due cue, assignee if present, project context if present, and lightweight actions.
4. **Nodata / filtered-empty area**
   - `p.nodata` style treatment for zero-state and filter-empty states.

**Row content expectations**
- Title is visually primary.
- State chip/badge is visible but small.
- Due label is secondary but prominent when due today or overdue.
- Project label, if present, is contextual only; it does not imply team sharing.
- Promoted tasks appear read-only and visually de-emphasized versus active tasks.

**Allowed primary actions**
- Add task
- Edit lightweight fields
- Mark in progress
- Mark done
- Cancel
- Reopen when allowed
- Promote to issue when allowed by later flow

**Not implied by this surface**
- No kanban columns
- No recurrence controls
- No dependency controls
- No reporting widgets
- No issue-form clone

**Responsive expectations**
- **Desktop**
  - Quick capture stays above the list.
  - Filters/actions can sit in the `contextual` area or alongside the header.
  - Rows may use 2-3 visual zones: title/state, due/context, actions.
- **Tablet**
  - Reduce row density; actions may collapse to a trailing action group.
  - Keep quick capture full-width and easy to submit in one pass.
- **Mobile**
  - Stack quick capture controls vertically.
  - Each task row becomes a vertical card-like row or stacked list item.
  - Avoid horizontal overflow; due/state/context should wrap beneath title.
  - Keep completion and edit actions tappable without opening a heavy modal flow.

### 2. Issue child-task panel
**Primary goal**
- Show and manage lightweight execution tasks directly inside an issue page without redefining the issue page itself.

**Placement / integration role**
- Inserted through issue-page hooks as a partial-friendly panel.
- Lives within the existing issue page flow, likely near details/planning content.
- Must feel like a native issue sub-panel, not a separate embedded app.

**Primary regions**
1. **Panel header**
   - Title: `Tasks`
   - Optional summary count such as open/completed counts, if implementation remains lightweight.
2. **Quick add row**
   - Compact title-first input within the panel.
   - Same lightweight create expectation as standalone capture.
3. **Issue task list**
   - Shows only this issue’s child tasks.
   - Supports sibling ordering semantics later, but the UI spec should remain simple and panel-sized.
4. **Panel nodata / denied state**
   - Standard `p.nodata` or `render_403` style outcome depending on access path.

**Panel behavior expectations**
- This is a scoped issue companion, not a full task workspace.
- Show issue-linked tasks only; do not blend in unrelated standalone tasks.
- Keep controls concise so the issue page remains readable.
- Panel must be renderable as a reusable partial without assuming control of the entire page layout.

**Allowed primary actions**
- Add issue-linked task
- Change lightweight state
- Edit lightweight fields
- Reorder issue-linked siblings when later implementation enables it
- Promote task to issue when allowed

**Responsive expectations**
- **Desktop**
  - Panel sits naturally within issue page content width.
  - Actions may appear inline per row if space allows.
- **Tablet**
  - Maintain panel within the issue flow; reduce metadata shown per row before wrapping the entire panel.
- **Mobile**
  - Panel stacks below surrounding issue content.
  - Quick add and row actions must fit narrow width without horizontal scrolling.
  - Reordering affordances, when implemented, should degrade to simple tap targets or secondary action access instead of drag-heavy assumptions.

### 3. Owner-centric dashboard
**Primary goal**
- Give the current user a fast execution view across visible tasks: what is open, due today, overdue, and recently completed.

**Placement / page role**
- Dashboard is a personal execution surface, not a team operations board.
- It may share the Task Hub page context or act as the primary grouped view under Task Hub navigation.

**Primary regions**
1. **Header / contextual controls**
   - Title options should stay plain and native, e.g. `My Tasks` or `Task Hub` with personal sections beneath.
   - Filters stay limited to MVP scope.
2. **Execution sections**
   - `My Open Tasks`
   - `Due Today`
   - `Overdue`
   - `Recently Completed`
3. **Optional grouping blocks**
   - By issue
   - By project
   - Only for tasks already visible to the current user
4. **Nodata / filter-empty states**
   - Standard `p.nodata` usage per section or per page.

**Dashboard behavior expectations**
- Personal, owner-centric, and execution-oriented.
- Grouping is for scanability, not analytics.
- Keep filters intentionally small: status, due bucket, assigned-to-me, standalone vs issue-linked, project, title search.
- Avoid turning the page into a report builder or team planning board.

**Section presentation expectations**
- `Overdue` should visually read as the highest urgency section.
- `Due Today` should be distinct from general open work.
- `Recently Completed` should be present but visually lighter than active sections.
- Empty sections may collapse to a short `p.nodata` line if the rest of the dashboard still has content.

**Responsive expectations**
- **Desktop**
  - May use a sidebar + main-content or multi-section stacked layout, following native Redmica page widths.
  - Grouped sections should remain readable without dashboard-card branding.
- **Tablet**
  - Reduce side-by-side layout to fewer columns or a single dominant column with filter controls above content.
- **Mobile**
  - Use a single stacked column.
  - Filters/actions should collapse cleanly without introducing horizontal tables.
  - Section headings remain visible; each section should be scannable with short rows and wrapped metadata.

### 4. Kanban board
**Primary goal**
- Give the current user a quick status-board view over the same personal Task Hub workload without turning Task Hub into a full planning suite.

**Placement / page role**
- Lives under `/task_hub` as the third view-selector option next to dashboard and list.
- Uses the same owner-centric scope as the other Task Hub views.

**Primary regions**
1. **Header / contextual controls**
   - Reuse the standard Task Hub page title and native view selector.
   - Keep any supporting copy short and native.
2. **Board columns**
   - Four fixed columns mapped to `TaskHub::Task::STATUSES`.
   - Columns are status buckets, not configurable lanes.
3. **Task cards**
   - Lightweight cards showing title first, with small due or context cues where needed.
   - Cards stay structurally native and rely on host styling first.
4. **Empty column states**
   - Use simple `p.nodata` style messaging within empty columns.

**Board behavior expectations**
- Kanban is a personal execution board, not a team planning board.
- Drag and drop is limited to lightweight status transitions through existing move endpoints.
- No custom board designer, lane configuration, WIP policy, analytics layer, or saved board views.
- Live browser verification on the plugin-loaded app at `http://127.0.0.1:4000` passed after the runtime restart, cache clear, and scoped asset-loading fixes, so Kanban acceptance is no longer blocked in this environment.

**Responsive expectations**
- **Desktop**
  - Four status columns may sit side by side when space allows.
- **Tablet**
  - Columns may compress, but the board should still read as ordered status buckets.
- **Mobile**
  - Columns may stack vertically; avoid forcing horizontal overflow as the only usable interaction.

## State and copy catalog
All copy should be locale-backed in implementation. The text below defines intent and baseline wording, not hardcoded strings.

| State / moment | Baseline copy intent | Presentation guidance |
| --- | --- | --- |
| Empty / no tasks | `No tasks yet.` | Use `p.nodata`. Keep it calm and minimal. |
| First-task CTA | `Add your first task` | Pair with empty state as the primary CTA when the user has no tasks in the current surface. |
| Permission denied | `You do not have permission to view these tasks.` | Use standard forbidden treatment; no custom branded error surface. |
| Overdue | `Overdue` | Use a clear urgency cue via badge/chip/text treatment. Due date should remain visible. |
| Due today | `Due today` | Distinct from overdue but still high-visibility. |
| Completed | `Completed` or `Done` | De-emphasize visually compared with open work; keep readable in recent history. |
| Cancelled | `Cancelled` | Secondary/de-emphasized state; should not look actionable until reopened. |
| Promoted / read-only | `Promoted to issue` and `Read only` | Make terminal/read-only status explicit so users do not expect inline edits. Link/back-reference can be shown later in implementation. |
| No results / filter empty | `No tasks match the current filters.` | Use `p.nodata` in filtered result areas; distinguish from first-use empty state. |

### State-specific notes
- **Empty / no tasks**
  - Applies when the surface has no records in scope.
  - Standalone and dashboard surfaces should optionally show a first-use CTA nearby.
- **First-task CTA**
  - Only shown for true first-use or empty-in-scope moments where create is allowed.
  - Keep CTA text lightweight; do not pitch project-management benefits.
- **Permission denied**
  - Use standard Redmica permission behavior.
  - For hidden resources, later implementation may render 404 instead of displaying this copy.
- **Overdue / due today**
  - These cues should appear inline with the task row and in dashboard grouping where applicable.
  - Overdue must outrank due today visually.
- **Completed / cancelled**
  - Keep available for scan and filtering but visually quieter than active work.
- **Promoted / read-only**
  - Must clearly communicate that the task is no longer editable through normal task actions.
- **No results / filter empty**
  - Separate this from a true empty workspace so the user understands tasks may exist outside the active filter.

## Surface-by-surface state application

### Standalone quick capture + list
- Empty state: `No tasks yet.` + `Add your first task`
- Filter-empty state: `No tasks match the current filters.`
- Permission denied: generally not a list-page state for the owner, but use standard deny behavior for unauthorized direct-resource actions.
- Overdue / due today: inline badge/text near due date.
- Completed / cancelled: visible but visually reduced.
- Promoted / read-only: show explicit read-only state in-row.

### Issue child-task panel
- Empty state: `No tasks yet.` within the panel.
- First-task CTA: compact quick-add affordance in the panel header/body.
- Permission denied: standard deny behavior if the issue/task scope is not visible.
- Overdue / due today: compact inline emphasis.
- Completed / cancelled: retain in the panel if included by the active view, but keep secondary.
- Promoted / read-only: visible in-row with no editable affordances.

### Owner-centric dashboard
- Empty state: `No tasks yet.` when the user has no visible tasks in dashboard scope.
- Section empty state: short `p.nodata` copy per section, e.g. no overdue tasks today.
- Filter-empty state: `No tasks match the current filters.`
- Permission denied: not a normal dashboard state; use standard access denial only when the page itself is not accessible.
- Overdue / due today: may be shown both as grouped sections and inline row status cues.
- Completed / cancelled: usually concentrated in recently completed or filtered historical slices.
- Promoted / read-only: shown as terminal items when included in a visible slice, without editable controls.

## Filters and controls scope
The UI may expose only MVP filter/control scope:
- status
- due bucket
- assigned to me
- standalone vs issue-linked
- project
- title search

The spec does **not** imply saved filters, advanced query grammar, exports, analytics panels, or multi-column sort builders.

## Out-of-scope guardrails
This document intentionally does **not** define or imply:
- recurring task screens
- task dependencies
- analytics or reporting dashboards
- configurable team boards, swimlanes, or planning overlays beyond the bounded personal Kanban view
- admin dashboards
- Gantt/planner/timeline views
- issue-style journal/comment systems
- attachment management UI
- custom theme or branding systems
- task nesting or checklist-of-checklists UI
- cross-project promotion flows
- heavyweight modal workflows for basic task actions

## Implementation guidance summary
- Build each surface from native Redmica partials and page structures.
- Favor compact forms and lightweight row actions over issue-form complexity.
- Treat standalone, issue-linked, and dashboard surfaces as related but distinct contexts.
- Keep copy locale-backed, short, and action-oriented.
- Keep promoted/read-only and permission-denied behavior explicit.
- Keep mobile layouts stacked and tap-friendly.
- If a proposed UI element makes Task Hub feel like a second issue tracker, it is out of MVP scope.
