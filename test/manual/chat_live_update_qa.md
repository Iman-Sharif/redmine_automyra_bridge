# Chat live update polling manual QA checklist

Use this lightweight checklist to verify that pending chat bubbles update in place when the poll endpoint returns messages changed after the `last_seen_update_at` cursor.

- [ ] Open an issue page with the Automyra chat panel enabled and confirm existing history loads.
- [ ] Send a message that creates an assistant pending bubble; note that the bubble remains visible while work is pending.
- [ ] Keep the panel open without refreshing the page until the backend updates the same assistant message record from `pending` to `delivered` or `failed`.
- [ ] Confirm the existing pending bubble changes status/content in place instead of creating a duplicate bubble.
- [ ] Confirm the browser network request to `/automyra_bridge/chat/poll` includes both `last_message_id` and `last_seen_update_at` after the first poll response.
- [ ] Confirm the poll response includes `last_message_id`, `last_seen_update_at`, and `server_time` cursor metadata.
- [ ] Refresh the page and confirm the final assistant message still appears once in chat history.
