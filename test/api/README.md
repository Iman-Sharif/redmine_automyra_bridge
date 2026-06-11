# Ask Automyra Chat — API curl Tests

> **Playwright / system tests (T33) are SKIPPED** because the test container is missing `libnspr4.so`, which is required by the Chromium runtime used by Playwright. The integration and functional tests in this plugin provide equivalent HTTP-level coverage.

---

## Authentication

All endpoints require a logged-in session cookie or valid Redmine API key passed in `X-Redmine-API-Key`. Anonymous requests return `302 Redirect` to the login page. Users without the `:use_automyra_bridge` permission receive `403 Forbidden`.

### Quick login session

```bash
# 1. Obtain a session cookie
curl -c cookies.txt -b cookies.txt \
  "http://localhost:3000/login" \
  -d "username=admin" \
  -d "password=admin"
```

### API key header (alternative)

```bash
export API_KEY="your_redmine_api_key"
```

---

## Endpoints

### 1. `send_message` — POST /automyra_bridge/chat/send

Send a user message into the current chat thread.  
*(Placeholder in T18 — currently returns `204 No Content`.)*

**Request**

```bash
curl -X POST \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/send" \
  -H "Content-Type: application/json" \
  -d '{"body":"Create a new issue for the server outage","page_type":"issue","page_id":1}'
```

**Response — 204 No Content**

```
HTTP/1.1 204 No Content
```

---

### 2. `history` — GET /automyra_bridge/chat/history

Retrieve the full message history for the current thread.

**Request**

```bash
curl -X GET \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/history?thread_kind=page&page_type=issue&page_id=1" \
  -H "Accept: application/json"
```

**Response — 200 OK**

```json
{
  "messages": []
}
```

*(Returns empty array until T18 implements full history serialization.)*

---

### 3. `poll` — GET /automyra_bridge/chat/poll

Poll for new messages in the thread since the last known `message_id`.

**Request — empty thread (first load)**

```bash
curl -X GET \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/poll?thread_kind=page&page_type=issue&page_id=1&last_message_id=0" \
  -H "Accept: application/json"
```

**Response — 200 OK (no thread yet)**

```json
{
  "messages": [],
  "unread_count": 0
}
```

**Request — after new messages exist**

```bash
curl -X GET \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/poll?thread_kind=page&page_type=issue&page_id=1&last_message_id=42" \
  -H "Accept: application/json"
```

**Response — 200 OK (with messages)**

```json
{
  "messages": [
    {
      "id": 43,
      "role": "assistant",
      "content": "I've created issue #123 for the outage.",
      "status": "delivered",
      "created_at": "2025-05-02T10:15:30Z",
      "has_proposal": true,
      "proposal_id": 7
    }
  ],
  "unread_count": 1
}
```

---

### 4. `toggle_thread` — POST /automyra_bridge/chat/toggle_thread

Create or switch the active thread for a page (or global). Returns the thread metadata plus its last 50 messages.

**Request — page thread**

```bash
curl -X POST \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/toggle_thread" \
  -H "Content-Type: application/json" \
  -d '{"thread_kind":"page","page_type":"issue","page_id":1}'
```

**Response — 200 OK (new thread)**

```json
{
  "thread_id": 5,
  "thread_kind": "page",
  "messages": [],
  "unread_count": 0
}
```

**Request — global thread**

```bash
curl -X POST \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/toggle_thread" \
  -d '{"thread_kind":"global"}'
```

**Response — 200 OK (global thread)**

```json
{
  "thread_id": 6,
  "thread_kind": "global",
  "messages": [],
  "unread_count": 0
}
```

---

### 5. `mark_read` — POST /automyra_bridge/chat/mark_read

Reset the unread counter for the current thread.

**Request**

```bash
curl -X POST \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/mark_read" \
  -H "Content-Type: application/json" \
  -d '{"thread_kind":"page","page_type":"issue","page_id":1}'
```

**Response — 204 No Content**

```
HTTP/1.1 204 No Content
```

---

### 6. `upload_attachment` — POST /automyra_bridge/chat/upload_attachment

Attach a file to an existing chat message.

**Request**

```bash
curl -X POST \
  -c cookies.txt -b cookies.txt \
  "http://localhost:3000/automyra_bridge/chat/upload_attachment" \
  -F "thread_kind=page" \
  -F "page_type=issue" \
  -F "page_id=1" \
  -F "message_id=99" \
  -F "file=@/path/to/screenshot.png"
```

**Response — 200 OK**

```json
{
  "id": 12,
  "filename": "screenshot.png",
  "url": "/attachments/12",
  "content_type": "image/png",
  "filesize": 48231
}
```

**Error — thread not found**

```
HTTP/1.1 404 Not Found
```

**Error — message not found**

```
HTTP/1.1 404 Not Found
```

**Error — no file provided**

```
HTTP/1.1 400 Bad Request

{"error":"No file provided"}
```

---

## Authentication / Permission Errors

### Anonymous request

```bash
curl -X GET \
  "http://localhost:3000/automyra_bridge/chat/history" \
  -H "Accept: application/json"
```

**Response**

```
HTTP/1.1 302 Found
Location: /login
```

### Missing permission

```bash
curl -X GET \
  -H "X-Redmine-API-Key: $USER_API_KEY" \
  "http://localhost:3000/automyra_bridge/chat/history" \
  -H "Accept: application/json"
```

**Response**

```json
{
  "success": false,
  "error": "Access denied"
}
```

---

## Testing with `ruby -Itest`

```bash
# Run only the chat integration tests
cd /opt/redmica
ruby -Ilib:test plugins/redmine_automyra_bridge/test/integration/automyra_bridge_chat_flow_test.rb

# Run the full plugin test suite
ruby -Ilib:test -e "Dir['plugins/redmine_automyra_bridge/test/**/*_test.rb'].each { |f| require File.expand_path(f) }"
```

---

## Notes

- `send_message` and `history` are currently stubbed in the controller (T18). The integration test exercises the HTTP contract so that once the backend logic is implemented, the same request/response shapes remain valid.
- `poll` is fully implemented and tested end-to-end in `automyra_bridge_chat_flow_test.rb`.
- `upload_attachment` relies on Redmine's `Attachment` model and `acts_as_attachable`; ensure file storage is configured.
