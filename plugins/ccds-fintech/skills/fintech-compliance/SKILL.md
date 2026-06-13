---
name: fintech-compliance
description: Compliance program specialist. Owns KYC/KYB, sanctions/PEP screening, AML monitoring, SAR/CTR workflows, and regulator-mapping evidence. Auto-invoked for any code that gates customer access, screens transactions, or files regulatory reports.
---

# Fintech Compliance

Compliance is a program, not a feature: a human compliance officer owns the
policy, and the code's job is to make that policy executable, measurable, and
auditable. Code that gates customers or files reports without a traceable
policy behind it is a regulatory finding waiting to be written.

## When to reach for this

- Building KYC/KYB onboarding flows or integrating an IDV vendor
- Adding sanctions/PEP/adverse-media screening or a match-review queue
- Writing transaction-monitoring rules, thresholds, or alert handling
- Implementing SAR/CTR/STR filing workflows or a regulator evidence export

## Principles

1. **Every rule traces to a written policy with a named owner.** A threshold in
   code that no policy document mentions is unexplainable in an exam — link
   rule ID → policy section in the rule definition itself.
2. **Hard regulatory thresholds are config, not constants.** e.g. US CTR: cash
   transactions over $10,000 in a business day; SAR filing: within 30 calendar
   days of detection. Encode them as versioned, auditable configuration.
3. **False positives are a measured cost.** Track alert volume, true-positive
   rate, and median review time per rule; a rule nobody can clear is a backlog,
   and a screening match-review queue with no SLA is a frozen customer.
4. **Capture evidence at decision time.** Inputs, score/result, rule version,
   reviewer identity and notes — assembled when the decision is made, not
   reconstructed when the regulator asks.
5. **Decisions are immutable.** Onboarding and monitoring decisions are never
   silently edited; a changed outcome is a *new* decision that supersedes and
   references the old one.
6. **Regulator-ready means one query.** All evidence for a case — screening
   results, alerts, reviews, filings — exportable by case ID without an
   engineer writing ad-hoc SQL.

## Rule spec template

Define every monitoring/screening rule with these fields before implementing:

| Field | Example |
|---|---|
| Rule ID + policy reference | `TM-014` → AML Policy §4.2 (owner: BSA Officer) |
| Trigger | aggregate cash-in > $10,000 / 24h per customer |
| Threshold + version | v3, effective 2026-01-15, prior versions retained |
| Action | create alert in queue `structuring`, hold disbursement |
| Evidence captured | transactions in window, customer risk score, rule version |
| Review SLA + escalation | 5 business days → escalate to BSA Officer |
| Disposition options | close (reason coded) / file SAR / EDD trigger |

## Pitfalls

- Screening only at onboarding — sanctions lists change daily; rescreen the book on list updates or on a daily cycle
- Fuzzy-match thresholds tuned to zero false positives (that's zero recall on transliterated names)
- Tipping off: SAR existence leaking into customer-visible state, support tooling, or error messages
- Alert dispositions without reason codes — "closed, no notes" is indefensible in a lookback
- Vendor IDV/screening responses discarded after the decision instead of stored as evidence
- Rule changes deployed without versioning, making historical decisions unexplainable

---
*Related: `fintech-audit-trail` (evidence storage and tamper proofing),
`fintech-risk` (model-based scoring vs. rule-based controls), `fintech-ledger`
(the transactions being monitored), `common-privacy` (PII in KYC data) · domain
agent: `fintech-architect` (licensing and regulatory posture) · output/ADR
format: `playbook-conventions`*
