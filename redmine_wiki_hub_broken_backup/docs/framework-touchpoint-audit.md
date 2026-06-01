# Wiki Hub Framework / Host Touchpoint Audit

Last updated: 2026-04-19

## Purpose

This audit inventories every known framework- and Redmine-touching behavior in the canonical plugin at `/opt/redmica/plugins/redmine_wiki_hub`, classifies upgrade risk, and assigns the intended downstream remediation owner task. It reflects the current post-route-unification codebase and is the source of truth for follow-on work in Tasks 4/5/7/8.

## Classification legend

| Classification | Meaning |
|---|---|
| supported Redmine plugin API | Expected plugin integration point that should remain in place |
| tolerated isolated patch | Works today but depends on host/framework internals; keep only with isolation and targeted coverage |
| unsafe/deprecated usage | High-upgrade-risk pattern; replace or contain before relying on Redmine/Rails internals changing |

## Audit summary

| Area | Touchpoint | Files | Classification | Action | Downstream owner |
|---|---|---|---|---|---|
| init | `Redmine::Plugin.register`, exact `requires_redmine`, top-menu entry | `init.rb:7-23` | supported Redmine plugin API | keep as supported pattern while README/runbooks carry the pinned Redmica-first matrix | none |
| init / reload | `Rails.configuration.to_prepare` wrapper installs the lifecycle bridge | `init.rb:23-27` | tolerated isolated patch | keep isolated and covered while rename/destroy still need host bridging | Task 4 |
| routes | static plugin routes file | `config/routes.rb:1-20` | supported Redmine plugin API | keep as supported pattern | none |
| hooks | `Redmine::Hook::Listener` wiki save callbacks | `lib/wiki_hub/hooks.rb:2-54` | supported Redmine plugin API | keep as supported pattern with log-only failure handling | none |
| host controller bridge | `WikiController.prepend(WikiHub::WikiControllerLifecycleBridge)` | `lib/wiki_hub/hooks.rb:4-54` | tolerated isolated patch | keep temporarily but isolate/test | Task 4 |
| controller cache | `Rails.cache.fetch` user-scoped collections in request flow | `app/controllers/wiki_hub_controller.rb:8-23` | tolerated isolated patch | keep temporarily but isolate/test | Task 7 |
| controller cache headers | `Cache-Control: private, max-age=300` on authenticated hub responses | `app/controllers/wiki_hub_controller.rb:238-241` | tolerated isolated patch | keep private semantics and continue validating cache safety | Task 7 |
| permissions | centralized permission service using `allowed_to?` | `app/services/wiki_hub/permission_filter.rb:9-34` | supported Redmine plugin API | keep as supported pattern | none |
| permissions | direct controller `allowed_to?` checks outside service | `app/controllers/wiki_hub_controller.rb:41-44,69-82`; `app/controllers/wiki_hub_metadata_controller.rb:6-15`; `app/controllers/wiki_hub_templates_controller.rb:27-30,70-76,103-116,174-181` | tolerated isolated patch | keep temporarily but isolate/test | Task 7 |
| migrations | versioned plugin migrations generally | `db/migrate/*.rb` | supported Redmine plugin API | keep as supported pattern | none |
| db extension enablement | `enable_extension 'pg_trgm'` and GIN trigram indexes | `db/migrate/008_enable_pg_trgm.rb:6-29` | tolerated isolated patch | keep temporarily but isolate/test | Task 5 |
| health | extension/tables/index-run health checks | `lib/wiki_hub/healthcheck.rb:12-53` | supported Redmine plugin API | keep as supported pattern | none |

## Detailed inventory

### 1. Init and boot-time integration

#### Supported

- `Redmine::Plugin.register :redmine_wiki_hub` and the now-exact `requires_redmine version: '6.0'` in `init.rb:7-23` are normal plugin entry points.
- The exact Redmine version metadata is intentionally narrower than the broader `version_or_higher` form so the plugin entry point does not overstate support beyond the pinned Redmica-first matrix documented in the README and runbooks.
- The top-menu registration in `init.rb:17-20` is a standard Redmine menu touchpoint.

#### Risk items

| Touchpoint | Evidence | Why it matters | Decision | Owner |
|---|---|---|---|---|
| `Rails.configuration.to_prepare` | `init.rb:23-27` | `to_prepare` is a valid Rails reload hook. In the current implementation it is limited to idempotent lifecycle-bridge installation, so the remaining risk is host controller coupling rather than route mutation or Journey introspection. | keep temporarily but isolate/test | Task 4 |

### 2. Routes

#### Supported

- `config/routes.rb:1-32` is now the canonical supported route registration mechanism for the plugin and the only route source.
- The current static route file covers the landing/search/index/admin/homepage routes plus formerly runtime-added endpoints such as search suggestions, related pages, quick create, bulk action, templates, lessons, graph, and backlinks.

#### Current state

`init.rb` no longer appends routes at runtime, and no duplicate route source remains. The prior `routes.append`/route-introspection/Journey workaround path has been removed from the implementation and should be treated as historical, not current behavior.

**Decision:** keep static route declarations as the single supported route mechanism.

### 3. Framework monkey patches

#### Current state

No current `Journey` monkey patch remains in `init.rb`. This audit retains the topic only to document that the previous `ActionDispatch::Journey::*#to_str` workaround was an upgrade hazard and has already been removed with route unification.

**Decision:** keep this area closed by preventing any reintroduction of framework monkey patches.

### 4. Hooks and host controller patching

#### Supported

- `WikiHub::Hooks < Redmine::Hook::Listener` in `lib/wiki_hub/hooks.rb:1-54` is a supported Redmine extension point.
- `controller_wiki_edit_after_save` and `controller_wiki_edit_post` are appropriate listener callbacks for post-save index refresh.
- Save/rename/destroy failures are now logged with action, operation, page_id, error class, and error message, and they degrade safely instead of surfacing a user-facing exception.

#### Tolerated isolated patch

`WikiHub::Hooks.install_lifecycle_bridge!` in `lib/wiki_hub/hooks.rb:4-11` prepends `WikiHub::WikiControllerLifecycleBridge` into `WikiController`, and the bridge overrides `rename` and `destroy` in `lib/wiki_hub/hooks.rb:56-80`.

Why it is brittle:

- depends on host controller method names remaining `rename` and `destroy`
- depends on Redmine continuing to expose `@page`
- runs through `to_prepare`, so correctness is tied to reload timing

What is still good:

- the prepend is guarded for idempotence (`return if WikiController < WikiHub::WikiControllerLifecycleBridge`, `hooks.rb:19`)
- the bridge is narrowly scoped to index cleanup side effects

**Decision:** keep temporarily but isolate/test in Task 4. Preferred direction is still to replace or narrow this bridge to a supported host callback/event if one can cover rename/destroy semantics; until then the prepend stays encapsulated, log-only on failure, and directly covered by focused lifecycle tests.

### 5. Controllers and cache behavior

#### Supported controller integration

- Standard Rails/Redmine callbacks are used throughout controllers: `before_action`, `require_login`, `respond_to`, `render_403`, `render_404`, `rescue_from` (`app/controllers/wiki_hub_controller.rb:2-6`; `app/controllers/wiki_hub_metadata_controller.rb:1-5`; `app/controllers/wiki_hub_templates_controller.rb:1-5`). These are not themselves upgrade hotspots.

#### Tolerated isolated patch: request-flow caching

`app/controllers/wiki_hub_controller.rb:10-17` caches user-scoped project and recent-page collections with:

- `Rails.cache.fetch("wiki_hub/projects/#{User.current.id}", expires_in: 10.minutes)`
- `Rails.cache.fetch("wiki_hub/recent/#{User.current.id}", expires_in: 5.minutes)`

Risk notes:

- `Rails.cache.fetch` is supported Rails API, but cache invalidation is implicit; page permission changes, membership changes, and wiki writes may leave stale results until expiry.
- `set_cache_headers` now marks hub responses `private, max-age=300` in `app/controllers/wiki_hub_controller.rb:238-241`, which is materially safer for authenticated, user-filtered pages, but invalidation and downstream cache behavior still deserve containment review.

Current test support is indirect only; the referenced integration tests exercise route resolution and indexing, not cache invalidation behavior.

**Decision:** keep temporarily but isolate/test in Task 7. Task 7 should validate that current private cache semantics and invalidation behavior remain safe for all delivery layers.

### 6. Permission touchpoints

#### Supported

- `WikiHub::PermissionFilter` centralizes permission evaluation in `app/services/wiki_hub/permission_filter.rb:9-16` and delegates to Redmine's supported `user.allowed_to?` API.
- This service is the preferred touchpoint because it localizes project resolution rules (`permission_filter.rb:21-33`).

#### Tolerated isolated patch

Direct `User.current.allowed_to?` checks still exist in controllers:

- bulk delete/edit checks in `app/controllers/wiki_hub_controller.rb:41-44,69-82`
- metadata access in `app/controllers/wiki_hub_metadata_controller.rb:7,14`
- template flows in `app/controllers/wiki_hub_templates_controller.rb:29,75,104,116,181`

These are still supported Redmine permission APIs, but the scattered pattern increases drift risk versus the centralized service and makes cache/authorization coupling harder to reason about.

**Decision:** keep temporarily but isolate/test in Task 7, with a likely follow-up normalization toward `PermissionFilter` or a peer service for controller-specific authorization.

### 7. Migrations and database compatibility

#### Supported

- Versioned plugin migrations are a standard Redmine plugin mechanism.
- The plugin health path checks extension presence with `ActiveRecord::Base.connection.extension_enabled?('pg_trgm')` in `lib/wiki_hub/healthcheck.rb:45-47`; that is a straightforward, supported adapter capability query.

#### Tolerated isolated patch

`db/migrate/008_enable_pg_trgm.rb:6-29` uses supported ActiveRecord migration helpers:

- `enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')`
- Postgres-specific GIN trigram indexes on `wiki_hub_page_snapshots.title` and `wiki_hub_page_links.target_title`
- rollback removes only plugin-owned trigram indexes and does **not** disable the shared `pg_trgm` extension

Why it is a compatibility hotspot:

- it hard-codes PostgreSQL-specific index features
- plugin install/CI on non-PostgreSQL adapters will fail without containment
- extension ownership may belong to platform provisioning rather than plugin migration policy

Current rollback behavior is limited to removing plugin-owned trigram indexes. That resolves the earlier shared-extension-ownership concern; the remaining compatibility risk in this migration area is PostgreSQL-specific indexing and prerequisite enforcement, not extension disablement.

**Decision:** Task 5 still owns PostgreSQL compatibility/documentation coverage, but rollback-time `disable_extension` is no longer an open blocker in the canonical migration file.

## Grep inventory

Audit grep results across `/opt/redmica/plugins/redmine_wiki_hub`:

| Pattern | Result |
|---|---|
| `prepend(` | `lib/wiki_hub/hooks.rb:21` |
| `class_eval` | no matches |
| `to_prepare` | `init.rb:24` |
| `routes.append` | no matches |
| `Journey` | no matches |
| `Rails.cache` | `app/controllers/wiki_hub_controller.rb:10,15` |
| `extension_enabled?` | `db/migrate/008_enable_pg_trgm.rb:12,54`; `lib/wiki_hub/healthcheck.rb:46` |
| `allowed_to?` | `app/controllers/wiki_hub_controller.rb:41,69`; `app/controllers/wiki_hub_metadata_controller.rb:7,14`; `app/controllers/wiki_hub_templates_controller.rb:75,116,181`; `app/services/wiki_hub/permission_filter.rb:11,16` |
| `caches_action` | no matches |
| `alias_method_chain` | no matches |

Absence of `routes.append`, `Journey` monkey patches, `caches_action`, and `alias_method_chain` reduces the remaining upgrade-risk surface. The principal current framework sensitivity is the isolated `WikiController.prepend` lifecycle bridge plus cache-behavior containment.

## Coverage notes from existing tests

- `test/integration/wiki_hub_landing_test.rb:11-32` proves route recognition for `/knowledge_hub`, `/projects/:project_id/wiki_hub`, and project search, but does not cover the full static route surface such as suggestions, quick create, bulk action, template analytics/use/preview, or homepage routes.
- `test/services/indexer_test.rb:12-29,101-129` and `test/integration/backlinks_panel_test.rb:9-37` provide relevant evidence that save/remove indexing side effects matter, which justifies preserving lifecycle hooks during remediation.
- `test/services/hooks_test.rb` now directly proves log-and-tolerate behavior for save, rename, and destroy lifecycle failures.
- No referenced tests currently prove cache invalidation beyond current private header semantics.

## Remediation map by downstream task

| Task | Scope owned by this audit | Exit condition for downstream work |
|---|---|---|
| Task 4 | Hook/lifecycle containment | Save/rename/destroy indexing behavior preserved with the smallest possible host integration surface and focused tests |
| Task 5 | `pg_trgm` migration compatibility | Postgres dependency documented/guarded; PostgreSQL-specific indexing and prerequisites remain explicit without reclaiming shared extension ownership on rollback |
| Task 7 | Cache and permission containment | Auth-sensitive caching semantics and permission checks are explicit, centralized where practical, and covered |
| Task 8 | Framework patch regression prevention | Removed framework monkey patches stay removed and are not reintroduced |

## Recommended sequencing

1. Task 4 first: preserve lifecycle indexing while reducing host controller coupling and keeping failures non-user-facing.
2. Task 5 next or in parallel: database compatibility work is mostly independent.
3. Task 7 after lifecycle stabilization: easier to reason about cache and authorization once the remaining host-touchpoint surface is stable.
4. Task 8 remains a regression-prevention checkpoint: keep framework monkey patches out of the codebase.
