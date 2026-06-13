---
name: saas-billing
description: Subscription, entitlement, and billing integration specialist. Auto-invoked when payment-provider integration code is written (Stripe, Paddle, Lago, etc.), webhooks are handled, entitlement checks are placed in code paths, usage meters are ingested, or proration/dunning logic is added.
---

# SaaS Billing

Billing bugs are visible to customers and finance simultaneously. Correctness here
means idempotent, recoverable, and reconciled — not just "the happy path charges
the card".

## When to reach for this

- Writing or reviewing a payment-provider webhook handler
- Placing entitlement checks in code paths, or caching/invalidating them
- Ingesting usage meters or computing usage-based invoice lines
- Implementing proration, plan changes, dunning, or grace periods

## Principles

1. **Idempotency everywhere.** Every webhook handler, entitlement mutation, and
   meter emission must tolerate exact duplicates. Dedupe webhooks by provider
   event ID; dedupe meters by a client-stable event ID.
2. **The provider owns money; you own entitlements.** Sync one direction. Never
   compute "is this customer paid?" from your own tables when the provider can be
   asked; never let the provider decide what features unlock.
3. **Webhooks arrive late, twice, and out of order.** On any subscription event,
   fetch the object's *current* state from the provider API rather than trusting
   the event payload's snapshot — this makes out-of-order delivery harmless.
4. **Entitlements are cached but invalidated on every relevant webhook.** Stale
   after a downgrade is a revenue leak; stale after an upgrade is a support ticket.
5. **Fail loud on reconciliation mismatch.** At invoice time, if your usage total
   and the provider's disagree beyond tolerance (~0.1% or one billing unit),
   alert — never silently trust either side.
6. **Minimize PCI scope.** Provider-hosted collection only (Stripe Elements /
   Checkout, Paddle overlay). Never log raw webhook bodies or request bodies that
   could carry card data; never persist PAN/CVV.
7. **Verify webhook signatures with the raw body.** Framework body-parsers that
   re-serialize JSON break signature verification — this is the single most common
   integration bug. Respect the provider's timestamp tolerance (Stripe: 5 min).

## Subscription event → entitlement action

| Provider event | Entitlement action | Notes |
|---|---|---|
| `checkout.completed` / `subscription.created` | grant plan, start trial clock | idempotent: re-grant is a no-op |
| `subscription.updated` (plan change) | re-derive entitlements from price ID | handle both upgrade and downgrade paths |
| `invoice.payment_failed` | start dunning timer; do **not** revoke yet | revoke only at `past_due` policy expiry |
| `subscription.deleted` / `canceled` | revoke at period end, not immediately | honor `cancel_at_period_end` |
| `invoice.paid` | clear dunning state, restore access | also the reconciliation trigger |

A worked idempotent webhook-handler skeleton (signature verification, event
dedupe, fetch-current-state pattern, entitlement invalidation) is in
[`references/webhook-handler.md`](references/webhook-handler.md).

## Pitfalls

- Trusting the event payload's subscription snapshot (out-of-order bug)
- Entitlement checks reading the provider API on the hot path (cache it; invalidate on webhook)
- Proration computed locally instead of previewing via the provider's API
- Meters aggregated client-side, or without a dedupe key
- Tests that only cover the happy path — the branches that matter are duplicate
  webhook, out-of-order webhook, payment-failed, and expiry mid-request

---
*Related: `saas-multitenancy` (billing-data isolation), `saas-auth-sso` (plan-gated
roles) · domain agent: `saas-architect` (billing topology) · escalate PCI scope
expansion to `secure-auditor` · output/ADR format: `playbook-conventions`*
