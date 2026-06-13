# Determinism audit checklist (rollback / lockstep)

Rollback and lockstep both require that the same inputs produce bit-identical
state on every machine. One divergent bit anywhere in the simulation desyncs the
session. Audit every item below before trusting a determinism-dependent topology.

## Floating point

- [ ] Same float behavior across all shipping platforms/compilers — either pin
      compiler flags (no fast-math, consistent FP contraction) and verify with
      cross-platform replay tests, or sidestep floats entirely with fixed-point
      math for simulation state
- [ ] No use of hardware-variant intrinsics (FMA, rsqrt estimates) in sim code
- [ ] Transcendentals (`sin`, `atan2`, `pow`) come from a deterministic software
      implementation or lookup table, not the platform libm
- [ ] Physics: the engine's built-in physics is almost never cross-platform
      deterministic — use a deterministic physics lib or custom fixed-point
      physics for anything in the rollback state

## Randomness and time

- [ ] One seeded PRNG owned by the simulation; seed exchanged at session start
- [ ] No `rand()`, no global RNG shared with rendering/VFX (cosmetic effects get
      their own non-sim RNG)
- [ ] PRNG state is part of the saved/rolled-back state
- [ ] No wall-clock or delta-time reads inside simulation — sim time is
      `tick * fixedDelta`, nothing else

## Ordering and containers

- [ ] No iteration over hash-ordered containers in sim code (hash maps/sets with
      address- or seed-dependent ordering) — iterate sorted keys or use ordered
      containers
- [ ] Entity processing order is explicit and identical everywhere (stable IDs,
      not pointer order or spawn-race order)
- [ ] All sorts in sim code are stable sorts with total orderings (tie-breaker on
      entity ID)
- [ ] No uninitialized memory read into state; structs zero-initialized before use

## State and serialization

- [ ] The complete rollback state is enumerated: every field the simulation reads
      must be saved/restored — a single cached value outside the snapshot causes
      "impossible" desyncs
- [ ] Save/load of a frame is itself bit-exact (round-trip test: save, load,
      save again, compare)
- [ ] State snapshot is memcpy-fast; budget resimulation cost — rollback of N
      frames means N extra sim steps in one render frame (at 7 frames rollback
      and 60 Hz, the sim step must comfortably run 8x in 16.6 ms)

## Desync detection harness

- [ ] Per-tick (or every N ticks) checksum of canonical sim state, exchanged
      between peers / reported to server
- [ ] On checksum mismatch: log the first divergent tick, dump both full states
      for offline diff — detecting "a desync happened five minutes ago" is
      useless without the first divergent field
- [ ] Replay system: record session inputs + seed, re-simulate headless in CI on
      every platform target, compare final checksums — this is the regression
      gate that keeps determinism earned
- [ ] Soak test: long automated sessions (hours) under a network conditioner with
      loss/jitter/reorder, asserting zero checksum mismatches
