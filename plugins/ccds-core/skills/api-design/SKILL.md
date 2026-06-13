---
name: api-design
description: API design and implementation specialist. Auto-invoked when writing HTTP endpoints, REST or GraphQL APIs, authentication flows, API clients, webhooks, or defining data contracts between services.
---

# API Design

An API contract outlives its implementation: clients are written against whatever
ships first, and every inconsistency becomes someone else's permanent workaround.

## When to reach for this

- Designing or reviewing HTTP/REST, GraphQL, or gRPC endpoints and their schemas
- Adding authentication or authorization to routes (OAuth2, JWT, API keys, mTLS)
- Defining error shapes, pagination, versioning, or webhook payload contracts
- Writing an API client and deciding its retry and idempotency behavior

## Principles

1. **Contract first.** Define routes, methods, schemas, error codes, and pagination
   before writing implementation code — the contract is what clients code against.
2. **Validate at the boundary.** All external input is validated and sanitized before
   it reaches business logic; reject unknown fields to block mass assignment.
3. **Errors are structured and consistent.** One error envelope across the whole API
   (RFC 9457 Problem Details is a solid default); never leak stack traces, SQL, or
   internal identifiers in error responses.
4. **Least privilege per endpoint.** Return only the fields the caller is authorized
   to see; authorization must be object-level ("their own resources"), not just
   route-level.
5. **Mutations are retryable.** Accept an `Idempotency-Key` header (or design natural
   idempotency) on POSTs that create or charge — clients *will* retry on timeout.
6. **Paginate every list endpoint from day one.** Cursor-based by default; offset
   pagination skips or duplicates rows under concurrent writes.
7. **Version deliberately.** Additive changes are free; renames, type changes, and
   removals require a new version and a deprecation window.
8. **Document as you go.** Every endpoint ships with description, request params,
   response schema, and error codes — usually as OpenAPI kept next to the code.

## Review checklist

- [ ] Input validation present and complete (including unknown-field rejection)
- [ ] Authentication enforced on all non-public routes
- [ ] Object-level authorization (user can only access their own resources)
- [ ] No sensitive data (secrets, PII) in logs or error responses
- [ ] Consistent HTTP status codes (4xx caller fault, 5xx server fault; 429 carries `Retry-After`)
- [ ] Rate limiting considered
- [ ] Pagination on list endpoints
- [ ] OpenAPI/schema documentation updated

A worked contract skeleton (error envelope, cursor pagination, idempotent create) is
in [`references/rest-contract.md`](references/rest-contract.md).

## Pitfalls

- Route-level auth without object-level checks — the classic IDOR
- `200 OK` responses carrying `{ "error": ... }` bodies, which break client error
  handling and retry logic
- Offset pagination on hot tables (rows shift under the reader)
- Webhook receive endpoints that trust payloads without signature verification
- Breaking changes shipped as "minor": renamed fields, tightened types, removed enum
  values
- Validation done twice differently (client and server disagree on what's legal)

---
*Related: `security-checklist` (auth/injection self-check), `ux-design`
(developer-facing ergonomics), `common-privacy` (PII in contracts) · pulled by any
domain agent · output/ADR format: `playbook-conventions`*
