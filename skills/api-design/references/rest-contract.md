# REST contract skeleton: error envelope, cursor pagination, idempotent create

Framework-agnostic, shown as HTTP exchanges. The three shapes below cover the
contract decisions that are hardest to change after clients exist.

## Error envelope (RFC 9457 Problem Details)

Every non-2xx response uses the same shape, with `Content-Type: application/problem+json`:

```json
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "2 fields failed validation",
  "errors": [
    { "field": "email", "message": "must be a valid email address" },
    { "field": "plan",  "message": "must be one of: free, pro, team" }
  ]
}
```

Rules: `type` is a stable, documentable identifier (clients switch on it, not on
`detail` text); `detail` is human-readable and safe to display; nothing in the body
reveals stack traces, queries, or internal IDs.

## Cursor pagination

```
GET /v1/orders?limit=50&cursor=eyJpZCI6IDQyMTd9

HTTP/1.1 200 OK
{
  "data": [ ... up to 50 orders ... ],
  "next_cursor": "eyJpZCI6IDQyNjd9",
  "has_more": true
}
```

Rules: the cursor is opaque to clients (encode the sort key server-side; never accept
raw offsets); `limit` has a server-enforced max (e.g. 100); a stable total sort order
(usually `created_at, id` tiebreak) prevents skips and duplicates under concurrent
writes; `next_cursor` is `null` on the last page.

## Idempotent create

```
POST /v1/payments
Idempotency-Key: 7f9c2b4a-0d31-4f6e-9a8e-3c5d1e2f4a6b

{ "amount_cents": 4999, "currency": "usd", "source": "tok_visa" }
```

Server behavior:

1. On first sight of the key: store `(key, request_hash)` before doing work, perform
   the create, store the response against the key.
2. On replay with the **same** key and same request hash: return the stored response
   (same status code and body) without re-executing.
3. On replay with the same key but a **different** body: return `409 Conflict` — the
   client has a bug.
4. Expire stored keys after a documented window (24 h is a common default).

## Status-code quick reference

| Situation | Code |
|---|---|
| Validation failure on a well-formed request | 422 |
| Malformed body / unparseable JSON | 400 |
| Missing or invalid credentials | 401 |
| Authenticated but not allowed (object-level) | 403 or 404 (404 if existence itself is sensitive) |
| Idempotency-key reuse with different body | 409 |
| Rate limited | 429 + `Retry-After` |
| Unhandled server error | 500 (envelope, no internals) |
