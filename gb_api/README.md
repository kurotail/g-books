# gb-api

REST API server for g-books, built with Go's standard `net/http` library and JWT-based authentication.

- **Runtime:** Go 1.26+
- **Port:** `8080`
- **Auth scheme:** JWT (HS256) — short-lived access tokens + single-use rotating refresh tokens
- **Real-time:** server-state changes are pushed to subscribers over a WebSocket (`GET /api/state/ws`)

---

## Run

Build the image and start a container:

```bash
docker build -t gb-api .
docker run --rm --env-file .env -p 8080:8080 gb-api
```

The server listens on `8080` inside the container; `-p 8080:8080` publishes it to the host.

---

## Role

| user type | role |
|-----------|------|
| Student   | 0          |
| Teacher   | 1          |
| Admin     | 2          |

---

## Authentication flow

```
POST /api/login
  → access_token  (15 min)
  → refresh_token (7 days, single-use)

POST /api/refresh            ← { "refresh_token": "..." }
  → new access_token
  → new refresh_token        (old token is invalidated immediately)
```

Refresh tokens are single-use. Using the same refresh token twice returns `401`.

---

## Endpoints at a glance

| Method & path | Auth | Description |
|---------------|------|-------------|
| `POST /api/login` | — | Exchange credentials for a token pair |
| `POST /api/register` | Bearer (> Student) | Register a new user (Student or Teacher; Admins cannot be created) |
| `POST /api/refresh` | — | Rotate a refresh token into a new token pair |
| `GET /api/users` | Bearer | List all users (username, role, group) |
| `POST /api/group/set` | Bearer (> Student) | Assign a user to a group (`group_id` `0` removes them) |
| `POST /api/group/name` | Bearer (member or > Student) | Rename a group |
| `POST /api/group/building` | Bearer (member or > Student) | Set a group's building (`building_id` `0` clears it) |
| `GET /api/group` | Bearer | Read the caller's own group |
| `POST /api/group/members` | Bearer | List the members of a group |
| `POST /api/item/inv` | Bearer | Read a group's inventory |
| `POST /api/item/slot` | Bearer | Read a group's slots |
| `POST /api/item/inv2slot` | Bearer | Move one item from inventory into a slot |
| `POST /api/item/slot2inv` | Bearer | Return a slotted item to the inventory |
| `POST /api/question/generate` | Bearer | Issue a random question + single-use session (students only in `QUIZ` state) |
| `POST /api/question/answer` | Bearer | Answer a question session (students only in `QUIZ` state); returns whether it was correct |
| `POST /api/question/upload` | Bearer (> Student) | Bulk-add questions to the pool; returns a `207` per-question result list |
| `GET /api/question/search` | Bearer (> Student) | Search the question pool by description substring |
| `PUT /api/question/{id}` | Bearer (> Student) | Update a pooled question by ID |
| `DELETE /api/question/{id}` | Bearer (> Student) | Delete a pooled question by ID |
| `GET /api/state` | Bearer | Read the current server state (`NORMAL` / `QUIZ`) |
| `POST /api/state` | Bearer (> Student) | Transition the server state |
| `GET /api/state/ws` | Bearer or `?access_token=` | WebSocket; pushes the current state on connect and on every `NORMAL` ⇄ `QUIZ` transition |

---

## Authentication

### `POST /api/login`

Authenticate with username and password.

**Request**

```json
{
  "username": "user",
  "password": "password123"
}
```

**Response `200 OK`**

```json
{
  "access_token":  "<jwt>",
  "refresh_token": "<jwt>"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `username` / `password` |
| `401`  | Wrong username or password |

---

### `POST /api/register`

Create a new user. The caller must present a valid access token and be a Teacher or
Admin. Teachers and Admins may create Students (`0`) or Teachers (`1`);
**Admins cannot be created via this endpoint**. An optional `group_id` places the
new user in a group immediately; if omitted (or `0`) the user starts in no group —
use `POST /api/group/set` to change it later.

Requires a valid access token:

```
Authorization: Bearer <access_token>
```

**Request** — `role` is `0` (Student) or `1` (Teacher); `group_id` is optional (`0` = no group)

```json
{
  "username": "alice",
  "password": "password123",
  "role": 0,
  "group_id": 2
}
```

**Response** — `201 Created` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a missing `username` / `password` / `role`, or a `role` greater than `2` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student, or `role` is `2` (Admin) |
| `409`  | A user with that username already exists |

---

### `POST /api/refresh`

Exchange a valid refresh token for a new token pair. The submitted token is invalidated on use.

**Request**

```json
{
  "refresh_token": "<jwt>"
}
```

**Response `200 OK`**

```json
{
  "access_token":  "<jwt>",
  "refresh_token": "<jwt>"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Missing or malformed body |
| `401`  | Token invalid, expired, already used, or wrong token type |

---

## Users & Groups

Each user has a `group_id`: `0` means **no group**, any value `> 0` is a real
group (groups are created on demand the first time they are referenced).
`GET /api/users` lists every account; the group endpoints read and change
membership.

All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `GET /api/users`

List all users. Any authenticated user may call it.

**Response `200 OK`** — `group_id` is `0` for users not in any group

```json
{
  "users": [
    { "username": "user",  "role": 1, "group_id": 1 },
    { "username": "alice", "role": 0, "group_id": 0 }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `POST /api/group/set`

Assign `username` to a group. **Teachers and Admins only.** A `group_id` of `0`
removes the user from their group; any value `> 0` places them in that group.

**Request**

```json
{ "username": "alice", "group_id": 2 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `username` / `group_id` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | The target `username` does not exist |

---

### `POST /api/group/name`

Rename a group. The caller must be a **member of the group**, or a **Teacher /
Admin** (who may rename any group). A group with no name set reads back as
`"Group <id>"` by default.

**Request** — `group_id` must be greater than 0; `name` must be non-empty

```json
{ "group_id": 1, "name": "Red Team" }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a missing `name`, or `group_id` is missing / not greater than 0 |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is neither a member of the group nor a Teacher/Admin |

---

### `POST /api/group/building`

Set a group's building. The caller must be a **member of the group**, or a
**Teacher / Admin** (who may set any group's building). A `building_id` of `0`
clears the assignment.

**Request** — `group_id` must be greater than 0; `building_id` is required (`0` = none)

```json
{ "group_id": 1, "building_id": 3 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a missing `building_id`, or `group_id` is missing / not greater than 0 |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is neither a member of the group nor a Teacher/Admin |

---

### `GET /api/group`

Return the calling user's own group. `name` defaults to `"Group <id>"` when
unset; `building_id` is `0` when no building is assigned.

**Response `200 OK`**

```json
{ "group_id": 1, "name": "Group 1", "building_id": 0 }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | The caller is not in any group |

---

### `POST /api/group/members`

List the members of a group. Any authenticated user may call it.

**Request** — `group_id` must be greater than 0

```json
{ "group_id": 1 }
```

**Response `200 OK`**

```json
{ "group_id": 1, "name": "Group 1", "members": ["user", "alice"] }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or `group_id` is missing / not greater than 0 |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

## Inventory

A group owns an **inventory** — a map of `item_id → quantity` — and a set of **slots**,
where each `slot_id` holds at most one item. Items move between the two:

- `inv2slot` takes one unit of an item out of the inventory and places it in a slot.
- `slot2inv` returns a slotted item to the inventory and clears the slot.

**Slot value encoding** — a slot's value is a *signed* `item_id`:

| Value | Meaning |
|-------|---------|
| `> 0` | A **normal** item; the value is its `item_id` |
| `< 0` | A **broken** item; its `item_id` is the absolute value (e.g. `-3` = broken item `3`) |
| `0`   | **Empty** slot — no item |

Inventory quantities are always non-negative; only slot values can be negative.

All inventory endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

Every request body carries a `group_id`, which must be **greater than 0** (group
`0` means "no group"); the relevant `item_id` / `slot_id` fields are listed per
endpoint below.

### `POST /api/item/inv`

Return the group's inventory.

**Request**

```json
{ "group_id": 1 }
```

**Response `200 OK`** — `inventory` is a map of `item_id → quantity`

```json
{ "group_id": 1, "inventory": { "1": 3, "2": 1 } }
```

---

### `POST /api/item/slot`

Return the group's slots.

**Request**

```json
{ "group_id": 1 }
```

**Response `200 OK`** — `slots` is a map of `slot_id → item_id`, where the value
is signed (see [Slot value encoding](#inventory): `> 0` normal, `< 0` broken,
`0` empty)

```json
{ "group_id": 1, "slots": { "0": 1, "2": -3 } }
```

Here slot `0` holds normal item `1`, and slot `2` holds a **broken** item `3`.

---

### `POST /api/item/inv2slot`

Move one unit of `item_id` from the inventory into `slot_id`. The inventory count is
decremented by one (and the item removed when it reaches zero); the slot is set to the
item as a **normal** (positive) value. `item_id` must be greater than 0.

**Request**

```json
{ "group_id": 1, "item_id": 1, "slot_id": 5 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Insufficient stock — the item's inventory count would drop below zero |

---

### `POST /api/item/slot2inv`

Return the item held in `slot_id` to the inventory. The inventory count is incremented by
one and the slot is cleared (set to `0`). Only **normal** items can be returned — a
**broken** item (negative value) cannot be moved back to the inventory.

**Request**

```json
{ "group_id": 1, "slot_id": 5 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | The slot does not exist, is empty (`0`), or holds a **broken** item (已損毀) |

---

**Error responses common to all inventory endpoints**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body; a required field (`item_id` / `slot_id`) is missing; `group_id` is missing or not greater than 0; or (for `inv2slot`) `item_id` is not greater than 0 |
| `401`  | Missing or malformed `Authorization` header, or an invalid/expired access token |

---

## Questions

A quiz flow split into two steps:

- `generate` picks a random question and opens a **single-use session** (15 min TTL).
- `answer` submits a session's answer. The session is **deleted on use** and the
  server replies whether the answer was correct.

Both are gated by the **server state machine** (see below): Teachers and Admins may
always generate and answer, while Students may only do so while the server is in `QUIZ`
state.

### Server state machine

The server holds a single global state, either `NORMAL` (default) or `QUIZ`,
maintained in-process by the service layer:

| State    | Student `generate` / `answer` | Teacher / Admin |
|----------|-------------------------------|-----------------|
| `NORMAL` | ❌ `403`                      | ✅              |
| `QUIZ`   | ✅                            | ✅              |

Read the state with `GET /api/state`; transition it with `POST /api/state`
(Teacher / Admin only).

Both endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `POST /api/question/generate`

Issue a new question session.

**Request**

```json
{ "group_id": 1 }
```

**Response `200 OK`** — the question text and its session ID (the answer is never returned)

```json
{
  "session": "0123456789abcdef0123456789abcdef",
  "description": "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or `group_id` is missing / not greater than 0 |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is in `NORMAL` state |

---

### `POST /api/question/answer`

Answer a question session. The answer is the zero-based index of the chosen option.

**Request**

```json
{ "session": "0123456789abcdef0123456789abcdef", "answer": 1 }
```

**Response `200 OK`**

```json
{ "correct": true }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, missing `session` or `answer`, or the session is unknown/already used/expired |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is in `NORMAL` state |

---

### Question pool management

The questions handed out by `generate` are drawn from a shared **question pool**.
Teachers and Admins manage this pool: bulk-upload new questions, search existing
ones, and update or delete them by ID. All four endpoints require a valid access
token and a role above Student — Students receive `403`.

Each question is `{ description, answer }`, where `answer` is the zero-based index
of the correct option and the options are embedded as text inside `description`.

```
Authorization: Bearer <access_token>
```

### `POST /api/question/upload`

Add a batch of questions in a single request. Invalid questions (empty
`description`) are skipped rather than failing the whole batch, so the response is
a **`207 Multi-Status`** carrying one result per submitted question, in request
order.

**Request**

```json
{
  "questions": [
    { "description": "2+2?\n(a)3\n(b)4", "answer": 1 },
    { "description": "", "answer": 0 },
    { "description": "Capital of France?\n(a)Paris\n(b)Rome", "answer": 0 }
  ]
}
```

**Response `207 Multi-Status`** — each result's `status` is `201` for a created
question (with its new `id`) or `400` for a rejected one (with an `error`)

```json
{
  "results": [
    { "index": 0, "status": 201, "id": 3 },
    { "index": 1, "status": 400, "error": "description 不可為空" },
    { "index": 2, "status": 201, "id": 4 }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or an empty `questions` list |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `GET /api/question/search`

Search the pool by case-insensitive substring of the question description. Omit
`q` (or pass it empty) to list every question.

**Request** — query parameter

```
GET /api/question/search?q=france
```

**Response `200 OK`** — matches in ascending `id` order; the answer is included
(teacher-facing)

```json
{
  "questions": [
    { "id": 4, "description": "Capital of France?\n(a)Paris\n(b)Rome", "answer": 0 }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `PUT /api/question/{id}`

Overwrite the pooled question with the given `id`.

**Request**

```json
{ "description": "2+2?\n(a)3\n(b)4", "answer": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a non-numeric `{id}`, or an empty `description` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | No question with that `id` |

---

### `DELETE /api/question/{id}`

Remove the pooled question with the given `id`.

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | No question with that `id` |

---

### `GET /api/state`

Read the current server state.

**Response `200 OK`**

```json
{ "state": "NORMAL" }
```

---

### `POST /api/state`

Transition the server state. Only Teachers and Admins may call it.

**Request**

```json
{ "state": "QUIZ" }
```

**Response `200 OK`**

```json
{ "state": "QUIZ" }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a state other than `NORMAL` / `QUIZ` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `GET /api/state/ws`

Subscribe to server-state changes over a WebSocket. Any authenticated user may
subscribe (same access policy as `GET /api/state`). On connect the server sends
the current state immediately, then pushes a message on every transition into or
out of `QUIZ`.

Because browsers cannot set headers on a WebSocket handshake, the access token
may be supplied either way:

- `Authorization: Bearer <access_token>` header, or
- `?access_token=<access_token>` query parameter.

**Messages** — each frame is JSON, identical in shape to `GET /api/state`:

```json
{ "state": "QUIZ" }
```

**Lifecycle**

- The first message is the current state at connect time (a snapshot).
- Subsequent messages are sent only when the state actually changes; a single
  transition is broadcast to every connected subscriber.
- On server shutdown each connection is closed gracefully with a WebSocket
  Going-Away (`1001`) close frame.

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing or invalid access token — the handshake is rejected before the upgrade |

---

## Token reference

| Token | TTL | Signing key env var | Notes |
|-------|-----|---------------------|-------|
| Access | 15 minutes | `JWT_KEY` | Sent in `Authorization` header |
| Refresh | 7 days | `JWT_REFRESH_KEY` | Single-use; rotated on every `/api/refresh` call |

> **Note:** Signing keys are currently hardcoded constants. Replace with environment variables before deploying to production.
