---
name: devtool-telemetry
description: Opt-in usage telemetry, crash reports, and update pings for CLIs and libraries. Auto-invoked when designing telemetry, debating what to collect, or responding to privacy concerns from enterprise users.
---

# DevTool Telemetry

Developers are the most suspicious telemetry audience in software. One unexpected
network call, one undocumented field, one leaked path — and community trust is gone
for good. Every byte the tool sends home must be consented, documented, and scrubbed.

## When to reach for this

- Adding usage telemetry, crash reporting, or update pings to a CLI or library
- Deciding the consent model and which fields are collectable at all
- Answering an enterprise/security review about what the tool phones home
- Debugging telemetry that slows the tool or surfaces errors to users

## Principles

1. **Opt-in beats opt-out for devtools.** Prompt once on first interactive run,
   persist the answer, respect it forever — including across upgrades. Also honor
   the ambient signals: `DO_NOT_TRACK=1`, `CI=true`, and the tool's own env var all
   mean "off", no prompt.
2. **Inventory every field publicly.** Ship a `TELEMETRY.md` data dictionary: every
   event, every field, an example payload, retention period. If a field isn't in the
   doc, the tool must not send it — enforce with an allowlist schema, not review.
3. **Scrub on the client, aggressively.** Strip argv values (keep flag *names* only),
   paths under `/home`, `/Users`, `C:\Users`, env var contents, and anything matching
   token/secret patterns. The server never sees the raw data, so it can't leak it.
4. **Make disable trivial, global, and confirmed.** `NO_TELEMETRY=1`, `--no-telemetry`,
   `tool config set telemetry false`, and a system-wide file (`/etc/<tool>/config`)
   for fleet management — any one of them wins. Print a one-line confirmation.
5. **Fail silent, always.** Blocked endpoint, rate limit, DNS failure — telemetry may
   never surface an error or slow the tool. Hard timeout (~2 s), fire-and-forget or
   batch to a local spool, drop on breach. Exit must not wait on a flush.
6. **Offer the enterprise escape hatch.** Self-host endpoint override
   (`TOOL_TELEMETRY_ENDPOINT=…`), air-gap mode that never resolves DNS, and a
   compliance one-pager: what's collected, retention, access, deletion path.
7. **Make payloads inspectable.** A `--telemetry-debug` flag (or doc'd local spool
   file) that prints exactly what would be sent. "See for yourself" defuses most
   privacy threads.

## Collect / never-collect line

| Safe to collect (with consent) | Never collect |
|---|---|
| command + flag *names* used | flag/arg *values*, full argv |
| exit code, duration, tool version | cwd, file paths, file names |
| OS family, arch, CI true/false | env variable contents |
| anonymized machine ID (random UUID, rotatable) | username, hostname, IP retained server-side |
| crash stack frames from *your* code, scrubbed | user code frames, local variables, secrets |

A worked client skeleton (consent gate, allowlist schema, scrubber, fail-silent
batched transport) is in [`references/telemetry-client.md`](references/telemetry-client.md).

## Pitfalls

- Phoning home before consent is established (the first-run prompt itself must not send)
- Update check that blocks startup when the network is down or slow
- Crash reporter uploading raw stack traces containing home-dir paths or argv
- "Anonymous" machine ID derived from MAC/hostname — that's a stable identifier, not anonymous
- Honoring the opt-out for events but not for the update ping or crash reporter
- A scrubber that runs on send but not on the local spool file (secrets at rest on disk)
- Adding a field in code without updating `TELEMETRY.md` — the doc and the allowlist
  must change in the same PR

---
*Related: `common-product-analytics` (in-app product analytics is a different
discipline with different consent norms), `devtool-cli-ux` (prompt and confirmation
wording), `devtool-packaging` (shipping the data dictionary with the artifact) ·
domain agent: `devtool-architect` (whether to collect at all) · output/ADR format:
`playbook-conventions`*
