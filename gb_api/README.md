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
| `POST /api/building` | Bearer (> Student) | Create a building |
| `GET /api/building` | Bearer | List all buildings |
| `GET /api/building/{id}` | Bearer | Read a building by ID |
| `POST /api/item` | Bearer | Read all of a group's items (inventory + slots) |
| `POST /api/item/inv2slot` | Bearer (not Student in QUIZ) | Move one item from inventory into a slot (swaps out any normal item already there) |
| `POST /api/item/slot2inv` | Bearer (not Student in QUIZ) | Return a slotted item to the inventory |
| `POST /api/question/generate` | Bearer (NORMAL) | Roll a new item + open a session to claim it (students NORMAL-only) |
| `POST /api/question/target` | Bearer (QUIZ) | Open an attack/repair session against a group's slot (students QUIZ-only) |
| `POST /api/question/answer` | Bearer | Answer the held session: grant item, or break/repair the target |
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

## Buildings

A **building** is a named layout that groups can be assigned to (see
[`POST /api/group/building`](#post-apigroupbuilding)). Each building has:

- `name` — a display name; a building with no name set reads back as `"Building <id>"`.
- `layout` — an opaque, frontend-specific JSON string, stored and returned **verbatim**
  (the server never parses it).
- `item_allowed_slot` — a map of `item_id → [slot_id, …]` describing which slots each
  item is allowed to occupy.
- `difficulty_type` — a map of `difficulty → [type, …]` listing the item types at each
  difficulty level in the building.

Buildings are created by Teachers/Admins; any authenticated user may read them.
All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `POST /api/building`

Create a building. **Teachers and Admins only.** `name` is required; `layout`,
`item_allowed_slot`, and `difficulty_type` are optional (omitted maps read back as empty).
The new building's `building_id` is assigned by the server and returned in the response.

**Request**

```json
{
  "name": "Library",
  "layout": "{\"w\":3,\"h\":2}",
  "item_allowed_slot": { "10": [0, 2], "20": [1] },
  "difficulty_type": { "1": [10, 30], "2": [20] }
}
```

**Response `200 OK`**

```json
{
  "building_id": 2,
  "name": "Library",
  "layout": "{\"w\":3,\"h\":2}",
  "item_allowed_slot": { "10": [0, 2], "20": [1] },
  "difficulty_type": { "1": [10, 30], "2": [20] }
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `name` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `GET /api/building`

List every building. Any authenticated user may call it.

**Response `200 OK`** — a JSON array of buildings

```json
[
  { "building_id": 1, "name": "Library", "layout": "{}", "item_allowed_slot": {}, "difficulty_type": {} },
  { "building_id": 2, "name": "Gym", "layout": "{\"w\":3}", "item_allowed_slot": { "10": [0, 2] }, "difficulty_type": { "1": [10] } }
]
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `GET /api/building/{id}`

Read a single building by ID. Any authenticated user may call it.

**Response `200 OK`**

```json
{
  "building_id": 1,
  "name": "Library",
  "layout": "{}",
  "item_allowed_slot": {},
  "difficulty_type": {}
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | No building with that `id` |

---

## Inventory

Items are **unique instances** stored in an internal `items` table — each is
`{ item_id, type, question_id }`, where `type` ties it to a building's
[`item_allowed_slot` / `difficulty_type`](#buildings) and `question_id` links it to a
pooled question (`0` = none). The items table is managed **internally** (no public
create/list API). *(An item with nothing referencing it should eventually be garbage
collected; that cleanup is a TODO, not yet implemented.)*

A group owns a set of these items, split between:

- **inventory** — the item IDs the group holds loose (not placed), and
- **slots** — `slot_id → item`, where each slot holds at most one item.

Inventory and slots are **disjoint**: an item is either loose in the inventory or sitting
in a slot, never both. Items move between them:

- `inv2slot` takes an owned item out of the inventory and places it in a slot.
- `slot2inv` returns a slotted item to the inventory and clears the slot.

**Broken items** — a slot can hold a *broken* item, surfaced as `"broken": true` in the
slot view. A broken item cannot be returned to the inventory or replaced.

**QUIZ-state restriction** — the two *move* endpoints (`inv2slot` and `slot2inv`)
are disabled for **students** while the server is in `QUIZ` state (they get
`403`); Teachers and Admins are unaffected. The read endpoint (`POST /api/item`)
is always available. (This is the inverse of the question endpoints, which are
the ones students may use *only* during `QUIZ`.)

All inventory endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

Every request body carries a `group_id`, which must be **greater than 0** (group
`0` means "no group"); the relevant `item_id` / `slot_id` fields are listed per
endpoint below.

### `POST /api/item`

Return **all** of a group's items: its `inventory` (an array of items) and its `slots`
(`slot_id → item`).

**Visibility** — a **student** sees the full `item_id` / `type` / `question_id` only when
querying **their own** group; for any other group they see **only `type`** (the
`item_id` and `question_id` fields are omitted). **Teachers and Admins** always see the
full fields.

**Request**

```json
{ "group_id": 1 }
```

**Response `200 OK`** (full view — own group, or teacher/admin)

```json
{
  "group_id": 1,
  "inventory": [
    { "item_id": 1, "type": 10, "question_id": 1 },
    { "item_id": 2, "type": 20, "question_id": 2 }
  ],
  "slots": {
    "0": { "item_id": 3, "type": 10, "broken": false }
  }
}
```

**Response `200 OK`** (restricted view — a student querying another group): only `type`
is exposed per item.

```json
{
  "group_id": 1,
  "inventory": [ { "type": 10 }, { "type": 20 } ],
  "slots": { "0": { "type": 10, "broken": false } }
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or `group_id` is missing / not greater than 0 |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `POST /api/item/inv2slot`

Move the owned item `item_id` from the group's inventory into `slot_id`. The item's
**Type must be allowed in that slot** by the group's building (the building's
`item_allowed_slot`); otherwise the move is rejected. The destination slot may already
hold a **normal** item — it is **swapped** back into the inventory before the new item is
placed. A slot holding a **broken** item cannot be replaced.

**Request**

```json
{ "group_id": 1, "item_id": 1, "slot_id": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | `item_id` is not in the group's inventory |
| `400`  | The item's `type` is not allowed in `slot_id` by the group's building |
| `400`  | The destination slot holds a **broken** item (已損毀) and cannot be replaced |
| `403`  | A **student** caller while the server is in `QUIZ` state |

---

### `POST /api/item/slot2inv`

Return the item held in `slot_id` to the group's inventory and clear the slot. Only a
**normal** item can be returned — a **broken** item cannot be moved back.

**Request**

```json
{ "group_id": 1, "slot_id": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | The slot does not exist, is empty, or holds a **broken** item (已損毀) |
| `403`  | A **student** caller while the server is in `QUIZ` state |

---

**Error responses common to all inventory endpoints**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body; a required field (`item_id` / `slot_id`) is missing; `group_id` is missing or not greater than 0; or (for `inv2slot`) `item_id` is not greater than 0 |
| `401`  | Missing or malformed `Authorization` header, or an invalid/expired access token |

---

## Questions

The quiz drives the game loop. A **generate** endpoint opens a **single-use session**
(15 min TTL); the shared **answer** endpoint consumes it and acts on the session's kind.
There are two generate endpoints, gated by the server state:

- **`POST /api/question/generate`** (NORMAL) — *earn an item*. Creates a brand-new item of a
  random type (drawn from the caller-group's building `difficulty_type` for the requested
  difficulty) tied to a random `area 1` question of that difficulty. Answering **correctly**
  adds the item to the group's inventory.
- **`POST /api/question/target`** (QUIZ) — *attack / repair*. Targets a group's slot.
  Answering **correctly** breaks an enemy's slotted item or repairs your own broken one.

The caller's own group comes from their token; the caller must be in a group. The graded
answer is never leaked in the generate response.

### Server state machine

The server holds a single global state, either `NORMAL` (default) or `QUIZ`. Students are
restricted to the matching endpoint; **Teachers and Admins bypass the state gate**:

| Endpoint | Student may call in | Teacher / Admin |
|----------|---------------------|-----------------|
| `POST /api/question/generate` (item) | `NORMAL` only | any state |
| `POST /api/question/target` (attack/repair) | `QUIZ` only | any state |
| `POST /api/question/answer` | any state | any state |

Read the state with `GET /api/state`; transition it with `POST /api/state`
(Teacher / Admin only). All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `POST /api/question/generate` — earn an item (NORMAL)

Roll a new item for the requested `difficulty` and open a session to claim it.

**Request**

```json
{ "difficulty": 1 }
```

**Response `200 OK`** — the question text and its session id (the answer is never returned)

```json
{
  "session": "0123456789abcdef0123456789abcdef",
  "description": "What is six times three?\n(a)6\n(b)18\n(c)9\n(d)12"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body or missing `difficulty`; caller is in no group; the group's building lists no type for the difficulty; or no `area 1` question matches the difficulty |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is not in `NORMAL` state |

---

### `POST /api/question/target` — attack / repair (QUIZ)

Open a session against `target_slot_id` in `target_group_id`. **Valid** only when:

- **attack** — the target is **another** group and its slot item is **not broken**; the
  graded question is that item's own question, and a correct answer **breaks** it; or
- **repair** — the target is the caller's **own** group and its slot item **is broken**; the
  graded question is a random `area 2` question, and a correct answer **repairs** it.

**Request**

```json
{ "target_group_id": 2, "target_slot_id": 0 }
```

**Response `200 OK`** — `{ "session", "description" }`, same shape as above.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body; `target_group_id` missing / not greater than 0; `target_slot_id` missing; the target slot is empty; the target item has no question; or the target is invalid (own non-broken slot, or another group's broken slot) |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is not in `QUIZ` state |

---

### `POST /api/question/answer`

Answer the held session (the zero-based index of the chosen option). The session is
**deleted on use** and the action depends on its kind.

**Request**

```json
{ "session": "0123456789abcdef0123456789abcdef", "answer": 1 }
```

**Response `200 OK`** — `correct` is always present. `item_id` is set when an **item**
session's correct answer grants an item. `success` is set for **target** sessions and reports
whether the break/repair actually happened (`false` if the slot's broken state no longer
allows it; a wrong answer omits it).

```json
{ "correct": true, "item_id": 5 }
```

```json
{ "correct": true, "success": true }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, missing `session` or `answer`, or the session is unknown/already used/expired |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### Question pool management

The questions handed out by `generate` are drawn from a shared **question pool**.
Teachers and Admins manage this pool: bulk-upload new questions, search existing
ones, and update or delete them by ID. All four endpoints require a valid access
token and a role above Student — Students receive `403`.

Each question is `{ description, answer, difficulty, area }`, where `answer` is the
zero-based index of the correct option and the options are embedded as text inside
`description`. `difficulty` and `area` are `uint` classifiers (default `0`): they drive
which question the generate endpoints draw (item → `area 1` + the requested difficulty;
repair → `area 2`) and also filter [search](#get-apiquestionsearch).

```
Authorization: Bearer <access_token>
```

### `POST /api/question/upload`

Add a batch of questions in a single request. Invalid questions (empty
`description`) are skipped rather than failing the whole batch, so the response is
a **`207 Multi-Status`** carrying one result per submitted question, in request
order.

**Request**

`difficulty` and `area` are optional per question (default `0`).

```json
{
  "questions": [
    { "description": "2+2?\n(a)3\n(b)4", "answer": 1, "difficulty": 1, "area": 2 },
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

The optional `difficulty` and `area` query parameters filter by **exact match**
(`uint`); each is applied only when present, and combined with `q` and with each
other as a logical **AND**.

**Request** — query parameters

```
GET /api/question/search?q=france&difficulty=1&area=2
```

| Parameter | Description |
|-----------|-------------|
| `q`          | Case-insensitive substring of `description`; omitted/empty matches all |
| `difficulty` | Exact `difficulty` to match; omitted = not filtered |
| `area`       | Exact `area` to match; omitted = not filtered |

**Response `200 OK`** — matches in ascending `id` order; the answer is included
(teacher-facing)

```json
{
  "questions": [
    { "id": 4, "description": "Capital of France?\n(a)Paris\n(b)Rome", "answer": 0, "difficulty": 1, "area": 2 }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | `difficulty` or `area` is present but not a valid non-negative integer |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `PUT /api/question/{id}`

Overwrite the pooled question with the given `id`. `difficulty` and `area` are
optional (default `0`).

**Request**

```json
{ "description": "2+2?\n(a)3\n(b)4", "answer": 1, "difficulty": 1, "area": 2 }
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
