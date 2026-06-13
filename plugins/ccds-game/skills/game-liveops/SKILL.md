---
name: game-liveops
description: Live-ops specialist. Owns telemetry, A/B testing, content-update cadence, retention loops, IAP/monetization integration, and seasonal/event scheduling. Auto-invoked for any live-ops, telemetry, A/B, monetization-integration, or content-cadence work.
---

# Game Live-Ops

A modern game is a service: telemetry, experimentation, and content cadence are the
difference between a launch and a live business. Every live change needs a metric
before it ships and a kill switch after.

## When to reach for this

- Designing the telemetry event taxonomy or instrumenting a new feature
- Setting up an A/B test on anything touching money or retention
- Planning content cadence — seasons, events, drops — or a live event's rollout
- Integrating IAP, ads, or a season pass on the game side

## Principles

1. **Instrument before launching anything new.** No feature reaches prod without a
   telemetry plan: events, properties, the funnel they form, and who reads them.
2. **A/B everything that touches money or retention.** Pre-register hypothesis,
   primary metric, minimum detectable effect, and duration before the test starts —
   peeking and post-hoc metric shopping make every test "win".
3. **Cadence is a product.** Predictable drops (weekly small / monthly event /
   quarterly season is a common shape) beat sporadic mega-updates for retention and
   for the team's sanity.
4. **Reversible by default.** Every live event, config push, and offer has a remote
   kill switch that does not require a client update — and the rollback is rehearsed,
   not just written down.
5. **Cohort, not aggregate.** Read D1/D7/D30 retention and revenue by install
   cohort, platform, and spender tier; aggregates mix yesterday's whales with
   today's installs and lie about both.
6. **Separate content from code.** Events, offers, and tuning ship as data the
   client already knows how to render; client releases are the slow path (store
   review, adoption lag), config is the fast path.

## Live event launch checklist

- [ ] Telemetry: event start/complete/abandon instrumented with event ID and variant on every event
- [ ] Success metric and guardrail metrics (crash rate, refund rate, D1 of new installs) pre-registered
- [ ] Kill switch tested in staging: event can be disabled remotely mid-flight without client harm
- [ ] Offer/economy values in remote config, with old values retained for instant revert
- [ ] Rollback playbook: who flips the switch, player-comms template, refund/compensation posture decided in advance
- [ ] Timezone plan: start/end in UTC, displayed locally; no end time during the team's night
- [ ] Load expectation: event-start spike estimated and checked against backend capacity
- [ ] Post-event report scheduled: metric vs. pre-registered target, within one week

## Pitfalls

- Shipping the feature first, "adding analytics later" — the baseline is gone forever
- Ending an A/B test the day a metric looks good (peeking) instead of at the pre-registered duration
- Kill switch that exists but was never exercised — first use is during the incident
- Event taxonomy drift: three names for the same action across features, making funnels unjoinable
- Aggregate revenue up while new-cohort retention quietly falls — the decay is invisible for a quarter
- Compensation/refund posture improvised during the incident instead of decided before launch

---
*Related: `game-balance-designer` (the economy values being tuned),
`common-product-analytics` (event schema and experimentation rigor),
`game-platform-cert` (store rules on offers and updates) · domain agent:
`game-architect` · output/ADR format: `playbook-conventions`*
