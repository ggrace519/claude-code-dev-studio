---
name: security-checklist
description: Application security reference — OWASP Top 10, secrets hygiene, and severity rating. Use proactively when writing or reviewing auth, crypto, file I/O, secrets handling, or code that processes untrusted input, to self-check before a full audit.
---

# Security Checklist

Reference checklists for application security self-review — the shared severity
language and baseline checks used while writing security-sensitive code, before the
`secure-auditor` agent runs its full audit.

## When to reach for this

- Writing or reviewing auth, crypto, file I/O, or secrets-handling code
- Any code path that processes untrusted external input
- Self-checking a change before requesting a full security audit
- Rating a security finding consistently (severity definitions below)

## Vulnerability priority framework

Rate findings by exploitability × impact:

- **CRITICAL** — remotely exploitable, no auth required, high impact (RCE, auth bypass, mass data exfiltration)
- **HIGH** — exploitable with low effort or authenticated access, significant impact
- **MEDIUM** — requires specific conditions; moderate impact
- **LOW** — defense-in-depth; low probability or limited impact
- **INFO** — hardening recommendation; not a vulnerability

**All CRITICAL and HIGH findings must be resolved before deployment (Phase 7).**

## OWASP Top 10 checklist

Review every codebase against:
- [ ] A01 Broken Access Control
- [ ] A02 Cryptographic Failures
- [ ] A03 Injection
- [ ] A04 Insecure Design
- [ ] A05 Security Misconfiguration
- [ ] A06 Vulnerable and Outdated Components
- [ ] A07 Identification and Authentication Failures
- [ ] A08 Software and Data Integrity Failures
- [ ] A09 Security Logging and Monitoring Failures
- [ ] A10 Server-Side Request Forgery (SSRF)

## AI-generated code: recurring mistake patterns

Model output is untrusted contributor code; these specific patterns recur often
enough in generated code to check for by name (they are also good semgrep/hook
rules per stack):

- [ ] No SQL or shell commands built by string concatenation — **parameterized
      queries and argument arrays, always**; string-building is a finding even
      when today's inputs look safe
- [ ] No `subprocess`/exec with `shell=True` on anything derived from input
- [ ] No `yaml.load` without `SafeLoader` (or equivalent unsafe deserializers)
- [ ] No `verify=False` / disabled TLS verification on HTTP clients
- [ ] No unintended `0.0.0.0` binds — loopback by default, all-interfaces only
      as an explicit, documented choice
- [ ] No outdated crypto the model reached for from old training data: ECB mode,
      MD5/SHA-1 for anything security-relevant, `random()` where a CSPRNG is
      required for tokens/ids
- [ ] Authorization checked, not just authentication — every handler that loads a
      resource verifies *this* user may act on *this* object (models write login
      flows and forget ownership checks)
- [ ] New dependencies verified to exist on the registry (name, author, real
      download history) before install — models invent plausible package names,
      and attackers register them (slopsquatting)

## Secrets hygiene checklist

- [ ] No credentials, API keys, or tokens in source code
- [ ] `.env` files excluded via `.gitignore`
- [ ] Secrets loaded from environment variables or a vault at runtime
- [ ] No secrets in logs, error messages, or API responses
- [ ] Rotation strategy exists for all secrets

## Pitfalls

- Self-rating real findings as MEDIUM to dodge the CRITICAL/HIGH deployment gate
- Checking the boxes against the framework's defaults instead of this codebase's
  actual routes, queries, and file paths
- Treating a passing checklist as a substitute for the full audit — this is the
  self-check, not the exploit-scenario analysis a finding deserves

---
*Related: `code-review-checklist` (general review dimensions), `api-design`
(boundary validation), `common-privacy` (data-exposure handling) · pulled by any
domain agent; the `secure-auditor` agent runs the full audit · output/ADR format:
`playbook-conventions`*
