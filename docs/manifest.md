# Glissade manifest contract (schema 1)

`schemaVersion` identifies the export format; `version` identifies a particular
build. They are independent. Python validates manifests before exporting or
publishing a live build. The browser validates them before playback. Existing
exports without `schemaVersion` are interpreted as schema 1 by the browser;
unknown versions are rejected with an explicit error.

The machine-readable structure is in [manifest.schema.json](manifest.schema.json).
The validators additionally check frame counts, unique scene IDs, and ordered,
unique, in-range keyframes and cuts.

## Scenes and frame sources

Every scene has an ID, zero-based index, name, positive FPS, nonnegative source
duration, `frameCount`, `frames`, `blocks`, `cuts`, `keyframes` and
`morphAnimations`. `frames.length` equals `frameCount`, which is at least one.

Frame sources are SVG URLs, base64 SVG/gzip data URIs, or `svg-delta-v1` objects.
A delta references an earlier frame of the **same scene** through its `base`
index. Its patches replace SVG element subtrees addressed by child-index paths.
The encoder anchors deltas at complete keyframes, avoiding unbounded chains.

## Timing and boundaries

- Time, hold, duration and dwell use seconds. Negative timings are rejected.
- Frame indices are zero-based. Each positive-duration block has
  `max(1, round(fps * duration))` intervals. For nonnegative inputs, ties round
  upward. Each scene includes its final endpoint, so its frame count is one
  plus the total number of intervals.
- A zero-duration transition consumes no interval and updates the state at
  its boundary. A zero-duration transition with a dwell immediately takes its
  target value, then holds it. Multiple cuts at the same instant collapse into
  one presenter stop, using the last cut's loop preference.
- A block owns `[start_frame, end_frame)`; the final block also owns its last
  endpoint. At a shared boundary, values belong to the following block.
- `duration` preserves source time. Playback uses `frameCount` and `fps`, so
  subframe durations are quantized to the available frame rate.
- Cuts pause on their endpoint. Continuing starts from that endpoint. Loop
  cuts repeat from the previous cut (or frame zero). Video segments include
  both endpoints, so adjacent segments share their boundary frame.
- `fps=0` is reserved for direct Typst/PDF slideshow rendering. The CLI and
  browser require strictly positive FPS.

## Live builds and caches

The editor compiles into a new temporary directory and switches the manifest
only after success. It retains the current and previous successful build for
in-flight frame requests. Frame URLs carry `?v=<version>` so a request cannot
accidentally read a newer build. Failed builds leave the working frames intact.

Only selected dirty slides need recompilation; other slides keep their last
rendered metadata until selected. Selection does not invalidate slides already
compiled for the same source revision. A project change invalidates all slides.

The browser uses bounded LRU caches. Failed loads are evicted so retries can
succeed, and live-manifest changes clear cached text, analysis and plans.
