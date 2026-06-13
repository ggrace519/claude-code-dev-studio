---
name: media-player
description: Client-side video / audio playback — ABR heuristics, player SDKs (Shaka, dash.js, ExoPlayer, AVPlayer), buffering / startup / rebuffer tuning. Auto-invoked when debugging QoE issues, implementing a player UI, or optimizing startup time.
---

# Media Player

QoE is felt in seconds and fractions of seconds — time-to-first-frame, rebuffer
rate, bitrate stability are the metrics viewers vote with. Everything between "user
hits play" and "video plays smoothly" is a deliberate decision, not SDK defaults.

## When to reach for this

- Choosing or integrating a player SDK (Shaka, hls.js, dash.js, ExoPlayer/Media3, AVPlayer) for a platform
- Tuning ABR: switch aggressiveness, buffer targets, panic-down thresholds
- Optimizing startup / TTFF, seeking behavior, or resume-instant-play
- Standing up QoE instrumentation, caption support, or a playback regression harness

## Principles

1. **Measure before tuning.** Startup time (p50/p95), rebuffer ratio (% of playback
   time), rebuffer events/hour, average and median bitrate served, error rate by
   code — instrumented from SDK events, emitted as per-session summaries. Tuning
   without these is guessing.
2. **Make ABR config explicit.** SDK defaults err toward stable bitrate over peak
   quality. Put switch aggressiveness, buffer target, and the panic-down threshold
   in one config block with documented per-platform overrides — never scattered
   inline tweaks.
3. **Win startup with parallelism and chunked transfer.** Fetch manifest, init
   segments, and license concurrently; CMAF chunked transfer lets the player start
   on a partially written segment. Starting one rung below estimated throughput and
   switching up beats waiting for a perfect first segment.
4. **Respect the platform.** iOS requires HLS and prefers native AVPlayer; Safari
   has ManagedMediaSource quirks; Android MediaCodec varies by vendor; TV OS
   players are slower than phones. One thin codepath per major platform beats a
   leaky universal abstraction.
5. **Subtitles are a11y, not an afterthought.** WebVTT/TTML/CEA-608/708 support
   with user-adjustable size, background, and language; tested with VoiceOver and
   TalkBack.
6. **Regression-test QoE in CI.** Golden-path runs on reference devices (Chrome
   desktop, Safari iOS, Android TV, one console); fail the build on startup
   regression > 200 ms or rebuffer-rate regression > 10% against baseline.

## Platform → SDK starting point

| Platform | SDK | Notes |
|---|---|---|
| Web (Chrome/Firefox/Edge) | Shaka Player or hls.js / dash.js | Shaka covers HLS+DASH+EME in one |
| Safari / iOS / tvOS | AVPlayer (native HLS) | MSE limited; FairPlay only via native |
| Android / Android TV / Fire TV | ExoPlayer (Media3) | per-vendor MediaCodec quirks; keep a device lab |
| Smart TVs (Tizen, webOS) | Shaka on the TV browser engine | old Chromium forks — pin SDK version floors |

ABR knobs that matter most: target buffer (live: small, e.g. 2–3 segments; VOD:
30 s+), upswitch confidence (sustained throughput, not one fast segment), and the
panic-down threshold (switch immediately when buffer falls below ~1 segment).

## Pitfalls

- One abstraction layer over every platform that ends up fighting all of them
- ABR "fixed" by pinning a rendition — masks the heuristic problem and burns bandwidth on good networks
- Startup measured in the lab on fast Wi-Fi only; p95 on cellular is the number that hurts
- Seek-accurate everywhere: keyframe-seek for scrubbing, frame-accurate only where the product needs it
- Captions rendered without user styling controls, or burned into video
- QoE events sampled so aggressively that per-device or per-ISP regressions are invisible

---
*Related: `media-transcode` (ladder the ABR chooses from), `media-drm-cdn` (license
latency in startup, per-CDN QoE), `media-live` (low-latency playback),
`media-ad-insertion` (break transitions) · domain agent: `media-architect` ·
output/ADR format: `playbook-conventions`*
