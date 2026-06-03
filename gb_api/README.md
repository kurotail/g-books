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

GET  /api/dashboard          ← Authorization: Bearer <access_token>

POST /api/refresh            ← { "refresh_token": "..." }
  → new access_token
  → new refresh_token        (old token is invalidated immediately)
```

Refresh tokens are single-use. Using the same refresh token twice returns `401`.

---

## Endpoints

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

### `GET /api/dashboard`

Protected resource. Requires a valid access token.

**Request header**

```
Authorization: Bearer <access_token>
```

**Response `200 OK`**

```json
{
  "message": "恭喜！您已成功通過 JWT 驗證，並讀取了受保護的資料庫內容。"
}
```

**Error responses**

| Status | Condition |
|--------|-----------|
| `401`  | Missing, expired, or invalid token; refresh token used instead of access token |

---

## Token reference

| Token | TTL | Signing key env var | Notes |
|-------|-----|---------------------|-------|
| Access | 15 minutes | `JWT_KEY` | Sent in `Authorization` header |
| Refresh | 7 days | `JWT_REFRESH_KEY` | Single-use; rotated on every `/api/refresh` call |

> **Note:** Signing keys are currently hardcoded constants. Replace with environment variables before deploying to production.
