# SLO / error-budget worksheet

Work through this per service, top to bottom. The output is an SLO spec, a
burn-rate alert set, and a budget policy — record the target choice as an ADR.

## 1. Pick SLIs (what users feel)

| User journey | SLI | Measured where |
|---|---|---|
| API call succeeds | good = non-5xx (and non-timeout) / total requests | edge LB or CDN logs — closest point to the user |
| API call is fast | good = requests < 300 ms / total requests | same edge source as availability |
| Async job completes | good = jobs done < X min / total jobs | queue/worker metrics |

Rules: ratio-of-good-events form (composes into budget math); measure at the
outermost point you control; 2–4 SLIs per service, not ten.

## 2. Set the target and compute the budget

Budget = (1 − target) × window. For a 30-day window:

| Target | Full-outage budget / 30 d | Implication |
|---|---|---|
| 99% | 7.2 h | fine for internal tools |
| 99.9% | 43.2 min | default for production services |
| 99.95% | 21.6 min | needs redundancy + fast rollback |
| 99.99% | 4.3 min | faster than humans respond — requires automated mitigation |

Sanity checks before committing:
- Your target can't exceed your dependencies'. A 99.99% SLO on a 99.9% database
  is fiction (serial dependencies multiply: 0.999 × 0.999 ≈ 0.998).
- Look at the last 90 days. If you'd have breached the proposed target three
  times, either invest first or pick the target you can actually meet.

## 3. Burn-rate alert rules

Burn rate = (error rate during window) / (1 − target). At 1× you spend exactly
the budget over the full window.

```yaml
# Prometheus-style skeleton; 99.9% target → budget fraction = 0.001
- alert: ErrorBudgetFastBurn          # 2% of budget in 1h
  expr: >
    (error_ratio_1h  > 14.4 * 0.001)
    and
    (error_ratio_5m  > 14.4 * 0.001)
  labels: { severity: page }

- alert: ErrorBudgetMidBurn           # 5% of budget in 6h
  expr: >
    (error_ratio_6h  > 6 * 0.001)
    and
    (error_ratio_30m > 6 * 0.001)
  labels: { severity: page }

- alert: ErrorBudgetSlowBurn          # 10% of budget in 3d
  expr: >
    (error_ratio_3d  > 1 * 0.001)
    and
    (error_ratio_6h  > 1 * 0.001)
  labels: { severity: ticket }
```

The short window (≈ 1/12 of the long) makes alerts self-clearing: once the
incident is mitigated, the short window drops below the rate and the page stops.

Low-traffic guard: if the long window can contain fewer than ~1/budget-fraction
requests (e.g. < 1,000 requests at 99.9%), a single error can page. Add a
minimum event count to the expression or lengthen the window.

## 4. Budget policy (agree before the first breach)

| Budget remaining | Policy |
|---|---|
| > 50% | normal velocity; safe window for chaos experiments and risky migrations |
| 10–50% | risky changes need review; reliability items prioritized into the sprint |
| < 10% | feature freeze on this service; only reliability work and critical fixes ship |
| Exhausted | freeze + postmortem of budget spend; target or investment re-negotiated |

## 5. Review checklist

- [ ] SLI measured at the user-facing edge, ratio-of-good-events form
- [ ] Target defensible against dependency SLOs and 90-day history
- [ ] All three burn-rate rules deployed, each with long + short window
- [ ] Low-traffic guard in place where request volume is thin
- [ ] Budget policy written down and signed off by product
- [ ] SLO dashboard shows attainment, remaining budget, and burn rate trend
- [ ] Recalibration date set (quarterly) — SLOs drift like everything else
