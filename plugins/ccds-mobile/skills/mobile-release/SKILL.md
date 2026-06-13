---
name: mobile-release
description: Mobile release pipeline and store submission specialist. Auto-invoked when TestFlight, Play Console, signing, provisioning, staged rollouts, review preparation, or store metadata / privacy declarations are being handled.
---

# Mobile Release

Ship the build, pass review on the first submission, and keep the rollout safe.
Unlike web, a bad mobile release can't be rolled back — only halted and
resubmitted through review — so the pipeline has to prevent, not just react.

## When to reach for this

- Setting up or changing code signing, provisioning, or keystore management
- Preparing a store submission: metadata, screenshots, privacy declarations, review notes
- Designing the staged-rollout ramp and its halt criteria
- A rejection landed and the resubmission needs to actually fix the cause

## Principles

1. **Automate the submission path.** CI-driven (fastlane, Xcode Cloud, Gradle +
   Play publisher) from tag to store track; manual uploads drift and can't be
   audited.
2. **Staged rollout or not at all.** Play: 1% → 10% → 50% → 100%, advancing
   only while crash-free and ANR rates hold the previous version's baseline.
   iOS phased release ramps automatically over 7 days and can be paused —
   pausing is your only brake, so wire the vitals alert that pulls it.
3. **Privacy forms match the code.** App Privacy (iOS), Data Safety (Play), and
   the iOS privacy manifest (`PrivacyInfo.xcprivacy`, required since May 2024 —
   including required-reason API declarations) must list exactly what the app
   and its SDKs collect. Audit SDKs each release; a mismatch is a rejection or
   a takedown.
4. **Be reviewer-friendly.** A working demo account (seeded with data), working
   deep links, and review notes that pre-answer the obvious questions ("the
   QR feature needs a second device — see attached video") cut review
   round-trips dramatically.
5. **Signing assets have a disaster-recovery story.** Use Play App Signing so
   Google escrows the app key; for iOS, distribution certs and profiles live in
   a shared vault/match repo, never on one laptop. Losing a non-escrowed
   keystore means losing the ability to update the app.
6. **Kill switches for risky features.** A server-side flag that disables a
   ship-blocking bug beats a 1–3 day emergency review cycle. Wire the flag
   *before* the rollout, and use expedited review only as the backup plan.

## Pre-submission checklist

- [ ] Version/build number bumped; release built from a tagged CI run, signed with release config
- [ ] dSYM / R8 mapping uploaded for this exact build (see `mobile-crash`)
- [ ] App Privacy / Data Safety / privacy manifest diffed against any new SDK or permission
- [ ] New permissions have usage strings and an in-context request flow (see `mobile-platform`)
- [ ] IAP products attached to the submission and tested in sandbox (see `mobile-iap`)
- [ ] Demo account works on a clean install; review notes updated
- [ ] What's-new text and screenshots current for every required locale/device class
- [ ] Rollout plan written: ramp percentages, vitals gates, who can halt, kill-switch flags listed
- [ ] Rollback reality check: can the previous version's users live with this schema/API change? (mobile can't roll back)

## Pitfalls

- Server APIs deployed in lockstep with the app — old app versions live for
  months; every API change must tolerate N-2 clients
- Halting a Play rollout but forgetting the iOS phased release (or vice versa)
- Data Safety form copied from last year while an SDK quietly added collection
- Demo account behind 2FA, geo-block, or expired data — the #1 avoidable rejection
- Treating TestFlight/internal-track approval as App Review approval; full
  review applies fresh rules at release submission
- One-shot 100% rollouts to "ship faster" — the time saved is repaid with
  interest on the first bad release

---
*Related: `mobile-crash` (rollout halt gates, symbol upload), `mobile-iap`
(billing rejections), `mobile-platform` (permission/privacy declarations) ·
domain agent: `mobile-architect` · output/ADR format: `playbook-conventions`*
