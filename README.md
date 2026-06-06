# Automyra Bridge

Automyra Bridge is a policy-controlled integration plugin that connects Redmica to the Automyra assistant platform. It lets users request AI assistance on tasks and issues, runs an in-app assistant chat with a governed tool registry, delivers webhooks to Automyra/Hermes, and enforces a governance layer over the actions the assistant may take.

## Overview

The bridge adds three main capabilities to Redmica:

- **Assistant requests** on tasks and issues (improve a task, ask the assistant).
- **In-app chat** with threads, polling/streaming run events, attachments, and retryable jobs.
- **Governance**: action proposals that must be approved/rejected, policy runs, findings, and an audit trail, so the assistant operates under explicit human-in-the-loop control.

It integrates with Automyra over HTTP, optionally records memory events to an external memory/LanceDB endpoint, and delivers mention/creation-review/auto-close events to Hermes webhooks.

## Requirements

- Redmine/Redmica 6.0+
- A reachable Automyra endpoint and token
- (Optional) memory endpoint and Hermes webhook configuration

## Installation

1. Copy the plugin into your Redmica plugins directory:

   ```bash
   cd /opt/redmica/plugins
   git clone <repository-url> redmine_automyra_bridge
   ```

2. Run plugin migrations:

   ```bash
   cd /opt/redmica
   bundle exec rake redmine:plugins:migrate NAME=redmine_automyra_bridge RAILS_ENV=production
   ```

3. Restart the Redmica application server.

4. Enable the **Automyra Bridge** module on projects that should use it, grant permissions to roles, and configure the plugin settings (endpoint, token, webhooks).

## Permissions

| Permission | Purpose |
| --- | --- |
| `use_automyra_bridge` | Use assistant features (improve task, assistant request). Requires project membership. |
| `manage_automyra_bridge` | Operate the bridge: view the operator console, retry/cancel jobs, and update project settings. Requires project membership. |

## Configuration

Settings live under Redmine administration plugin settings for `redmine_automyra_bridge`:

| Setting | Default | Purpose |
| --- | --- | --- |
| `automyra_endpoint` | _(empty)_ | Base URL of the Automyra service. |
| `automyra_token` | _(empty)_ | Auth token for Automyra requests. |
| `request_timeout_seconds` | `15` | HTTP timeout for outbound calls. |
| `memory_endpoint` / `memory_token` | _(empty)_ | Optional external memory service. |
| `memory_session_key` | `main` | Memory session key. |
| `memory_model` | `manifest/auto` | Memory model selector. |
| `memory_lancedb_config_path` | `/root/.openclaw/openclaw.json` | LanceDB config path. |
| `memory_lancedb_uri` | _(empty)_ | LanceDB URI. |
| `memory_lancedb_table` | `memories` | Default memory table. |
| `memory_lancedb_redmine_table` | `redmine-memories` | Redmine memory table. |
| `webhook_secret` / `webhook_user_login` | _(empty)_ | Inbound webhook auth + acting user. |
| `hermes_webhook_url` | `https://automyra.sbg-server.com/webhooks/redmica-mentions` | Default Hermes webhook. |
| `hermes_webhook_url_mentions` / `_creation_review` / `_auto_close` | _(empty)_ | Per-event Hermes overrides. |
| `hermes_webhook_secret` | _(empty)_ | Hermes signing secret. |
| `activity_log_secret` | `change-me-in-production` | Secret for the activity-log API. |
| `auto_close_enabled` | `0` | Enable auto-close on a trigger status. |
| `auto_close_trigger_status_name` | `Resolved` | Status that triggers auto-close. |

> Set real secrets in production. Do not leave `activity_log_secret` at its placeholder value.

## Endpoints

### Assistant

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/automyra_bridge/task/improve` | Request task improvement. |
| `POST` | `/automyra_bridge/assistant_request` | General assistant request. |

### Chat

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/automyra_bridge/chat/send` | Send a chat message. |
| `GET` | `/automyra_bridge/chat/history` | Chat history. |
| `GET` | `/automyra_bridge/chat/poll` | Poll for updates. |
| `GET` | `/automyra_bridge/chat/runs/:id/events` | Run events. |
| `GET` | `/automyra_bridge/chat/runs/:id/events/stream` | Streamed run events. |
| `POST` | `/automyra_bridge/chat/{toggle_thread,mark_read,upload_attachment,retry_job,cancel_job,new_thread}` | Thread/job actions. |

### Operator console

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/projects/:project_id/automyra_bridge` | Operator dashboard. |
| `GET` | `/projects/:project_id/automyra_bridge/diagnostics` | Diagnostics (also global at `/automyra_bridge/diagnostics`). |
| `POST` | `/projects/:project_id/automyra_bridge/jobs/:id/retry` | Retry a job. |
| `POST` | `/projects/:project_id/automyra_bridge/jobs/:id/cancel` | Cancel a job. |
| `PATCH` | `/projects/:project_id/automyra_bridge/settings` | Update project settings. |

### Action proposals (governed actions)

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/automyra_bridge/proposals/:id` | Show a proposal. |
| `POST` | `/automyra_bridge/proposals/:id/approve` | Approve a proposal. |
| `POST` | `/automyra_bridge/proposals/:id/reject` | Reject a proposal. |
| `GET`/`POST` | `/automyra/proposals` | List/create proposals (JSON). |
| `GET`/`POST` | `/automyra/proposals/:id/status` | Proposal status (JSON). |

### Webhooks and activity log

| Method | Path | Description |
| --- | --- | --- |
| `POST` | `/automyra_bridge/webhooks/incoming` | Inbound webhook (JSON). |
| `POST` | `/automyra/activity_log` | Append an activity-log entry (JSON). |

### Governance (namespaced)

`/automyra_bridge/governance/` exposes RESTful `policies` (with `run_now`, `run_all_now`, `toggle_enabled`), plus read-only `runs`, `findings`, and `actions`.

## Architecture

- **Models** include chat threads/messages, runs and run events, jobs, action proposals, audit/activity/memory events, project settings, and the governance suite (policies, runs, findings, actions, review state).
- **Services** under `app/services/automyra_bridge/` implement a chat context builder, an assistant run processor, an action-proposal creator/executor, a tool registry, and a large catalogue of governed tools (issue create/update/comment/status/priority/due-date/search, task create/update/complete/cancel/reopen/assign/comment/search, wiki create/update/search/summarize/backlinks/related, project status summary, and context/memory helpers).
- **Jobs**: `HermesWebhookDeliverJob` (webhook delivery) and `GovernanceRunJob` (policy execution).
- **Hooks**: journal, issue-status, and issue-creation hooks install at boot to react to Redmine lifecycle events; the tool registry is validated on load.

## Documentation

See the `docs/` directory for operational and governance guidance:

- `runbook.md` — general operations.
- `governance_runbook.md`, `governance_policy_example.md`, `governance_provider_config.md`, `governance_scheduler.md`, `governance_rollback.md` — governance configuration and procedures.
- `next-phase-plan.md` — roadmap.

## Operational notes

- Restart the application after deploy so routes, hooks, and the tool registry reload. The running Puma process caches controller classes until restarted.
- Configure all secrets before enabling in production; the default `activity_log_secret` is a placeholder.
