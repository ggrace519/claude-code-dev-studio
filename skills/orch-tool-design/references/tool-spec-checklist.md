# Tool definition: worked example and quality checklist

JSON-Schema-flavored (the format used by Anthropic, OpenAI, and MCP tool
definitions); the discipline is identical regardless of provider.

## Bad → good

**Bad** — the kind of definition that gets pasted from internal API docs:

```json
{
  "name": "ticket",
  "description": "Ticket endpoint. Supports CRUD operations on the TMS.",
  "input_schema": {
    "type": "object",
    "properties": {
      "action": { "type": "string" },
      "data":   { "type": "object" }
    }
  }
}
```

Failure modes this manufactures: the model invents `action` values, stuffs
guessed field names into `data`, can't tell reads from writes, and gets a 422
it can't interpret. This is four tools wearing one name.

**Good** — one job, tight schema, coaching built in:

```json
{
  "name": "create_ticket",
  "description": "Create a NEW support ticket and return its ticket_id. Mutating; idempotent per request_id (safe to retry with the same request_id). To modify an existing ticket use update_ticket; to find tickets use search_tickets. Example: create_ticket(title=\"Login fails on Safari\", priority=\"high\", requester_email=\"a@b.com\", request_id=\"req-7f3a\")",
  "input_schema": {
    "type": "object",
    "properties": {
      "title":           { "type": "string", "maxLength": 120,
                           "description": "One-line summary, e.g. \"Login fails on Safari\"" },
      "priority":        { "type": "string", "enum": ["low", "normal", "high", "urgent"],
                           "description": "Default \"normal\". \"urgent\" pages on-call — only for outages." },
      "requester_email": { "type": "string", "format": "email" },
      "body":            { "type": "string",
                           "description": "Optional details. Plain text; markdown is not rendered." },
      "request_id":      { "type": "string",
                           "description": "Caller-generated idempotency key. Reuse on retry; new value per new ticket." }
    },
    "required": ["title", "requester_email", "request_id"]
  }
}
```

## Error catalog pattern

Return errors as structured, coaching responses — never as empty results and
never as bare codes:

| Condition | Response to the model | Retry same call? |
|---|---|---|
| Unknown `requester_email` | `{"error": "requester_not_found", "message": "No user with that email. Call search_users to find the correct address, then retry."}` | no — fix input first |
| Duplicate `request_id` | `{"ticket_id": "T-1042", "note": "already created by an earlier call"}` — success, not error | n/a (idempotent) |
| Rate limited | `{"error": "rate_limited", "message": "Retry after 30s.", "retry_after_s": 30}` | yes, after delay |
| Validation failure | name the field, the constraint, and a valid example value | no — fix input first |

## Quality checklist

**Naming and catalog**
- [ ] `verb_noun`, consistent casing across the catalog
- [ ] No sibling overlap without an explicit "use X when…, use Y when…" line in both descriptions
- [ ] Catalog reviewed when it passes ~15–20 tools: merge near-duplicates, namespace by domain, or split by agent

**Description**
- [ ] First sentence: what it does and what it returns
- [ ] States read-only vs mutating, and idempotency/retry behavior
- [ ] Names the sibling to use instead for adjacent jobs
- [ ] Contains 1–2 example calls with realistic values (real ID shapes, units)

**Schema**
- [ ] Enums for every closed value set; ranges (`minimum`/`maximum`) on numbers
- [ ] Every optional parameter documents its default
- [ ] No parameter pairs that interact invisibly (if A requires B, say so or merge them)
- [ ] Formats and units in the field description ("ISO 8601 UTC", "cents, not dollars")

**Behavior**
- [ ] Errors are structured and coaching; "not found" is distinguishable from "empty result"
- [ ] Output is bounded: pagination or truncation with an explicit "truncated, refine your query" marker
- [ ] Mutating calls accept an idempotency key, or are inherently safe to retry
- [ ] Eval cases exist for: correct selection among siblings, a hard-case argument fill, and recovery from each catalogued error
