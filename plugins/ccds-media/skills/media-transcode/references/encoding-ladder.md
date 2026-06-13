# Worked encode → measure → package commands

ffmpeg/x264-flavored; the pattern (fixed aligned GOPs → capped-CRF encode per rung →
VMAF check against source → CMAF packaging with dual manifests) is the same for
x265, VP9, and AV1 — only the codec flags change.

## 1. Encode one rung (capped CRF, aligned GOPs)

```bash
# 1080p rung at 24 fps. keyint = 2 s GOP = 48 frames; scenecut=0 keeps every
# rendition's segment boundaries identical — required for ABR and ad stitching.
ffmpeg -i mezzanine.mov \
  -vf "scale=-2:1080" \
  -c:v libx264 -preset slow -profile:v high -level 4.1 \
  -crf 21 -maxrate 5000k -bufsize 10000k \
  -x264-params "keyint=48:min-keyint=48:scenecut=0" \
  -c:a aac -b:a 128k -ac 2 \
  -movflags +faststart \
  out_1080p.mp4
```

Per rung, change only `scale`, `maxrate`/`bufsize` (bufsize = 2× maxrate), and
`level`. Capped CRF beats plain CBR for VOD: quality-constant where it can be,
bitrate-capped where it must be. For live, switch to CBR-ish (`-b:v` with tight
`maxrate`) — players need predictable segment sizes.

## 2. Measure VMAF against the source

```bash
# Scale the encode BACK to source resolution before comparing — VMAF at mixed
# resolutions is not comparable. Distorted is the first input, reference second.
ffmpeg -i out_720p.mp4 -i mezzanine.mov -lavfi \
  "[0:v]scale=1920:1080:flags=bicubic[d];[d][1:v]libvmaf=log_fmt=json:log_path=vmaf_720p.json" \
  -f null -
```

Gate on the pooled mean (and watch the 1st-percentile frame score for brief
quality collapses). If a rung misses its target, adjust `crf`/`maxrate` and re-run —
do not eyeball it.

## 3. Package CMAF: one segment set, HLS + DASH manifests

```bash
packager \
  'in=out_1080p.mp4,stream=video,init_segment=v1080/init.mp4,segment_template=v1080/$Number$.m4s' \
  'in=out_720p.mp4,stream=video,init_segment=v720/init.mp4,segment_template=v720/$Number$.m4s' \
  'in=out_1080p.mp4,stream=audio,init_segment=a/init.mp4,segment_template=a/$Number$.m4s' \
  --segment_duration 4 \
  --generate_static_live_mpd --mpd_output manifest.mpd \
  --hls_master_playlist_output master.m3u8
```

Segment duration must be a multiple of the GOP (2 s GOP → 4 s segments). Add the
remaining rungs and language/audio-description tracks as further `in=` lines;
DRM (CENC keys) bolts onto this same invocation — see `media-drm-cdn`.

## Auto-QC checklist (gate before `ready`)

- [ ] VMAF per rung ≥ target (pooled mean), no frame below the collapse floor
- [ ] Black-frame scan (`blackdetect`) and silence scan (`silencedetect`) over full duration
- [ ] Loudness within target (`loudnorm` print: -23 LUFS EBU R128, or platform spec)
- [ ] A/V sync drift < 40 ms at start, middle, end
- [ ] Segment boundaries identical across all rungs (same segment count, aligned timestamps)
- [ ] Duration of every rung matches the mezzanine within one frame
- [ ] All expected audio languages and caption sidecars present and probe-clean
