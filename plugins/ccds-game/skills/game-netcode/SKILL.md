---
name: game-netcode
description: Multiplayer netcode specialist. Auto-invoked when networked gameplay code is written — client prediction, server reconciliation, rollback, lag compensation, matchmaking, or dedicated-server topology.
---

# Game Netcode

Netcode is the machinery that makes networked gameplay feel local — prediction,
reconciliation, rollback, lag compensation. Its bugs (rubber-banding, ghost hits,
desyncs) are the class players notice most and clip first.

## When to reach for this

- Choosing or implementing the network topology for a multiplayer game
- Writing client prediction, server reconciliation, or interpolation code
- Implementing lag-compensated hit registration or rollback
- Designing the replication schema, tick rates, or session/matchmaking lifecycle

## Principles

1. **Match the topology to the genre — don't reinvent.** Shooters and MOBAs →
   authoritative server with prediction. Fighting games → rollback (the GGPO
   model). RTS → deterministic lockstep. Turn-based → simple state sync.
2. **Predict on client, reconcile from server.** Never trust the client (anything
   client-authoritative is a cheat vector); never wait for the server (a full RTT
   of input lag is unplayable past LAN).
3. **Lag compensation is a documented design choice.** Favor-the-shooter rewind
   feels right to the shooter and "shot behind cover" to the victim — pick the
   rewind window (commonly capped around 200–400 ms), write it down as an ADR.
4. **Deltas, not full states.** Snapshot deltas against the last acked baseline,
   quantized fields, and interest management (don't replicate what the player
   can't perceive) — bandwidth is the scarcest resource.
5. **Decouple tick from snapshot from render.** Common shape: simulate at
   30–64 Hz, snapshot to clients at 20–30 Hz, render interpolated ~100 ms in the
   past. Each rate is a separate, tunable decision.
6. **Determinism is earned, not assumed.** Rollback and lockstep require
   eliminating every nondeterminism source — float behavior across
   platforms/compilers, iteration order, RNG, time. See the checklist below.
7. **Test under real network conditions.** Packet loss, jitter, reordering,
   asymmetric latency — via a conditioner (clumsy, tc/netem, Network Link
   Conditioner) in CI-able form, not just office LAN.

## Topology decision table

| Genre / constraint | Topology | Key parameters to fix early |
|---|---|---|
| FPS / action, server-hosted | authoritative server + client prediction | tick rate, rewind window, interp delay |
| Fighting, 1v1 low player count | rollback (peer or relayed) | max rollback frames (7–8 typical), input delay frames |
| RTS, hundreds of units | deterministic lockstep | turn length, desync detection (state hashes) |
| Co-op, low stakes | relaxed client authority + server validation | which fields the server vetoes |
| Turn-based | server-authoritative state sync | nothing real-time; focus on reconnect |

A full determinism audit checklist for rollback/lockstep (float traps, RNG,
iteration order, desync detection harness) is in
[`references/determinism-checklist.md`](references/determinism-checklist.md).

## Pitfalls

- Trusting the client's reported hit/position "for now" — it ships that way
- Prediction without reconciliation smoothing — corrections snap instead of blending
- Replicating via per-field reliable RPCs instead of snapshot deltas — bandwidth and ordering both degrade
- Only testing at 0 ms LAN latency; first jitter exposure is the public playtest
- Physics engine in the rollback loop that was never deterministic to begin with
- No desync detection in lockstep builds — divergence discovered minutes after the cause
- Tick logic coupled to render frame rate, so a fast client simulates faster

---
*Related: `game-engine` (engine constraints on determinism and physics),
`game-perf-profiler` (CPU cost of resimulation), `game-balance-designer`
(matchmaking/MMR parameters) · domain agent: `game-architect` (server hosting
topology) · output/ADR format: `playbook-conventions`*
