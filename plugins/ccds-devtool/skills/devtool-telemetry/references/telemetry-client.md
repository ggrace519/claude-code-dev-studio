# Consent-gated, fail-silent telemetry client skeleton

TypeScript-flavored for a Node CLI; the pattern (consent gate → allowlist schema →
client-side scrub → spool → batched fail-silent send) is identical in Go, Rust, or
Python.

```ts
// 1. Consent gate — checked on EVERY emit, not just at startup.
//    Precedence: ambient signals > explicit flag/env > persisted choice > unset.
function telemetryEnabled(): boolean {
  if (process.env.DO_NOT_TRACK === "1") return false;
  if (process.env.CI === "true") return false;          // never collect from CI
  if (process.env.TOOL_NO_TELEMETRY === "1") return false;
  const choice = readConfig().telemetry;                 // "on" | "off" | undefined
  return choice === "on";                                // undefined = not consented = off
}

// First-run prompt: interactive TTY only, and it must not send anything itself.
// Persist "on"/"off" to the user config; never re-prompt after an answer.

// 2. Allowlist schema — a field not declared here cannot be sent.
//    This file and TELEMETRY.md change in the same PR, or CI fails.
const EVENT_SCHEMA = {
  command_run: ["command", "flags", "exit_code", "duration_ms",
                "version", "os", "arch", "ci"] as const,
  crash:       ["version", "os", "arch", "error_name", "stack_scrubbed"] as const,
};

// 3. Scrubber — runs BEFORE anything touches disk or network.
function scrub(s: string): string {
  return s
    .replace(/(?:\/home|\/Users|[A-Z]:\\Users)\\?\/?[^\s/\\]+/g, "<user-dir>")
    .replace(/\b(?:ghp|gho|sk|pk|xox[bap])[-_][A-Za-z0-9_-]{10,}\b/g, "<token>")
    .replace(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\b/g, "<email>");
}

function emit(type: keyof typeof EVENT_SCHEMA, fields: Record<string, unknown>) {
  if (!telemetryEnabled()) return;
  const allowed = Object.fromEntries(
    EVENT_SCHEMA[type].filter(k => k in fields)
      .map(k => [k, typeof fields[k] === "string" ? scrub(fields[k] as string) : fields[k]]));
  appendToSpool({ type, ts: Date.now(), ...allowed });   // spool is already scrubbed
  if (process.env.TOOL_TELEMETRY_DEBUG === "1")
    console.error("[telemetry]", JSON.stringify(allowed)); // inspectable, on stderr
}

// 4. Transport — batched, hard-capped, never observable by the user.
async function flushSpool() {
  const batch = readSpool(50);                           // cap batch size
  if (batch.length === 0) return;
  const endpoint = process.env.TOOL_TELEMETRY_ENDPOINT   // enterprise self-host
                ?? "https://telemetry.example.com/v1/events";
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 2000);      // 2s hard budget
    const res = await fetch(endpoint, { method: "POST", signal: ctrl.signal,
      headers: { "content-type": "application/json" }, body: JSON.stringify(batch) });
    clearTimeout(t);
    if (res.ok) clearSpool(batch.length);
    // non-2xx: leave in spool, retry next run; spool itself is size-capped (drop oldest)
  } catch { /* fail silent — no log line, no exit-code change, no retry loop */ }
}
// Call flushSpool() fire-and-forget at command start, NOT at exit —
// process exit must never wait on telemetry.
```

## Verification checklist

- [ ] Fresh install, no consent given → zero network calls (verify with a proxy / `strace`)
- [ ] `DO_NOT_TRACK=1` / `CI=true` / `NO_TELEMETRY` → no prompt, no send, no spool write
- [ ] Disable command prints a one-line confirmation and survives upgrade
- [ ] Field added in code but not in `TELEMETRY.md` → CI fails (schema/doc lockstep check)
- [ ] Spool file on disk contains only scrubbed payloads (grep for home dir, tokens)
- [ ] Endpoint blackholed (firewall) → command duration unchanged, exit code unchanged, stderr clean
- [ ] `TOOL_TELEMETRY_DEBUG=1` output matches exactly what the wire would carry
- [ ] Self-host endpoint override verified end-to-end; air-gap mode performs no DNS lookup
