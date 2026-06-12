# Automyra Bridge — Security Audit Report

- **Task:** 24 — SSRF UrlValidator + HMAC + permission audit
- **Date:** 2026-06-12
- **Scope:** `app/services/automyra_bridge/url_validator.rb` (SSRF) and HMAC
  signature / permission enforcement across the webhook, operator, chat,
  action-proposals, and activity-log endpoints.
- **Type:** Audit + report. Only clearly-safe, behavior-preserving fixes applied.
  Behavior-changing fixes are recorded as recommendations and gated behind
  Wave 3 characterization.
- **Evidence:**
  - `/root/.omo/evidence/task-24-ssrf-ranges.txt`
  - `/root/.omo/evidence/task-24-auth-consistency.txt`

## Summary

| Severity | Count |
|----------|-------|
| HIGH     | 1     |
| MEDIUM   | 4     |
| LOW      | 3     |

- **Internal IP range allowed through UrlValidator?** No. Every loopback,
  link-local, cloud-metadata (169.254.169.254), private (10/8, 172.16/12,
  192.168/16), CGNAT (100.64/10), all-zeros, and IPv6 internal target tested was
  **blocked**; public hosts were **allowed**. SSRF range coverage is complete.
- **Auth-consistency verdict:** Mostly consistent. Permission checks uniformly
  use native Redmine `allowed_to?`/`admin?`. Two real inconsistencies on the
  shared-secret machine endpoints (timing-safe compare + a shipped default
  secret). No fixes applied — all gated behind Wave 3.

No clearly-safe code change was warranted: `BLOCKED_RANGES` is already complete
(nothing obviously-missing to add), and every auth issue is behavior-changing.
**Zero code changes were made by this audit.**

---

## SSRF — `UrlValidator` (`app/services/automyra_bridge/url_validator.rb`)

The validator parses the URL, requires HTTP(S) + a hostname, enforces an
optional host allowlist, resolves the hostname, and rejects if any resolved
address falls in `BLOCKED_RANGES`. Call sites additionally invoke
`validate_connected_peer!` to re-check the actual connected socket peer
(TOCTOU/rebind mitigation).

`BLOCKED_RANGES` covers: `0.0.0.0/8`, `127.0.0.0/8`, `10.0.0.0/8`,
`100.64.0.0/10`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`
(includes 169.254.169.254 metadata), assorted IETF special-use v4 ranges,
multicast/reserved, and IPv6 `::/128`, `::1/128`, `::ffff:0:0/96`,
`64:ff9b::/96`, `100::/64`, `2001:db8::/32`, `fc00::/7`, `fe80::/10`, `ff00::/8`.

### Findings

#### SSRF-1 (LOW) — IPv6-literal URLs blocked incidentally, not by range match
- **File:** `url_validator.rb` `safe?` / `resolved_addresses` (lines ~70-90)
- A bracketed IPv6 literal (`http://[::1]/`) yields `URI#host == "[::1]"`
  (brackets retained). `Resolv.getaddresses("[::1]")` returns `[]`, so the URL
  is rejected with "hostname did not resolve" — **blocked, but via the
  resolve-failure path, not the explicit IPv6 ranges.** The IPv6 ranges DO
  apply to hostnames that resolve to internal IPv6 (the realistic vector).
- **Risk:** Low — net result is still BLOCK for every IPv6 internal literal
  tested (`::1`, `fc00::1`, `fe80::1`).
- **Recommendation (clearly safe, but still a behavior change → gate):** strip
  brackets before `Resolv.getaddresses` / `IPAddr.new` so literals are matched
  by range directly (defense-in-depth). **RISKY-ish:** touches the resolve path;
  gate behind characterization tests in Wave 3. Not applied.

#### SSRF-2 (LOW) — `trusted_internal_outbound_hosts` can bypass range blocks by design
- **File:** `url_validator.rb` `trusted_internal_host?` + `safe?` / `validate_connected_peer!`
- An operator-configured host in `trusted_internal_outbound_hosts` skips the
  blocked-range check (and the connected-peer check). This is intentional
  (lets the bridge reach an internal Automyra/memory endpoint) but is a
  deliberate SSRF carve-out worth documenting.
- **Recommendation:** Document the operational risk; ensure the setting is
  admin-only. No code change.

**SSRF verdict: no internal range is reachable; coverage complete. No HIGH/MED
SSRF findings.**

---

## HMAC & Permission Findings

#### AUTH-1 (HIGH) — Temporary admin password still active
- **Where:** Redmine `admin` account (environment-level, not plugin code).
- **Detail:** `admin` still authenticates with the temp password
  `[REDACTED-rotated-2026-06-12]` (verified live via `check_password?`).
- **Risk:** HIGH — full admin takeover with a known credential.
- **Recommendation:** Rotate immediately. **Owned by Task 22** — recorded here,
  not changed by this audit.

#### AUTH-2 (MED) — `activity_log` uses non-timing-safe secret comparison
- **File:** `automyra_bridge_activity_log_controller.rb:33`
  (`supplied != "Bearer #{expected}"`).
- **Detail:** The sibling webhook endpoint uses
  `ActiveSupport::SecurityUtils.secure_compare` (timing-safe,
  `webhooks_controller.rb:44`). The activity-log endpoint uses a plain `!=`,
  which short-circuits on first mismatched byte → theoretical timing oracle on
  the bearer secret.
- **Risk:** MED (remote timing side-channel; practical exploitability is low
  over a network but the inconsistency is real and the fix is cheap).
- **Recommendation:** Replace with
  `ActiveSupport::SecurityUtils.secure_compare(supplied, "Bearer #{expected}")`
  guarded by a blank check. **RISKY (behavior change on an auth path) → gate
  behind Wave 3 characterization.** Not applied.

#### AUTH-3 (MED) — `activity_log_secret` ships a guessable default
- **File:** `init.rb:32` (`'activity_log_secret' => 'change-me-in-production'`).
- **Detail:** Default plugin setting is a publicly-known string. Live value is
  currently **BLANK** (endpoint fail-closed verified), so not exploitable right
  now, but any operator who "sets the default" exposes a known secret.
- **Risk:** MED (latent — depends on operator behavior).
- **Recommendation:** Ship blank (force explicit configuration) or generate a
  random secret on install. **Behavior change → gate behind Wave 3.** Not applied.

#### AUTH-4 (MED) — Hardcoded HMAC secret fallback (inherited)
- **Where:** Per task context, a hardcoded HMAC secret fallback was expected in
  `config/additional_environment.rb` at the Redmica config root. **Only
  `additional_environment.rb.example` exists in this container** (no active
  `additional_environment.rb`), and the plugin resolves
  `hermes_webhook_secret` purely from plugin Settings (live value: set, not a
  hardcoded fallback). The init.rb defaults for both `webhook_secret` and
  `hermes_webhook_secret` are blank.
- **Risk:** MED if a hardcoded fallback exists in another environment/deploy.
- **Recommendation:** **Owned by Task 23** (HMAC fallback removal with a
  dual-secret grace window). Do NOT remove here. Recorded as a finding to feed
  Task 23. Not changed.

#### AUTH-5 (LOW) — `chat` run-event actions skip the shared permission filter
- **File:** `automyra_bridge_chat_controller.rb:7-8` skip
  `require_valid_chat_scope` + `require_automyra_chat_permission` for
  `run_events`/`run_events_stream`.
- **Detail:** Both actions enforce `authorized_to_view_run_events?` inline
  (owner OR `allowed_to?(:view_automyra_bridge_chat | :manage_automyra_bridge)`),
  so access is still controlled — but the mechanism differs from sibling
  actions (consistency smell, not a hole).
- **Risk:** LOW.
- **Recommendation:** Keep the inline check; optionally fold into a dedicated
  `before_action` for uniformity. No change.

#### AUTH-6 (LOW) — `action_proposals` silently defaults project to `redmine-dta`
- **File:** `automyra_bridge_action_proposals_controller.rb:82,91`.
- **Detail:** When `project_id` is blank on `create`/`find`, the controller
  defaults to project identifier `redmine-dta`. Authorization is still enforced
  against the resolved project (`authorize_project_manage!`), so it is not an
  authz bypass, but the silent fallback is surprising and could route a proposal
  to an unintended project.
- **Risk:** LOW.
- **Recommendation:** Require explicit `project_id` or fail loudly. Behavior
  change → gate behind Wave 3. Not applied.

---

## Clearly-Safe Fixes Applied

**None.** SSRF coverage is already complete (no obviously-missing range to add
without risk), and every auth finding is a behavior change on an auth path or is
owned by another task (22/23). Per the audit-first mandate, nothing was changed.

## Recommendations Routed to Other Waves/Tasks

- **Task 22:** Rotate the temp admin password (AUTH-1, HIGH).
- **Task 23:** HMAC secret fallback removal with dual-secret grace window (AUTH-4).
- **Wave 3 (characterization-gated):** AUTH-2 (timing-safe compare),
  AUTH-3 (default secret), AUTH-6 (project fallback), SSRF-1 (IPv6 bracket strip).

## Constraint Cross-Check

- HMAC algorithm: **sha256 retained** (no change). ✔
- Permission checks: native Redmine `allowed_to?`. ✔
- TLS: outbound uses `use_ssl` when scheme https; HTTP gated by `allow_http_outbound`. ✔
- CSRF: state-changing browser POSTs keep `verify_authenticity_token`; only
  machine endpoints (webhook, activity_log) and API-authenticated proposal
  actions skip it. ✔
- No secrets committed, no secret rotated, no migrations run, no DB modified. ✔
