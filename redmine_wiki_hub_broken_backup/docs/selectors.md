# Wiki Hub Data Test ID Selectors

This document lists all `data-testid` selectors used in the Redmine Wiki Hub plugin. These selectors are used for automated testing and DOM identification.

## Selector Naming Convention

All data-testid selectors in Wiki Hub follow these conventions:

1. **Prefix:** All selectors start with `wiki-hub-` to namespace them
2. **Format:** Lowercase with hyphens (`kebab-case`)
3. **Structure:** `wiki-hub-{component}-{element}`

## Implemented Selectors

### Hub Landing Page (`app/views/wiki_hub/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-page` | `<div>` | Main page container |
| `wiki-hub-toolbar` | `<nav>` | Top toolbar with actions |
| `wiki-hub-sidebar` | `<div>` | Sidebar container |
| `wiki-hub-navigation` | `<div>` | Navigation section in sidebar |
| `wiki-hub-nav-all` | `<li>` | "All Pages" navigation link |
| `wiki-hub-nav-templates` | `<li>` | "Templates" navigation link |
| `wiki-hub-nav-lessons` | `<li>` | "Lessons" navigation link |
| `wiki-hub-nav-graph` | `<li>` | "Graph" navigation link |
| `wiki-hub-nav-backlinks` | `<li>` | "Backlinks" navigation link |
| `wiki-hub-nav-admin` | `<li>` | "Admin" navigation link |
| `wiki-hub-project-groups` | `<div>` | Project groups section |
| `wiki-hub-project-tree` | `<div>` | Project tree container |
| `wiki-hub-project-item` | `<div>` | Individual project item (has `data-project-id`) |
| `wiki-hub-project-toggle` | `<button>` | Project expand/collapse toggle |
| `wiki-hub-project-content` | `<div>` | Expandable project content |
| `wiki-hub-project-cards` | `<div>` | Project cards container |
| `wiki-hub-project-card` | `<div>` | Individual project card (has `data-project-id`) |
| `wiki-hub-more-projects` | `<p>` | "More projects" indicator |
| `wiki-hub-no-projects` | `<p>` | Empty state for no projects |
| `wiki-hub-recent-changes` | `<div>` | Recent changes section |
| `wiki-hub-recent-list` | `<ul>` | Recent changes list |
| `wiki-hub-recent-change` | `<li>` | Individual recent change item (has `data-page-id`) |
| `wiki-hub-no-recent` | `<p>` | Empty state for no recent changes |
| `wiki-hub-main` | `<div>` | Main content area |
| `wiki-hub-title` | `<h1>` | Main page title |
| `wiki-hub-search` | `<div>` | Search input container |
| `wiki-hub-filters` | `<div>` | Filters panel |
| `wiki-hub-bulk-toolbar` | `<div>` | Bulk operations toolbar |
| `wiki-hub-content` | `<div>` | Content area |
| `wiki-hub-pages-grid` | `<div>` | Pages grid container |
| `wiki-hub-page-card` | `<article>` | Individual page card (has `data-page-id`) |
| `wiki-hub-page-title` | `<h3>` | Page title heading |
| `wiki-hub-page-kind` | `<span>` | Page kind badge |
| `wiki-hub-page-category` | `<span>` | Page category badge |
| `wiki-hub-page-summary` | `<p>` | Page summary text |
| `wiki-hub-page-project` | `<span>` | Project name |
| `wiki-hub-page-date` | `<span>` | Page date |
| `wiki-hub-empty` | `<div>` | Empty state for no pages |

### Quick Create (`app/views/wiki_hub/quick_create_form.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-quick-create` | `<div>` | Quick create page container |
| `wiki-hub-quick-create-form` | `<form>` | Quick create form |
| `wiki-hub-quick-create-project` | `<select>` | Project selection dropdown |
| `wiki-hub-quick-create-title` | `<input>` | Page title input |
| `wiki-hub-quick-create-template` | `<select>` | Template selection dropdown |
| `wiki-hub-quick-create-submit` | `<input>` | Submit button |

### Templates Listing (`app/views/wiki_hub_templates/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-templates-page` | `<div>` | Templates page container |
| `wiki-hub-templates-title` | `<h2>` | Templates page title |
| `wiki-hub-templates-description` | `<p>` | Templates description |
| `wiki-hub-template-analytics` | `<div>` | Template analytics dashboard |
| `wiki-hub-templates-list` | `<div>` | Templates grid container |
| `wiki-hub-template-card` | `<article>` | Individual template card (has `data-template-id`) |
| `wiki-hub-template-title` | `<h3>` | Template title |
| `wiki-hub-template-project` | `<span>` | Template project |
| `wiki-hub-template-summary` | `<p>` | Template summary |
| `wiki-hub-template-date` | `<span>` | Template date |
| `wiki-hub-templates-empty` | `<div>` | Empty state for no templates |

### Template Detail (`app/views/wiki_hub_templates/show.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-template-detail` | `<div>` | Template detail container |
| `wiki-hub-template-detail-title` | `<h2>` | Template detail title |

### Use Template (`app/views/wiki_hub_templates/use_form.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-use-template` | `<div>` | Use template page container |
| `wiki-hub-use-template-form` | `<form>` | Use template form |
| `wiki-hub-use-template-project` | `<select>` | Target project selection |
| `wiki-hub-use-template-title` | `<input>` | Page title input |
| `wiki-hub-use-template-submit` | `<input>` | Submit button |
| `wiki-hub-template-preview` | `<div>` | Template preview section |

### Create Template from Hub (`app/views/wiki_hub_templates/create_from_hub_form.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-create-template` | `<div>` | Create template form container |

### Lessons (`app/views/wiki_hub_lessons/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-lessons-page` | `<div>` | Lessons page container |
| `wiki-hub-lessons-title` | `<h2>` | Lessons page title |
| `wiki-hub-lessons-description` | `<p>` | Lessons description |
| `wiki-hub-lessons-list` | `<div>` | Lessons timeline container |
| `wiki-hub-lessons-month` | `<div>` | Month separator in timeline |
| `wiki-hub-lesson-card` | `<article>` | Individual lesson card (has `data-lesson-id`) |
| `wiki-hub-lesson-date` | `<span>` | Lesson date |
| `wiki-hub-lesson-title` | `<h4>` | Lesson title |
| `wiki-hub-lesson-summary` | `<p>` | Lesson summary |
| `wiki-hub-lesson-project` | `<span>` | Lesson project |
| `wiki-hub-lesson-updated` | `<span>` | Lesson last updated |
| `wiki-hub-lessons-empty` | `<div>` | Empty state for no lessons |

### Graph Visualization (`app/views/wiki_hub_graph/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-graph-page` | `<div>` | Graph page container |
| `wiki-hub-graph-title` | `<h2>` | Graph page title |
| `wiki-hub-graph-description` | `<p>` | Graph description |
| `wiki-hub-graph-controls` | `<div>` | Graph controls panel |
| `wiki-hub-graph-root-input` | `<input>` | Root page input field |
| `wiki-hub-graph-load-button` | `<button>` | Load graph button |
| `wiki-hub-graph-zoom-in` | `<button>` | Zoom in button |
| `wiki-hub-graph-zoom-out` | `<button>` | Zoom out button |
| `wiki-hub-graph-reset` | `<button>` | Reset view button |
| `wiki-hub-graph-container` | `<div>` | Graph canvas container |
| `wiki-hub-graph-canvas` | `<canvas>` | Graph visualization canvas |
| `wiki-hub-graph-tooltip` | `<div>` | Graph node tooltip |
| `wiki-hub-graph-legend` | `<div>` | Graph legend |
| `wiki-hub-graph-stats` | `<div>` | Graph statistics panel |
| `wiki-hub-graph-node-count` | `<span>` | Node count display |
| `wiki-hub-graph-edge-count` | `<span>` | Edge count display |

### Backlinks (`app/views/wiki_hub_backlinks/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-backlinks-page` | `<div>` | Backlinks page container |
| `wiki-hub-backlinks-title` | `<h2>` | Backlinks page title |
| `wiki-hub-backlinks-target` | `<p>` | Target page info |
| `wiki-hub-backlinks-list` | `<ul>` | Backlinks list |
| `wiki-hub-backlink-row-{id}` | `<li>` | Individual backlink row (dynamic ID) |
| `wiki-hub-backlinks-empty` | `<p>` | Empty state for no backlinks |
| `wiki-hub-backlinks-select-page` | `<p>` | Prompt to select a page |

### Metadata (`app/views/wiki_hub_metadata/show.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-metadata-page` | `<div>` | Metadata page container |
| `wiki-hub-metadata-title` | `<h2>` | Metadata page title |
| `wiki-hub-metadata-form` | `<div>` | Metadata edit form |
| `wiki-hub-metadata-category-label` | `<label>` | Category field label |
| `wiki-hub-metadata-page-kind-label` | `<label>` | Page kind field label |
| `wiki-hub-metadata-lesson-date-label` | `<label>` | Lesson date field label |
| `wiki-hub-metadata-tags-label` | `<label>` | Tags field label |
| `wiki-hub-metadata-summary-label` | `<label>` | Summary field label |
| `wiki-hub-metadata-featured-label` | `<label>` | Featured field label |
| `wiki-hub-metadata-current` | `<div>` | Current metadata display |
| `wiki-hub-current-category` | `<dd>` | Current category value |
| `wiki-hub-current-page-kind` | `<dd>` | Current page kind value |
| `wiki-hub-current-lesson-date` | `<dd>` | Current lesson date value |
| `wiki-hub-current-tags` | `<dd>` | Current tags list |
| `wiki-hub-tag-{name}` | `<span>` | Individual tag (dynamic name) |
| `wiki-hub-current-summary` | `<dd>` | Current summary value |
| `wiki-hub-current-featured` | `<dd>` | Current featured status |

### Homepage Settings (`app/views/wiki_hub_homepage/show.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-homepage-page` | `<div>` | Homepage settings container |
| `wiki-hub-homepage-title` | `<h2>` | Homepage settings title |
| `wiki-hub-homepage-description` | `<p>` | Homepage description |
| `wiki-hub-homepage-settings` | `<div>` | Settings form section |
| `wiki-hub-homepage-enabled-label` | `<label>` | Enabled checkbox label |
| `wiki-hub-homepage-status` | `<div>` | Status display section |
| `wiki-hub-homepage-status-text` | `<p>` | Status text |

### Admin (`app/views/wiki_hub_admin/index.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-admin-page` | `<div>` | Admin page container |
| `wiki-hub-admin-title` | `<h2>` | Admin page title |
| `wiki-hub-admin-health` | `<section>` | Health check section |
| `wiki-hub-health-status` | `<span>` | Health status indicator |
| `wiki-hub-health-details` | `<dl>` | Health details list |
| `wiki-hub-health-{key}` | `<dd>` | Individual health metric (dynamic key) |
| `wiki-hub-admin-stats` | `<section>` | Statistics section |
| `wiki-hub-admin-snapshots` | `<dd>` | Page snapshots count |
| `wiki-hub-admin-links` | `<dd>` | Page links count |
| `wiki-hub-admin-orphans` | `<dd>` | Orphan pages count |
| `wiki-hub-admin-rebuild` | `<section>` | Rebuild index section |
| `wiki-hub-admin-index-runs` | `<section>` | Index runs history section |
| `wiki-hub-index-run-{id}` | `<tr>` | Individual index run row (dynamic ID) |
| `wiki-hub-admin-no-index-runs` | `<p>` | Empty state for no index runs |

### Search (`app/views/wiki_hub/search.html.erb`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-search-page` | `<div>` | Search page container |
| `wiki-hub-search-title` | `<h2>` | Search page title |
| `wiki-hub-search-facets` | `<div>` | Search facets/filters panel |
| `wiki-hub-search-form-container` | `<div>` | Search form container |
| `wiki-hub-search-info` | `<div>` | Search info bar |
| `wiki-hub-search-count` | `<span>` | Results count |
| `wiki-hub-search-results` | `<div>` | Search results container |
| `wiki-hub-search-list` | `<ul>` | Search results list |
| `wiki-hub-search-result` | `<li>` | Individual search result (has `data-page-id`) |
| `wiki-hub-search-result-title` | `<h3>` | Result title |
| `wiki-hub-search-result-project` | `<span>` | Result project |
| `wiki-hub-search-result-meta` | `<div>` | Result metadata |
| `wiki-hub-search-result-date` | `<span>` | Result date |
| `wiki-hub-search-result-excerpt` | `<div>` | Result excerpt |
| `wiki-hub-search-empty` | `<div>` | Empty state for no results |
| `wiki-hub-search-prompt` | `<div>` | Initial search prompt |

### JavaScript Generated (from `wiki_hub_bulk.js`)

| Selector | Element | Purpose |
|----------|---------|---------|
| `wiki-hub-search-suggestions` | `<div>` | Search autocomplete suggestions (dynamically created) |

## Testing with Selectors

### Playwright Example

```javascript
// Verify page loaded
await page.waitForSelector('[data-testid="wiki-hub-title"]');

// Get element text
const title = await page.textContent('[data-testid="wiki-hub-title"]');
expect(title).toBe('Wiki Hub');

// Click a navigation link
await page.click('[data-testid="wiki-hub-nav-templates"]');

// Wait for dynamic content
await page.waitForSelector('[data-testid="wiki-hub-template-card"]');
```

### Capybara Example

```ruby
# Check element exists
expect(page).to have_css("[data-testid='wiki-hub-title']")

# Click within element
find("[data-testid='wiki-hub-nav-graph']").click

# Find dynamic rows
find("[data-testid='wiki-hub-backlink-row-123']")
```

### Selenium Example

```python
# Find element by attribute
title = driver.find_element(By.CSS_SELECTOR, "[data-testid='wiki-hub-title']")
assert title.text == "Wiki Hub"

# Wait for dynamic elements
WebDriverWait(driver, 10).until(
    EC.presence_of_element_located((By.CSS_SELECTOR, "[data-testid='wiki-hub-search-suggestions']"))
)
```

## Maintenance Notes

When modifying selectors:

1. **Never remove selectors** without checking test dependencies
2. **Update this document** when adding new selectors
3. **Use semantic names** that describe the element's purpose
4. **Keep selectors stable** to avoid breaking tests
5. **Document breaking changes** in release notes

## Generating This Document

To verify selectors in the canonical codebase:

```bash
cd /opt/redmica/plugins/redmine_wiki_hub
grep -r "data-testid" --include="*.erb" --include="*.js" --include="*.html" --include="*.css" . | sort
```

Last updated: April 19, 2026
