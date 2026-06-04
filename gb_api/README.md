# gb-api

REST API server for g-books, built with Go's standard `net/http` library and JWT-based authentication.

- **Runtime:** Go 1.24+
- **Port:** `8080`
- **Auth scheme:** JWT (HS256) — short-lived access tokens + single-use rotating refresh tokens

---

## Run

```bash
go run ./cmd/server
```

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
| `POST /api/refresh` | — | Rotate a refresh token into a new token pair |
| `POST /api/item/inv` | Bearer | Read a group's inventory |
| `POST /api/item/slot` | Bearer | Read a group's slots |
| `POST /api/item/inv2slot` | Bearer | Move one item from inventory into a slot |
| `POST /api/item/slot2inv` | Bearer | Return a slotted item to the inventory |

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
| `400`  | Malformed JSON body |
| `401`  | Wrong username or password |

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

## Inventory

A group owns an **inventory** — a map of `item_id → quantity` — and a set of **slots**,
where each `slot_id` holds at most one `item_id`. Items move between the two:

- `inv2slot` takes one unit of an item out of the inventory and places it in a slot.
- `slot2inv` returns a slotted item to the inventory and clears the slot.

All inventory endpoints require a valid access token:

```
Authorization: Bearer <access_token>
```

Every request body carries a `group_id`; the relevant `item_id` / `slot_id` fields
are listed per endpoint below.

### `POST /api/item/inv`

Return the group's inventory.

**Request**

```json
{ "group_id": 0 }
```

**Response `200 OK`** — map of `item_id → quantity`

```json
{ "1": 3, "2": 1 }
```

---

### `POST /api/item/slot`

Return the group's slots.

**Request**

```json
{ "group_id": 0 }
```

**Response `200 OK`** — map of `slot_id → item_id`

```json
{ "0": 1 }
```

---

### `POST /api/item/inv2slot`

Move one unit of `item_id` from the inventory into `slot_id`. The inventory count is
decremented by one (and the item removed when it reaches zero); the slot is set to the item.

**Request**

```json
{ "group_id": 0, "item_id": 1, "slot_id": 5 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | Insufficient stock — the item's inventory count would drop below zero |

---

### `POST /api/item/slot2inv`

Return the item held in `slot_id` to the inventory. The inventory count is incremented by
one and the slot is cleared.

**Request**

```json
{ "group_id": 0, "slot_id": 5 }
```

**Response** — `200 OK` with an empty body on success.

**Error responses**

| Status | Condition |
|--------|-----------|
| `400`  | The slot does not exist |

---

**Error responses common to all inventory endpoints**

| Status | Condition |
|--------|-----------|
| `400`  | Malformed JSON body, or a required field (`item_id` / `slot_id`) is missing |
| `401`  | Missing or malformed `Authorization` header, or an invalid/expired access token |

---

## Token reference

| Token | TTL | Signing key env var | Notes |
|-------|-----|---------------------|-------|
| Access | 15 minutes | `JWT_KEY` | Sent in `Authorization` header |
| Refresh | 7 days | `JWT_REFRESH_KEY` | Single-use; rotated on every `/api/refresh` call |

> **Note:** Signing keys are currently hardcoded constants. Replace with environment variables before deploying to production.
