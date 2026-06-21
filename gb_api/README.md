# gb-api

REST API server for g-books, built with Go's standard `net/http` library and JWT-based authentication.

- **Runtime:** Go 1.26+
- **Storage:** PostgreSQL (via `pgx`); schema loaded from `postgres/init.sql`, admin account seeded on startup
- **Edge:** nginx reverse proxy terminating HTTPS on `443` (HTTP on `80` redirects to it)
- **Auth scheme:** JWT (HS256) — short-lived access tokens + single-use rotating refresh tokens
- **Real-time:** server-state changes are pushed to subscribers over a WebSocket (`GET /api/state/ws`, reached at `wss://localhost/api/state/ws`)

---

## Run

The stack runs as three containers via Docker Compose: a PostgreSQL database (`postgres`), the
Go API (`api`, internal only), and an nginx reverse proxy (`nginx`) that terminates HTTPS and
serves uploaded media. On a fresh database volume, `postgres` runs `postgres/init.sql`
(mounted into `/docker-entrypoint-initdb.d`) to create the schema. The API waits for
`postgres` to be healthy, then seeds the admin account on startup.

**1. Generate a self-signed TLS certificate** (one time; written to `nginx/certs/`):

```bash
sh nginx/gen-certs.sh          # or, on Windows PowerShell:
# powershell -ExecutionPolicy Bypass -File .\nginx\gen-certs.ps1
```

**2. Configure environment** — copy/edit `.env` (see [Environment](#environment) below), then
**3. Start the stack:**

```bash
docker compose up --build
```

The API is reached through nginx at **`https://localhost`** (e.g. `https://localhost/api/login`). Plain `http://localhost` 301-redirects to HTTPS. The API container's `8080` is not published to the host — only nginx talks to it over the internal network.

> The certificate is self-signed, so clients will warn about an untrusted cert. Use `curl -k`, or trust `nginx/certs/server.crt` locally.

### Environment

Configuration is read from `.env` (consumed by both the `postgres` and `api` containers):

| Env var | Purpose |
|---------|---------|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | Credentials/name for the Postgres container |
| `DATABASE_URL` | Connection string the API uses (host `postgres` is the compose service name) |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | Admin account seeded on startup (default `admin` / `admin123`) so you can log in |
| `JWT_KEY` / `JWT_REFRESH_KEY` | 64-char hex signing keys for access / refresh tokens |
| `UPLOAD_DIR`, `MAX_IMAGE_MB`, `MAX_AUDIO_MB` | Media upload directory and per-category size caps |

Database state persists in the `pgdata` Docker volume across restarts. The schema is loaded
from `postgres/init.sql` **only when the `pgdata` volume is first created**; edits to that file
take effect after a `docker compose down -v` (which deletes the volume and its data). The admin
account is seeded by the API on each boot.

Users are keyed by a stable numeric `id` (`users.id`, the primary key); `username` is a
unique, mutable handle, and the `user_inventory` / `user_slots` / `user_students` tables
reference `users(id)`. **Endpoints reference an existing user by `user_id`** — in request
bodies (`user_id` / `target_user_id`) and the `DELETE /api/users/{id}` path — and the JWT
carries the same `user_id`. `username` is used only where a name is defined or authenticated:
`POST /api/login`, `POST /api/register`, and `POST /api/users/username` (rename). The `id` is
**read-only**: it is returned in user objects (e.g. `GET /api/users`) but is server-assigned
and accepted by no request body. Because everything references the `id`, renaming a user
(which changes only the `username` column) leaves their items, slots, roster, **and existing
access / refresh tokens** all valid — no re-login required.

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
| `GET /api/users` | Bearer | List all users (username, role, building, profile picture, student roster) |
| `GET /api/users/{username}` | Bearer | Look up a single user by username (resolve their `id`) |
| `POST /api/users/pfp` | Bearer (self or > Student) | Set a user's profile-picture link (empty `profile_pic_url` clears it) |
| `POST /api/users/building` | Bearer | Set the caller's own building (`building_id` `0` clears it) |
| `POST /api/users/username` | Bearer | Rename the caller's own account (existing tokens stay valid) |
| `POST /api/users/password` | Bearer | Change the caller's own password (must supply the current one) |
| `POST /api/users/students` | Bearer (> Student) | Replace a user's student roster by a given list; returns a `207` per-id result |
| `DELETE /api/users/{id}` | Bearer (> Student) | Delete a user by id (cannot delete yourself) |
| `POST /api/building` | Bearer (> Student) | Create a building |
| `GET /api/building` | Bearer | List all buildings |
| `GET /api/building/{id}` | Bearer | Read a building by ID |
| `PUT /api/building/{id}` | Bearer (> Student) | Replace a building by ID |
| `POST /api/student` | Bearer (> Student) | Create a student (server-assigned `student_id`) |
| `GET /api/student` | Bearer | List all students |
| `GET /api/student/{id}` | Bearer | Read a student by ID |
| `PUT /api/student/{id}` | Bearer (> Student, or a student assigned to the caller) | Replace a student by ID |
| `DELETE /api/student/{id}` | Bearer (> Student) | Delete a student (cascades: removed from every user's roster) |
| `POST /api/item` | Bearer | Read all of a user's items (inventory + slots) |
| `POST /api/item/inv2slot` | Bearer (not Student in QUIZ2) | Move one item from inventory into a slot (swaps out any normal item already there) |
| `POST /api/item/slot2inv` | Bearer (not Student in QUIZ2) | Return a slotted item to the inventory |
| `POST /api/question/generate` | Bearer (QUIZ1) | Roll a new item + open a session to claim it (students QUIZ1-only) |
| `POST /api/question/target` | Bearer (QUIZ2) | Open an attack/repair session against a user's slot (students QUIZ2-only) |
| `POST /api/question/answer` | Bearer | Answer the held session: grant item, or break/repair the target |
| `POST /api/question/upload` | Bearer (> Student) | Bulk-add questions to the pool; returns a `207` per-question result list |
| `GET /api/question/search` | Bearer (> Student) | List the question pool, optionally filtered by difficulty/area |
| `GET /api/question/{id}` | Bearer | Fetch a single pooled question by ID |
| `PUT /api/question/{id}` | Bearer (> Student) | Update a pooled question by ID |
| `DELETE /api/question/{id}` | Bearer (> Student) | Delete a pooled question by ID |
| `POST /api/image` | Bearer | Upload an image; returns the URL it is served at |
| `POST /api/audio` | Bearer | Upload an audio file; returns the URL it is served at |
| `GET /api/state` | Bearer | Read the current server state (`NORMAL` / `QUIZ1` / `QUIZ2`) |
| `POST /api/state` | Bearer (> Student) | Transition the server state |
| `GET /api/state/ws` | Bearer or `?access_token=` | WebSocket; pushes the current state on connect and on every state transition |

---

## Authentication

### `POST /api/login`

Authenticate with username and password.

**Request**

```json
{
  "username": "admin",
  "password": "admin123"
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
**Admins cannot be created via this endpoint**. A new user starts with no building —
use `POST /api/users/building` to assign one later.

Requires a valid access token:

```
Authorization: Bearer <access_token>
```

**Request** — `role` is `0` (Student) or `1` (Teacher)

```json
{
  "username": "alice",
  "password": "password123",
  "role": 0
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

## Users

Each user directly owns their game state: a `building_id` (`0` means **no building**),
plus an inventory and slots (see [Inventory](#inventory)) and a **student roster** — the set
of [student](#students) IDs assigned to them (see
[`POST /api/users/students`](#post-apiusersstudents)). `GET /api/users` lists every account;
the other user endpoints set a user's picture, building, or student roster, or delete an account.

All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `GET /api/users`

List all users. Any authenticated user may call it.

**Response `200 OK`** — `building_id` is `0` for users with no building;
`profile_pic_url` is empty when no picture is set; `students` is the assigned student
roster (ascending `student_id` order, empty when none)

```json
{
  "users": [
    { "id": 1, "username": "admin", "role": 2, "building_id": 1, "profile_pic_url": "/images/abc.jpg", "students": [1, 2] },
    { "id": 2, "username": "alice", "role": 0, "building_id": 0, "profile_pic_url": "", "students": [] }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `GET /api/users/{username}`

Look up a single user by username. Any authenticated user may call it. This is the
cheap way to resolve a username to its numeric `id` (which the rest of the API uses
in request bodies) without listing every user via `GET /api/users`.

**Response `200 OK`** — the same user object as in the list:

```json
{ "id": 2, "username": "alice", "role": 0, "building_id": 0, "profile_pic_url": "", "students": [] }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | No user with that `username` |

---

### `POST /api/users/pfp`

Set a user's profile-picture link. A user may set **their own** picture; a
**Teacher / Admin** may set **any** user's. `user_id` is optional — when omitted,
it targets the caller. An empty `profile_pic_url` clears the picture. The link
is stored and returned verbatim (typically a URL returned by `POST /api/image`).

**Request**

```json
{ "user_id": 2, "profile_pic_url": "/images/abc.jpg" }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller targets another user but is not a Teacher/Admin |
| `404`  | The target `user_id` does not exist |

---

### `POST /api/users/building`

Set **the calling user's own** building. A `building_id` of `0` clears the
assignment. The building drives item generation and the slot type rules (see
[Buildings](#buildings) and [Inventory](#inventory)).

**Request** — `building_id` is required (`0` = none)

```json
{ "building_id": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `building_id` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `POST /api/users/students`

Replace a target user's **student roster** with the given list of `student_id`s.
**Teachers and Admins only.** `user_id` is **required** (the target user). The set is a
**full replace**: the roster becomes exactly the valid ids from `student_ids`.

Each id is checked against the [students](#students) table: known ids are assigned, unknown
ids are reported and **skipped**. The response is therefore always a **`207 Multi-Status`**
carrying one result per submitted id (duplicates are collapsed).

**Request**

```json
{ "user_id": 2, "student_ids": [1, 2, 999] }
```

**Response `207 Multi-Status`** — each result's `status` is `200` for an assigned student
or `404` for an unknown one (with an `error`)

```json
{
  "results": [
    { "student_id": 1, "status": 200 },
    { "student_id": 2, "status": 200 },
    { "student_id": 999, "status": 404, "error": "學生不存在" }
  ]
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `user_id` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | The target `user_id` does not exist |

---

### `POST /api/users/username`

Rename **the calling user's own** account. The new `username` must not already be taken.
Only the `username` changes; the account's numeric `id` is stable, so everything keyed by it
(inventory, slots, student roster) is unaffected. Tokens carry that `id`, so the caller's
existing access/refresh tokens **remain valid** — no re-login is required.

**Request**

```json
{ "username": "new_name" }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `username` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `409`  | The requested `username` is already taken |

---

### `POST /api/users/password`

Change **the calling user's own** password. The current password must be supplied and
correct (a valid token alone is not sufficient).

**Request**

```json
{ "old_password": "current-secret", "new_password": "new-secret" }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `old_password` / `new_password` |
| `401`  | Missing/malformed `Authorization` header, an invalid/expired access token, or a wrong current password |

---

### `DELETE /api/users/{id}`

Delete a user account by its numeric id. **Teachers and Admins only.** A caller
cannot delete the account they are authenticated as.

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A missing or non-numeric `{id}` in the path |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower, or the caller is deleting their own account |
| `404`  | The target `id` does not exist |

---

## Buildings

A **building** is a named layout that users can be assigned to (see
[`POST /api/users/building`](#post-apiusersbuilding)). Each building has:

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

### `PUT /api/building/{id}`

Replace an existing building. **Teachers and Admins only.** The request body has the
same shape as [`POST /api/building`](#post-apibuilding) and is a **full replace**: every
field is overwritten, so omitted `layout`, `item_allowed_slot`, and `difficulty_type`
values are cleared (read back as empty). `name` is required.

**Request**

```json
{
  "name": "Library",
  "layout": "{\"w\":4,\"h\":2}",
  "item_allowed_slot": { "10": [0, 2], "20": [1] },
  "difficulty_type": { "1": [10, 30], "2": [20] }
}
```

**Response `200 OK`** — the updated building

```json
{
  "building_id": 1,
  "name": "Library",
  "layout": "{\"w\":4,\"h\":2}",
  "item_allowed_slot": { "10": [0, 2], "20": [1] },
  "difficulty_type": { "1": [10, 30], "2": [20] }
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}`, malformed JSON body, or a missing `name` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | No building with that `id` |

---

## Students

A **student** is a lightweight record: `{ student_id, name, profile_pic_url }`. The
`student_id` is the **server-assigned, read-only** primary key — it is allocated by the
database on create and is **not** accepted as input. `profile_pic_url` is an image link
(typically a URL returned by [`POST /api/image`](#post-apiimage--post-apiaudio)),
stored and returned verbatim; empty means no picture.

Students are assigned to users via each user's [roster](#post-apiusersstudents). Deleting a
student **cascades**: its id is removed from every user's roster.

Create, update, and delete are **Teacher/Admin only**; any authenticated user may read.
All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `POST /api/student`

Create a student. **Teachers and Admins only.** `name` is required; `profile_pic_url`
is optional. The `student_id` is **server-assigned** and returned in the response (any
`student_id` sent in the body is ignored).

**Request**

```json
{ "name": "Alice", "profile_pic_url": "/images/abc.jpg" }
```

**Response `200 OK`** — the created student, including its new `student_id`

```json
{ "student_id": 1, "name": "Alice", "profile_pic_url": "/images/abc.jpg" }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `name` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `GET /api/student`

List every student. Any authenticated user may call it.

**Response `200 OK`** — a JSON array of students

```json
[
  { "student_id": 1, "name": "Alice", "profile_pic_url": "/images/abc.jpg" },
  { "student_id": 2, "name": "Bob", "profile_pic_url": "" }
]
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |

---

### `GET /api/student/{id}`

Read a single student by ID. Any authenticated user may call it.

**Response `200 OK`**

```json
{ "student_id": 1, "name": "Alice", "profile_pic_url": "/images/abc.jpg" }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | No student with that `id` |

---

### `PUT /api/student/{id}`

Replace an existing student. **Teachers and Admins, or a Student-role caller updating a
student in their own [roster](#post-apiusersstudents).** The body is a **full replace**
of `name` and `profile_pic_url` (`student_id` is taken from the path, not the body);
`name` is required.

**Request**

```json
{ "name": "Alice", "profile_pic_url": "/images/new.jpg" }
```

**Response `200 OK`** — the updated student

```json
{ "student_id": 1, "name": "Alice", "profile_pic_url": "/images/new.jpg" }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}`, malformed JSON body, or a missing `name` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower and the `id` is not in their roster |
| `404`  | No student with that `id` |

---

### `DELETE /api/student/{id}`

Delete a student. **Teachers and Admins only.** The deletion **cascades**: the `id` is
also removed from every user's [student roster](#post-apiusersstudents).

**Response `200 OK`**

```json
{ "deleted": true }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |
| `404`  | No student with that `id` |

---

## Inventory

Items are **unique instances** stored in an internal `items` table — each is
`{ item_id, type, question_id }`, where `type` ties it to a building's
[`item_allowed_slot` / `difficulty_type`](#buildings) and `question_id` links it to a
pooled question (`0` = none). The items table is managed **internally** (no public
create/list API). *(An item with nothing referencing it should eventually be garbage
collected; that cleanup is a TODO, not yet implemented.)*

A user owns a set of these items, split between:

- **inventory** — the item IDs the user holds loose (not placed), and
- **slots** — `slot_id → item`, where each slot holds at most one item.

Inventory and slots are **disjoint**: an item is either loose in the inventory or sitting
in a slot, never both. Items move between them:

- `inv2slot` takes an owned item out of the inventory and places it in a slot.
- `slot2inv` returns a slotted item to the inventory and clears the slot.

**Broken items** — a slot can hold a *broken* item, surfaced as `"broken": true` in the
slot view. A broken item cannot be returned to the inventory or replaced.

**QUIZ2-state restriction** — the two *move* endpoints (`inv2slot` and `slot2inv`)
are disabled for **students** while the server is in `QUIZ2` state (they get
`403`); Teachers and Admins are unaffected. The read endpoint (`POST /api/item`)
is always available. (This is the inverse of the `target` question endpoint, which
students may use *only* during `QUIZ2`.)

All inventory endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

Every request body carries a `user_id` identifying whose board to act on (it must be
present and non-zero); the relevant `item_id` / `slot_id` fields are listed per endpoint below.

### `POST /api/item`

Return **all** of a user's items: their `inventory` (an array of items) and their `slots`
(`slot_id → item`).

**Visibility** — a **student** sees the full `item_id` / `type` / `question_id` only when
querying **their own** board; for any other user they see **only `type`** (the
`item_id` and `question_id` fields are omitted). **Teachers and Admins** always see the
full fields.

**Request**

```json
{ "user_id": 2 }
```

**Response `200 OK`** (full view — own board, or teacher/admin)

```json
{
  "user_id": 2,
  "inventory": [
    { "item_id": 1, "type": 10, "question_id": 1 },
    { "item_id": 2, "type": 20, "question_id": 2 }
  ],
  "slots": {
    "0": { "item_id": 3, "type": 10, "question_id": 1, "broken": false }
  }
}
```

**Response `200 OK`** (restricted view — a student querying another user): only `type`
is exposed per item.

```json
{
  "user_id": 2,
  "inventory": [ { "type": 10 }, { "type": 20 } ],
  "slots": { "0": { "type": 10, "broken": false } }
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a missing `user_id` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | The queried `user_id` does not exist |

---

### `POST /api/item/inv2slot`

Move the owned item `item_id` from the user's inventory into `slot_id`. The item's
**Type must be allowed in that slot** by the user's building (the building's
`item_allowed_slot`); otherwise the move is rejected. The destination slot may already
hold a **normal** item — it is **swapped** back into the inventory before the new item is
placed. A slot holding a **broken** item cannot be replaced. A caller may only move items
on **their own** board.

**Request**

```json
{ "user_id": 2, "item_id": 1, "slot_id": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | `item_id` is not in the user's inventory |
| `400`  | The item's `type` is not allowed in `slot_id` by the user's building |
| `400`  | The destination slot holds a **broken** item (已損毀) and cannot be replaced |
| `403`  | The `user_id` is not the caller's own, or a **student** caller while the server is in `QUIZ2` state |

---

### `POST /api/item/slot2inv`

Return the item held in `slot_id` to the user's inventory and clear the slot. Only a
**normal** item can be returned — a **broken** item cannot be moved back. A caller may
only move items on **their own** board.

**Request**

```json
{ "user_id": 2, "slot_id": 1 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | The slot does not exist, is empty, or holds a **broken** item (已損毀) |
| `403`  | The `user_id` is not the caller's own, or a **student** caller while the server is in `QUIZ2` state |

---

**Error responses common to all inventory endpoints**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body; a required field (`item_id` / `slot_id`) is missing; `user_id` is missing or zero; or (for `inv2slot`) `item_id` is not greater than 0 |
| `401`  | Missing or malformed `Authorization` header, or an invalid/expired access token |

---

## Questions

The quiz drives the game loop. A **generate** endpoint opens a **single-use session**
(15 min TTL); the shared **answer** endpoint consumes it and acts on the session's kind.
There are two generate endpoints, gated by the server state:

- **`POST /api/question/generate`** (QUIZ1) — *earn an item*. Creates a brand-new item of a
  random type (drawn from the caller's building `difficulty_type` for the requested
  difficulty) tied to a random `area 1` question of that difficulty. Answering **correctly**
  adds the item to the caller's inventory.
- **`POST /api/question/target`** (QUIZ2) — *attack / repair*. Targets a user's slot.
  Answering **correctly** breaks another user's slotted item or repairs your own broken one.

The caller is identified by their token; generating an item requires the caller to have a
building assigned. The graded answer is never leaked in the generate response.

### Server state machine

The server holds a single global state — one of `NORMAL` (default), `QUIZ1`, or `QUIZ2`.
Students are restricted by the current state; **Teachers and Admins bypass the state gate**:

| Endpoint | Student may call in | Teacher / Admin |
|----------|---------------------|-----------------|
| `POST /api/question/generate` (item) | `QUIZ1` only | any state |
| `POST /api/question/target` (attack/repair) | `QUIZ2` only | any state |
| `POST /api/question/answer` | any state | any state |
| `POST /api/item/inv2slot`, `POST /api/item/slot2inv` (move) | any state **except** `QUIZ2` | any state |

In short: `QUIZ1` is the item-earning phase in which students may also move items, `QUIZ2`
is the attack/repair phase (and locks students out of moving items), and `NORMAL` is the
default idle phase in which students may move items but can neither generate nor target.

Read the state with `GET /api/state`; transition it with `POST /api/state`
(Teacher / Admin only). All endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

### `POST /api/question/generate` — earn an item (QUIZ1)

Roll a new item for the requested `difficulty` and open a session to claim it.

**Request**

```json
{ "difficulty": 1 }
```

**Response `200 OK`** — the question `content` and its session id (the answer is never returned). For a multiple-choice question `content.choices` carries the options; for a `voice_response` question `choices` is omitted.

```json
{
  "session": "0123456789abcdef0123456789abcdef",
  "content": {
    "description": { "type": "text", "data": "What is six times three?" },
    "choices": { "type": "text", "data": ["6", "18", "9", "12"] }
  }
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body or missing `difficulty`; the caller has no building; the building lists no type for the difficulty; or no `area 1` question matches the difficulty |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is not in `QUIZ1` state |

---

### `POST /api/question/target` — attack / repair (QUIZ2)

Open a session against `target_slot_id` on `target_user_id`'s board. **Valid** only when:

- **attack** — the target is **another** user and their slot item is **not broken**; the
  graded question is that item's own question, and a correct answer **breaks** it; or
- **repair** — the target is the caller's **own** board and the slot item **is broken**; the
  graded question is a random `area 2` question, and a correct answer **repairs** it.

**Request**

```json
{ "target_user_id": 2, "target_slot_id": 0 }
```

**Response `200 OK`** — `{ "session", "content" }`, same shape as above.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body; `target_user_id` missing; `target_slot_id` missing; the target slot is empty; the target item has no question; or the target is invalid (own non-broken slot, or another user's broken slot) |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller is a Student and the server is not in `QUIZ2` state |
| `404`  | `target_user_id` does not exist |

---

### `POST /api/question/answer`

Answer the held session. The session is **deleted on use** and the action depends on
its kind. The shape of `answer` depends on the question's answer type:

- **index** questions — `answer` is the zero-based index of the chosen option (a single
  number). It is graded correct if it is one of the question's accepted indexes.
- **voice_response** questions — `answer` is the student's recorded answer: a WAV audio
  file, base64-encoded into a string. The server transcribes it (via a speech-to-text
  backend) and grades it correct if the transcript matches, case-insensitively, **any** of
  the question's accepted transcripts.

The student always submits a single value; the question's correct answer is a **set**
(see the upload format below), and a submission passes if it matches at least one member.

**Request** — multiple choice

```json
{ "session": "0123456789abcdef0123456789abcdef", "answer": 1 }
```

**Request** — voice response (`answer` is base64-encoded WAV audio)

```json
{ "session": "0123456789abcdef0123456789abcdef", "answer": "UklGRiQAAABXQVZF..." }
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
| `404`  | The session's owner no longer exists (e.g. deleted mid-session) — item not granted |

---

### Question pool management

The questions handed out by `generate` are drawn from a shared **question pool**.
Teachers and Admins manage this pool: bulk-upload new questions, search existing
ones, and update or delete them by ID. All four endpoints require a valid access
token and a role above Student — Students receive `403`.

Each question is `{ content, answer, difficulty, area }`:

- `content.description` is `{ type, data }`, where `type` is one of `text`, `audio`, or
  `voice_response`. `data` is the prompt text for `text`, or a URL for `audio` /
  `voice_response`.
- `content.choices` is `{ type, data }`, present for multiple-choice questions and omitted
  for `voice_response`. `type` is `text` (then `data` is a list of option strings) or
  `audio` (then `data` is a list of audio URLs, e.g. uploaded via `POST /api/audio`).
- `answer` is `{ type, data }`, where `data` is always a non-empty **array** (a set of
  accepted answers): for `type` `index`, an array of zero-based correct-choice indexes
  (numbers); for `type` `voice_response`, an array of accepted transcripts (strings). A
  student's single submission is graded correct if it matches any member.
- `difficulty` and `area` are `uint` classifiers (default `0`): they drive which question
  the generate endpoints draw (item → `area 1` + the requested difficulty; repair →
  `area 2`) and also filter [search](#get-apiquestionsearch).

Validation accepts only the type values listed above, requires a non-empty
`description.data`, and requires `answer.data` to be a non-empty array of the type its
`answer.type` implies.

```
Authorization: Bearer <access_token>
```

### `POST /api/question/upload`

Add a batch of questions in a single request. Invalid questions (unknown type values,
an empty `description.data`, or an `answer.data` that is not a non-empty array) are
skipped rather than failing the whole batch, so the
response is a **`207 Multi-Status`** carrying one result per submitted question, in
request order.

**Request**

`difficulty` and `area` are optional per question (default `0`).

```json
{
  "questions": [
    {
      "content": {
        "description": { "type": "text", "data": "2+2?" },
        "choices": { "type": "text", "data": ["3", "4"] }
      },
      "answer": { "type": "index", "data": [1, 3] },
      "difficulty": 1,
      "area": 2
    },
    {
      "content": { "description": { "type": "text", "data": "" } },
      "answer": { "type": "index", "data": [0] }
    },
    {
      "content": { "description": { "type": "audio", "data": "https://example.com/audio/q.mp3" } },
      "answer": { "type": "voice_response", "data": ["eighteen", "18"] }
    }
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

List the pool. With no parameters it returns every question.

The optional `difficulty` and `area` query parameters filter by **exact match**
(`uint`); each is applied only when present, and combined as a logical **AND**.

**Request** — query parameters

```
GET /api/question/search?difficulty=1&area=2
```

| Parameter | Description |
|-----------|-------------|
| `difficulty` | Exact `difficulty` to match; omitted = not filtered |
| `area`       | Exact `area` to match; omitted = not filtered |

**Response `200 OK`** — matches in ascending `id` order; the answer is included
(teacher-facing)

```json
{
  "questions": [
    {
      "id": 4,
      "content": {
        "description": { "type": "text", "data": "Capital of France?" },
        "choices": { "type": "text", "data": ["Paris", "Rome"] }
      },
      "answer": { "type": "index", "data": [0] },
      "difficulty": 1,
      "area": 2
    }
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

### `GET /api/question/{id}`

Fetch a single pooled question by `id`. Open to **any** authenticated user (no role
restriction); the response is the same teacher-facing record as `search` and **includes
the answer**.

**Request** — no body

```
GET /api/question/1
```

**Response `200 OK`** — the full `{ id, content, answer, difficulty, area }` record

```json
{
  "id": 1,
  "content": {
    "description": { "type": "text", "data": "What is six times three?" },
    "choices": { "type": "text", "data": ["6", "18", "9", "12"] }
  },
  "answer": { "type": "index", "data": [1] },
  "difficulty": 1,
  "area": 1
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | A non-numeric `{id}` |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `404`  | No question with that `id` |

---

### `PUT /api/question/{id}`

Overwrite the pooled question with the given `id`. `difficulty` and `area` are
optional (default `0`).

**Request**

```json
{
  "content": {
    "description": { "type": "text", "data": "2+2?" },
    "choices": { "type": "text", "data": ["3", "4"] }
  },
  "answer": { "type": "index", "data": [1] },
  "difficulty": 1,
  "area": 2
}
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a non-numeric `{id}`, an unknown type value, or an empty `description.data` |
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

Read the current server state. `updated_at` is the RFC 3339 timestamp of the last
state change (the server start time for the initial `NORMAL`). `end_time`, when
present, is the RFC 3339 time at which the state will automatically revert to
`NORMAL`; it is omitted when no auto-revert is scheduled.

**Response `200 OK`**

```json
{ "state": "NORMAL", "updated_at": "2026-06-15T09:30:00Z" }
```

---

### `POST /api/state`

Transition the server state to one of `NORMAL`, `QUIZ1`, or `QUIZ2`. Only Teachers and
Admins may call it.

An optional `end_time` (RFC 3339) schedules an **automatic revert to `NORMAL`** once
that time passes — a background poller checks it about once a second. The end time
must be in the future, and is ignored when the target state is `NORMAL`. Each
request **overwrites** any previous schedule: omitting `end_time` (or setting
`NORMAL`) clears it.

**Request**

```json
{ "state": "QUIZ2", "end_time": "2026-06-15T10:00:00Z" }
```

**Response `200 OK`** — echoes the new state, the `updated_at` it was set at, and the
scheduled `end_time` (omitted when none)

```json
{ "state": "QUIZ2", "updated_at": "2026-06-15T09:30:00Z", "end_time": "2026-06-15T10:00:00Z" }
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, a missing `state`, a state other than `NORMAL` / `QUIZ1` / `QUIZ2`, or an `end_time` that is not in the future |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `403`  | Caller's role is Student or lower |

---

### `GET /api/state/ws`

Subscribe to server-state changes over a WebSocket. Any authenticated user may
subscribe (same access policy as `GET /api/state`). On connect the server sends
the current state immediately, then pushes a message on every state transition.

Because browsers cannot set headers on a WebSocket handshake, the access token
may be supplied either way:

- `Authorization: Bearer <access_token>` header, or
- `?access_token=<access_token>` query parameter.

**Messages** — each frame is JSON, identical in shape to `GET /api/state`:

```json
{ "state": "QUIZ2", "updated_at": "2026-06-15T09:30:00Z" }
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

## Media uploads

Authenticated users can upload **images** and **audio files**. Each upload is stored
on disk under a random name and the response carries the URL it can be fetched from.
Uploaded files are served as **static files** — `/images/<filename>` for images and
`/audio/<filename>` for audio — and do not pass back through the API on read (in the
Docker Compose stack, nginx serves them directly off a volume shared with the API).

Both endpoints take a `multipart/form-data` body with a single **`file`** field and
require a valid access token:

```
Authorization: Bearer <access_token>
```

The stored file's type is determined by **sniffing its content**, not by trusting the
client-supplied name. For audio — where content sniffing is unreliable (e.g. a tag-less
MP3) — the original filename extension is used as a fallback only when the content is
otherwise unrecognized.

| Category | Endpoint | Accepted formats | Default size cap | Served at |
|----------|----------|------------------|------------------|-----------|
| Image | `POST /api/image` | JPEG, PNG, GIF, WebP | 10 MiB | `/images/<filename>` |
| Audio | `POST /api/audio` | MP3, WAV, OGG, AIFF, M4A, AAC, FLAC | 25 MiB | `/audio/<filename>` |

### `POST /api/image` · `POST /api/audio`

Upload a single file. The request is `multipart/form-data` with the file in the `file`
field; everything else (storage path, generated name, served URL) is handled by the server.

**Request**

```
POST /api/image
Authorization: Bearer <access_token>
Content-Type: multipart/form-data; boundary=...

file=<binary file data>
```

**Response `201 Created`** — `url` is the path the file is served at

```json
{
  "filename": "9f86d081884c7d659a2feaa0c55ad015.jpg",
  "url": "/images/9f86d081884c7d659a2feaa0c55ad015.jpg"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Missing `file` field, or the upload could not be read (including a body far exceeding the cap) |
| `401`  | Missing/malformed `Authorization` header, or an invalid/expired access token |
| `413`  | The file exceeds the category's size cap |
| `415`  | The file is not an accepted image / audio format |

### Configuration

The upload directory and per-category size caps are configurable via environment variables:

| Env var | Default | Description |
|---------|---------|-------------|
| `UPLOAD_DIR` | `/srv/uploads` | Directory uploads are written to (under `images/` and `audio/` subdirs); in Compose this is a volume shared with nginx |
| `MAX_IMAGE_MB` | `10` | Maximum image upload size, in MiB |
| `MAX_AUDIO_MB` | `25` | Maximum audio upload size, in MiB |

> When raising `MAX_AUDIO_MB`, also bump `client_max_body_size` in
> `nginx/conf.d/default.conf` so nginx does not reject the larger body before it
> reaches the API.

---

## Token reference

| Token | TTL | Signing key env var | Notes |
|-------|-----|---------------------|-------|
| Access | 15 minutes | `JWT_KEY` | Sent in `Authorization` header |
| Refresh | 7 days | `JWT_REFRESH_KEY` | Single-use; rotated on every `/api/refresh` call |

> **Note:** Signing keys are currently hardcoded constants. Replace with environment variables before deploying to production.
