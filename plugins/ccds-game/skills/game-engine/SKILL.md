---
name: game-engine
description: Engine-specific implementation specialist (Unity, Unreal, Godot, bespoke). Auto-invoked when engine APIs are being used — rendering, shaders, scene management, physics, animation, audio, or engine-idiomatic patterns.
---

# Game Engine Implementation

Engine-idiomatic code uses the engine's APIs with their grain rather than fighting
it. Fighting the engine produces subtle lifecycle bugs and performance traps that
surface months later under load.

## When to reach for this

- Writing gameplay code against engine APIs — rendering, physics, animation, scene management
- Deciding between a built-in engine system and a custom replacement
- Authoring or reviewing shaders, LOD setups, or streaming/scene-loading code
- Porting a pattern from one engine's idiom to another's (MonoBehaviour ↔ Actor/Component ↔ Node)

## Principles

1. **Use the engine's patterns.** Unity: components + ScriptableObjects, respect the
   `Awake`/`OnEnable`/`Start` order. Unreal: Actor/Component + UPROPERTY for GC
   visibility. Godot: scene composition + signals. Cross-engine "framework" layers
   that hide the engine usually hide its lifecycle guarantees too.
2. **Prefer built-in over custom.** Built-in physics, animation, navigation, and
   audio are battle-tested across thousands of titles. Replace one only with a
   measured cause and an ADR recording why.
3. **Shaders have budgets.** Every sampler, texture read, and branch costs;
   mobile/tile-based GPUs additionally punish overdraw and alpha blending. Know the
   target hardware before authoring, not after profiling.
4. **LODs and culling ship from the start.** Retrofitting LOD chains, occlusion
   culling, and impostors onto finished content is far costlier than authoring with
   them — make them part of the asset acceptance criteria.
5. **Profile inside the engine's tooling.** Unity Profiler + Frame Debugger,
   Unreal Insights + `stat unit`, RenderDoc/PIX for GPU captures. The engine's view
   of its own frame beats guessing from external timers.
6. **Respect the main-thread contract.** Most engine APIs are main-thread-only;
   move work off-thread via the engine's own job/task system (Unity Jobs/Burst,
   Unreal TaskGraph), not raw threads touching engine objects.

## Built-in vs. custom decision table

| Situation | Default | Go custom only when |
|---|---|---|
| Rigid-body physics | engine physics | deterministic lockstep/rollback netcode requires it |
| Character movement | engine character controller | feel requirements exceed it — and measured against `game-feel-critic` criteria |
| Animation blending | engine state machine / blend trees | procedural animation is the product |
| Pathfinding | engine navmesh | non-planar or massively dynamic worlds |
| UI | engine UI system | proven perf ceiling on target hardware |
| Serialization/saves | engine-supported formats | versioned cross-platform saves demand a stable custom schema |

When the built-in option is rejected, record the measured reason and the fallback
as an ADR — "we didn't like it" does not survive the next hire.

## Pitfalls

- Per-frame allocations in hot paths (`Update`, tick) — GC spikes read as random hitches
- Doing work in constructors/`Awake` that depends on other objects' initialization order
- `Find`/string-based lookups every frame instead of cached references
- Physics queried or stepped from rendering callbacks (or vice versa) — use the
  engine's fixed-step callback for simulation logic
- Shaders authored on desktop GPUs, first mobile capture taken at beta
- Custom replacements for built-ins with no benchmark proving the built-in was the problem

---
*Related: `game-perf-profiler` (frame-budget analysis), `game-netcode` (determinism
constraints on physics/engine choices), `game-audio` (audio pipeline integration),
`game-feel-critic` (input/camera responsiveness) · domain agent: `game-architect`
(engine selection) · output/ADR format: `playbook-conventions`*
