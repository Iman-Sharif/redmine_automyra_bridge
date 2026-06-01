# Wiki Hub Plugin - Improvement Plan

**Review Date:** 2026-04-18  
**Current Version:** 0.1.0  
**Goal:** Transform into a one-stop shop for all wiki pages with powerful, user-friendly UI

---

## Current State Analysis

### Existing Features
✅ Global wiki search with full-text search  
✅ Cross-project linking (@project/page syntax)  
✅ Knowledge graph visualization  
✅ Page categorization (Agreements, Competition, Supplier, Policy, Process, General)  
✅ Page kinds (standard, template, lesson_learned)  
✅ Tagging system  
✅ Template management  
✅ Lessons learned tracking  
✅ Backlinks visualization  
✅ User preferences for homepage integration  
✅ Project-scoped wiki hub  

### Architecture
- **Backend:** Ruby on Rails with PostgreSQL (pg_trgm for search)
- **Frontend:** Standard Redmine views with custom CSS
- **Data Model:** 7 tables for snapshots, profiles, links, tags, etc.
- **API:** JSON endpoints for all major functions

---

## Your Requirements

1. **One-stop shop** - Central hub for ALL wiki activities
2. **Create templates from hub** - Template creation workflow
3. **Create pages from hub** - Direct page creation
4. **Interactive directory by project** - Visual project-based navigation
5. **Powerful & user-friendly UI** - Modern, intuitive interface

---

## Improvement Opportunities

### 1. UI/UX Modernization (HIGH PRIORITY)

**Current:** Standard Redmine table-based views  
**Target:** Modern card-based, responsive dashboard

**Specific Improvements:**
- **Card-based page display** with preview snippets
- **Quick actions** (edit, delete, duplicate) on hover
- **Drag-and-drop** organization for templates
- **Real-time search** with instant results
- **Split-pane view** - list on left, preview on right
- **Dark mode support** (you mentioned preference)
- **Mobile-responsive** design

**Implementation:**
```erb
<!-- New dashboard layout -->
<div class="wiki-hub-dashboard">
  <div class="hub-toolbar">
    <button class="btn-create-page">+ New Page</button>
    <button class="btn-create-template">+ New Template</button>
    <div class="quick-filters">
      <span class="filter-chip active">All</span>
      <span class="filter-chip">Templates</span>
      <span class="filter-chip">Lessons</span>
      <span class="filter-chip">Recent</span>
    </div>
  </div>
  
  <div class="hub-content split-view">
    <div class="page-list cards">
      <!-- Card-based page list -->
    </div>
    <div class="page-preview">
      <!-- Live preview pane -->
    </div>
  </div>
</div>
```

---

### 2. One-Stop Shop Features (HIGH PRIORITY)

**Missing Capabilities:**
- ❌ Direct page creation from hub
- ❌ Quick edit without leaving hub
- ❌ Bulk operations (delete, tag, categorize)
- ❌ Page templates marketplace
- ❌ Import/export functionality

**Implementation Plan:**

#### 2.1 Quick Page Creation
```ruby
# New controller action
class WikiHubController
  def quick_create
    @page = WikiPage.new(
      project_id: params[:project_id],
      title: params[:title],
      content: template_content || default_content
    )
    
    if @page.save
      # Auto-index in wiki_hub
      WikiHub::Indexer.index_page(@page)
      redirect_to wiki_page_path(@page)
    else
      render json: { errors: @page.errors }
    end
  end
end
```

#### 2.2 Template Creation Workflow
```ruby
class WikiHubTemplatesController
  def create_from_hub
    # Convert existing page to template
    source_page = WikiPage.find(params[:source_page_id])
    
    @template = WikiPage.create!(
      project_id: params[:project_id] || source_page.project_id,
      title: "[Template] #{source_page.title}",
      content: source_page.content,
      wiki_page_profile_attributes: {
        page_kind: 'template',
        category: params[:category] || 'General',
        summary: params[:summary]
      }
    )
    
    redirect_to knowledge_hub_templates_path
  end
end
```

#### 2.3 Bulk Operations
```javascript
// Frontend: Bulk action toolbar
const BulkActions = {
  selectedPages: [],
  
  actions: {
    delete: () => { /* confirm and delete */ },
    tag: (tagName) => { /* apply tag */ },
    categorize: (category) => { /* set category */ },
    duplicate: () => { /* clone pages */ },
    export: () => { /* download as zip */ }
  }
}
```

---

### 3. Interactive Project Directory (HIGH PRIORITY)

**Current:** Simple list of projects in sidebar  
**Target:** Visual project explorer with drill-down

**Features:**
- **Project cards** with wiki stats (page count, last updated)
- **Expandable tree view** - projects → wikis → pages
- **Project thumbnails** - preview of wiki content
- **Cross-project search** with project filters
- **Bookmarked projects** - quick access to favorites

**Implementation:**
```erb
<div class="project-directory">
  <div class="project-filters">
    <input type="search" placeholder="Find project..." />
    <select class="sort-by">
      <option>Recently updated</option>
      <option>Most pages</option>
      <option>Alphabetical</option>
    </select>
  </div>
  
  <div class="project-grid">
    <% @projects.each do |project| %>
      <div class="project-card" data-project-id="<%= project.id %>">
        <div class="project-header">
          <h4><%= project.name %></h4>
          <span class="page-count"><%= project.wiki_pages.count %> pages</span>
        </div>
        <div class="project-preview">
          <%= truncate(project.wiki_pages.first&.content, length: 100) %>
        </div>
        <div class="project-actions">
          <%= link_to "View Wiki", project_wiki_hub_path(project) %>
          <%= link_to "New Page", new_project_wiki_page_path(project) %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

---

### 4. Enhanced Search & Discovery (MEDIUM PRIORITY)

**Current:** Basic full-text search  
**Target:** AI-powered, faceted search with recommendations

**Improvements:**
- **Faceted search** - filter by project, category, kind, date, author
- **Saved searches** - bookmark common queries
- **Search suggestions** - autocomplete based on content
- **Related pages** - "You might also like" recommendations
- **Recent activity** - "What's new in your wikis"
- **Trending pages** - most viewed this week

**Implementation:**
```ruby
class WikiHub::SearchQuery
  def call
    base_query
      .then { |q| apply_project_filter(q) }
      .then { |q| apply_category_filter(q) }
      .then { |q| apply_kind_filter(q) }
      .then { |q| apply_date_filter(q) }
      .then { |q| apply_text_search(q) }
      .then { |q| apply_sort(q) }
  end
  
  def suggestions
    # Autocomplete based on titles and tags
    WikiHub::PageSnapshot
      .where("title ILIKE ?", "%#{term}%")
      .limit(5)
      .pluck(:title)
  end
  
  def related_pages(page_id)
    # Find pages with similar tags or links
    source = WikiHub::PageSnapshot.find(page_id)
    
    WikiHub::PageSnapshot
      .where.not(id: page_id)
      .where(category: source.category)
      .or(where_tags_overlap(source.tags))
      .limit(5)
  end
end
```

---

### 5. Template System Enhancement (MEDIUM PRIORITY)

**Current:** Basic template listing  
**Target:** Template marketplace with variables

**Features:**
- **Template variables** - `{{variable_name}}` substitution
- **Template categories** - organized template library
- **Template ratings** - user feedback system
- **Template sharing** - cross-project templates
- **Template preview** - see before using
- **One-click apply** - create page from template instantly

**Implementation:**
```ruby
class WikiHub::TemplateService
  def apply_template(template_id, variables = {})
    template = WikiPage.find(template_id)
    
    content = template.content.gsub(/\{\{(\w+)\}\}/) do |match|
      var_name = $1
      variables[var_name] || "[#{var_name}]"
    end
    
    WikiPage.create!(
      project_id: variables[:project_id],
      title: variables[:title],
      content: content,
      wiki_page_profile_attributes: {
        page_kind: 'standard',
        category: template.wiki_page_profile&.category
      }
    )
  end
end
```

---

### 6. Analytics & Insights (MEDIUM PRIORITY)

**Missing:** Usage analytics and content insights

**Features:**
- **Page view statistics** - most/least viewed pages
- **Search analytics** - what users are looking for
- **Content gaps** - projects without wiki coverage
- **Stale content alerts** - pages not updated in X days
- **Popular links** - most referenced pages
- **Contributor leaderboard** - who's creating content

**Implementation:**
```ruby
class WikiHub::AnalyticsService
  def stale_content(days: 90)
    WikiHub::PageSnapshot
      .where('updated_at < ?', days.days.ago)
      .order(:updated_at)
  end
  
  def content_gaps
    Project.active
      .left_joins(:wiki)
      .where(wikis: { id: nil })
      .or(where(wiki_pages: { id: nil }))
  end
  
  def popular_pages(limit: 10)
    WikiHub::PageSnapshot
      .joins(:page_links_as_target)
      .group(:id)
      .order('COUNT(wiki_hub_page_links.id) DESC')
      .limit(limit)
  end
end
```

---

### 7. Integration Enhancements (LOW PRIORITY)

**Potential Integrations:**
- **Redmine issues** - link wiki pages to issues
- **Calendar** - wiki pages with dates (meetings, deadlines)
- **Notifications** - alert on wiki changes
- **Email digest** - weekly wiki summary
- **Slack/Teams** - notifications on updates
- **Export formats** - PDF, Word, Markdown export

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] UI/UX audit and design mockups
- [ ] Set up modern frontend tooling (Stimulus, Turbo)
- [ ] Create new dashboard layout
- [ ] Implement card-based page display

### Phase 2: Core Features (Week 3-4)
- [ ] Quick page creation from hub
- [ ] Quick template creation workflow
- [ ] Bulk operations (delete, tag, categorize)
- [ ] Interactive project directory

### Phase 3: Search & Discovery (Week 5-6)
- [ ] Enhanced faceted search
- [ ] Search suggestions & autocomplete
- [ ] Related pages recommendations
- [ ] Saved searches

### Phase 4: Templates & Analytics (Week 7-8)
- [ ] Template variables system
- [ ] Template marketplace UI
- [ ] Analytics dashboard
- [ ] Stale content alerts

### Phase 5: Polish & Integration (Week 9-10)
- [ ] Mobile responsiveness
- [ ] Dark mode
- [ ] Performance optimization
- [ ] Integration testing

---

## Technical Considerations

### Frontend Options
1. **Stimulus + Turbo** (Rails native) - Recommended
2. **React/Vue** - More complex, requires API
3. **HTMX** - Lightweight, progressive enhancement

### Database Optimizations
- Add GIN indexes for search performance
- Cache popular queries
- Background job for indexing

### Security
- Ensure permission checks on all actions
- Sanitize user input for XSS prevention
- Rate limiting on search API

---

## Success Metrics

- **User adoption** - % of users accessing wiki via hub
- **Search success** - % of searches finding relevant results
- **Content creation** - new pages created per week
- **Template usage** - templates applied per week
- **User satisfaction** - feedback scores

---

## Next Steps

1. **Review this plan** - confirm priorities and scope
2. **Create design mockups** - wireframes for new UI
3. **Set up development environment** - branch for improvements
4. **Begin Phase 1** - UI foundation work

**Estimated Total Effort:** 8-10 weeks for full implementation
**Priority Features (Quick Wins):**
- Quick page/template creation (1 week)
- Card-based UI (1 week)
- Interactive project directory (1 week)
