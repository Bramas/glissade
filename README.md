# Glissade

Glissade is a Typst animation and presentation toolkit built for the web. Write
slides and animation state in Typst, preview them in a live editor, then export
a self-contained HTML presentation with resolution-independent SVG frames.

Glissade focuses on three things:

- a compact Typst API for timelines, transitions, cuts, and shared slide state;
- browser-native morphing and draw-in effects for formulas and vector graphics;
- a practical presentation workflow with live rebuilding, navigation, and
  portable HTML output.

[Documentation](https://bramas.github.io/glissade/docs.html) ·
[Examples](examples)

A complete [20-minute conference example](examples/standup-gathering) presents
myopic robots and stand-up gathering, with checked execution traces, a short
Simulant demo and English speaker notes.

## Quick start

The CLI requires Python 3.10 or newer and Typst on `PATH`. Video export also
requires FFmpeg. The pinned development toolchain uses Typst 0.14.2 and Bun
1.3.6; Bun is only needed when changing the browser sources.

Install the command from a checkout:

```bash
uv tool install .
glissade --help
```

Alternatively, use `pipx install .`, or keep running `python3 bin/glissade.py`
without installation. In the commands below, `glissade` can replace
`python3 bin/glissade.py`. The installed command includes its browser assets
and has no Python runtime dependencies.

```typ
#import "@preview/glissade:0.1.0": *
#set page(width: 128mm, height: 96mm)
#show: deck.with(fps: 12)

#slide(title: "Hello Glissade", autoplay: true)[
  = Hello Glissade
  #init(width: 3cm)
  #animate(width: 8cm)
  #animate(width: 3cm)
  #cut(loop: true)

  #context {
    rect(width: a("width"), height: 1cm, fill: blue)
  }
]
```

The animation ends with the slide body; no explicit terminator is needed.

Export it as a self-contained presentation:

```bash
python3 bin/glissade.py --root . slides.typ html --fps 24
```

Or start the live editor:

```bash
python3 bin/glissade.py --root . slides.typ dev --fps 12
```

The editor runs at `http://127.0.0.1:8765` and provides live rebuilding, a
draggable playhead, animation blocks, cut markers, and per-slide compilation.

## Touying integration

Touying can own the presentation structure and theme while Glissade supplies
continuous animation segments. Bind Touying's public function wrapper once,
then place Glissade animations between ordinary Touying pauses:

```typ
#import "@preview/touying:0.7.3": *
#import themes.simple: *
#import "@preview/glissade:0.1.0" as glissade

#show: simple-theme.with(aspect-ratio: "16-9")
#let glissade-animation = glissade.touying(
  touying-fn-wrapper,
  fps: 12,
)

== Mixed animation

Touying content
#pause

#glissade-animation(id: "moving-circle")[
  #glissade.init(x: 0pt)
  #glissade.animate(x: 100pt)
  #context {
    move(dx: glissade.a("x"), circle(radius: 10pt))
  }
]

#pause
Another Touying reveal
```

The `html` and `dev` commands detect Touying metadata automatically. Native
Touying subslides—including `pause`, `uncover`, and `only` states—become
presenter cuts. The subslides reserved by `touying-animation` play continuously
between those cuts. Touying remains responsible for complete page layout,
themes, counters, headers, and footers.

Do not add `#show: glissade.deck` to a Touying document: both functions are
document-level renderers. `glissade.touying` sets the default FPS for every
embedded animation in an ordinary `typst compile`. Pass `fps` directly to one
`glissade-animation` call to override it locally. Glissade's `html`,
`dev`, and `video` commands use their `--fps` option for all embedded animations.

Export video with FFmpeg when a non-interactive rendition is useful:

```bash
python3 bin/glissade.py --root . slides.typ video --fps 24 --cut none
```

Use `--cut scene` for one file per slide or `--cut all` for one file per
presenter segment.

## Browser-native morphing

`glissade-morph` connects Typst animation state to the browser renderer.
Explicit `part` markers let formulas preserve their semantic pieces across
keyframes:

```typ
#init(formula-state: $a = part(a) = part(b)$)
#animate(formula-state: $b = part(a) = part(b) / (1+c)$)

#context {
  glissade-morph("formula-state")
}
```

Matched pieces move smoothly, while unmatched content fades cleanly. Vector
shapes can use the same mechanism for geometry morphing or a
`draw-border-then-fill` creation effect.

## Presentation controls

- Right or Page Down starts or continues an animation. Double-tap to step
  through keyframes.
- Left or Page Up returns to the current or previous animation boundary.
- Space toggles playback and advances to the next animation at the end.
- Clicking the slide continues when paused; double-clicking pauses an animation.
- On touch screens, tap to play or pause, swipe left to continue, and swipe right
  to return to the previous animation boundary.
- `O` opens the slide overview and `F` enters fullscreen.

Playback pauses at every `cut()` and at the final frame. The generated HTML
contains the runtime and compressed SVG frames in one portable file. By default,
HTML export stores smaller SVG deltas for intermediate frames when that is more
compact than keeping complete SVGs; use `--no-optimize-frames` to disable this.
Repeated text glyphs are shared per slide, and delta patches are compressed
together. Shared data is decoded only when the slide is needed. Use
`--no-share-glyphs` to disable glyph sharing or `--no-compress-frames` to disable
gzip compression for both frames and shared data.

`--title "My talk"` sets the HTML title. With `--no-embed-frames`, `slides.html`
uses its own `slides.frames/` directory, so exporting another deck beside it
does not overwrite its images. Serve external-frame exports over HTTP;
self-contained exports can be opened directly as local files.

The dev editor watches Typst files, images, fonts and common data files under
`--root`. Failed builds keep the previous working preview. Successful builds
are published together with their manifest, and old temporary builds are
cleaned up automatically.

Video export uses Typst's raster frames, including native Touying subslides.
Browser-generated morph and drawing interpolation are available in HTML and
the playground; they are not baked into the video export.

## Browser playground

The playground supports Glissade decks, semantic formula parts,
`glissade-morph`, and `create` through the same renderer as exported HTML.
Use **Try a formula morph** for a complete example. Playback pauses at cuts;
the frame controls also let you inspect transitions manually. Touying decks
and arbitrary local file imports remain CLI workflows.

The compiler and renderer CDN URLs are pinned to typst.ts 0.7.0. The playground
requires a network connection for these components and their fonts.

## Development

Python responsibilities are split between `glissade/compiler.py` (scene
discovery and SVG/PNG compilation), `frames.py` (SVG deltas), `manifest.py`
(format validation), `live.py` (preview server), and `cli.py` (exports).
The `bin/` entry points remain available for repository use.

The readable browser sources live under `web/`. Bun bundles them into the
checked-in templates under `glissade/assets/` and the playground assets:

```bash
bun run build
bun run check
bun run build:playground-lib
bun test tests/runtime.test.js
python3 -m unittest discover -s tests -v
```

Run the browser integration tests after installing the optional test tools:

```bash
python3 -m venv .venv
.venv/bin/pip install -e '.[test]'
.venv/bin/python -m playwright install chromium
GLISSADE_BROWSER_TESTS=1 .venv/bin/python -m unittest discover -s tests -p test_browser.py -v
```

Pull requests run asset checks, runtime and compiler tests, real-browser morph
and playground tests, video export checks, and a distribution build. The
[manifest contract](docs/manifest.md) describes timing and compatibility rules.

Measure a generated 20-slide deck and optionally browser memory:

```bash
python3 bin/benchmark.py --slides 20 --fps 12 --output /tmp/glissade-benchmark.json
.venv/bin/python bin/benchmark.py --slides 20 --fps 12 --browser
```

The report records compilation time, export time, SVG/HTML size and, with
`--browser`, sampled JS heap and cache usage. Frame text caches retain at most
120 entries and 32 MiB of decoded text; analysis and morph-plan caches retain
64 and 32 entries. Reloading the live manifest clears these caches. These are
cache budgets, not a limit on the whole browser's memory.
Decoded shared glyph and delta data has a separate cache of at most 8 entries
and 8 MiB, or a single larger slide payload. Keeping that payload avoids
decompressing the same slide on every frame; it is evicted when other shared
data is loaded.

The exact-frame runtime inspector is useful when debugging morphs:

```bash
uv run bin/inspect_runtime.py slides.html \
  --scene shape-create --frame 5 --output /tmp/frame.svg
```

## Acknowledgements

Glissade grew from [Kino](https://github.com/aualbert/kino), created by
Augustin Albert. Kino established the core machinery for managing animated
Typst variables and extracting animation frames as SVG. Glissade is deeply
grateful for that foundation.

Thanks also to Jean-Romain Luttringer for finding the name Glissade.

Since then, Glissade has developed into a separate project focused on animated
presentations for the browser: multi-slide documents, a live editor,
self-contained HTML export, playback controls, formula and geometry morphing,
and browser-rendered drawing effects.

## License

MIT
