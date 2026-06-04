---
name: security-checklist
description: Application security reference — OWASP Top 10, secrets hygiene, and severity rating. Use proactively when writing or reviewing auth, crypto, file I/O, secrets handling, or code that processes untrusted input, to self-check before a full audit.
---

# Security Checklist

Reference checklists for application security self-review. The `secure-auditor` agent
pulls this for its full audit; any domain agent should pull it while writing
security-sensitive code (auth, crypto, file I/O, secrets, untrusted input).

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

## Secrets hygiene checklist

- [ ] No credentials, API keys, or tokens in source code
- [ ] `.env` files excluded via `.gitignore`
- [ ] Secrets loaded from environment variables or a vault at runtime
- [ ] No secrets in logs, error messages, or API responses
- [ ] Rotation strategy exists for all secrets

When a finding requires a full audit with exploit scenarios and fixes, return to the
orchestrator to engage the `secure-auditor` agent.
