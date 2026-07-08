# Kino

[Kino](https://github.com/aualbert/kino) is an easy-to-use, proof of concept package for creating animations in pure Typst. Kino comes with a companion script [kino.py](https://github.com/aualbert/kino/blob/main/bin/kino.py) for exporting to videos, slideshows, or reveal.js presentations. See the [manual](docs/manual.pdf) and the [examples](https://github.com/aualbert/kino/blob/main/examples).

## Examples

<table>
<tr>
  <td>
    <a href="examples/graphs/arrays.typ">
      <img src="examples/graphs/arrays.gif" width="250px">
    </a>
  </td>
  <td>
    <a href="examples/graphs/lilaq.typ">
      <img src="examples/graphs/lilaq.gif" width="250px">
    </a>
  </td>
  <td>
    <a href="examples/countdown.typ.typ">
      <img src="examples/countdown.gif" width="250px">
    </a>
  </td>
</tr>
</table>

## Installation

To use the Kino package, simply add the following code to your document:
```typ
#import "@preview/kino:0.1.0": *
```
The HTML exporter and live editor require Python and Typst. A presentation is
one Typst document containing any number of `slide` calls, so definitions,
functions, counters, and imports are naturally shared.

Generate a self-contained presentation with:

```bash
python3 bin/kino.py --root . examples/slides.typ html --fps 24
```

SVG frames are minified and gzip-compressed by default. Compressed frames are
decompressed lazily and cached by the presentation runtime:

```bash
python3 bin/kino.py --root . examples/slides.typ html --fps 24
```

Use `--no-minify-svg` or `--no-compress-frames` to inspect the generated SVGs
or target a browser without `DecompressionStream` support.

The generated HTML includes the presentation runtime and SVG frames in a
single file. Animations remain resolution-independent, so
neither reveal.js nor ffmpeg is needed. Right starts or continues playback and
does nothing while an animation is already playing. Double-tap Right to enter
keyframe stepping; that mode resets after two seconds without another press.
Left pauses at the start of the current or previous animation. Space toggles
playback, and a compact timeline is available while paused for direct seeking.
Playback pauses at every `cut()` and at the final frame. Press Space again to
continue after a cut, and use `F` to enter fullscreen. The exported page is a clean
presentation view without editor panels; press `O` to open its slide overview.

For an editor with live rebuilds, a draggable playhead, animation blocks, and
cut markers, run:

```bash
python3 bin/kino.py --root . examples/slides.typ dev --fps 12
```

Then open `http://127.0.0.1:8765`. Editing a Typst source rebuilds the SVG
frames while the last successful preview remains available. The selected slide
is rebuilt immediately. Other slides are marked stale and rebuilt on demand
when selected, keeping the preview responsive without serving outdated frames.
The dev server logs source changes, discovered slides, per-slide compilation
times, on-demand cache rebuilds, and compilation failures to the terminal.

## Morphing and Drawing

Kino can also animate inline SVG content in the browser. `kino-morph(...)`
wraps content that should be animated from one keyframe to the next, and
`part(...)` marks sub-parts of a formula that should be matched explicitly.

```typ
#init(formula-state: $a = part(a) = part(b)$)
#animate(formula-state: $b = part(a) = part(b) / (1+c)$)

#context [
  #kino-morph("formula-state")
]
```

Matched parts use a smooth, Manim-like default easing in the browser runtime.
Unmatched leftovers fall back to a light fade instead of a full geometric
match, which avoids bold-looking duplicate glyphs during overlap.

For shapes that should be introduced from nothing, attach a morph effect to
the creating transition:

```typ
#create(shape-state: [
  #cetz.canvas({
    import cetz.draw: *
    circle((0pt, 0pt), radius: 65pt, fill: blue)
  }),
  morph-effect: "draw-border-then-fill",
)

#context {
  align(center, kino-morph("shape-state"))
}
```

`kino-morph` uses the state name as its ID by default. Pass an explicit `id`
only when rendering the same state more than once on a slide.

Likewise, `part(...)` derives its key from the rendered formula fragment. An
explicit `key` is only needed to distinguish repeated identical fragments or
to intentionally match differently written fragments across states.

The `draw-border-then-fill` effect is implemented in JavaScript from the final
SVG path data, so it works on ordinary vector shapes without extra Typst-side
geometry annotations.

### Inspecting an exact runtime frame

The runtime inspector renders a logical frame without using the presentation
playback controls and writes the composed result as a standalone SVG:

```sh
uv run bin/inspect_runtime.py examples/slides.html \
  --scene shape-create --frame 5 --output /tmp/shape-create-05.svg
```

The command uses the same browser runtime as the presentation and prints a
JSON summary of the generated geometry/draw layers. Frame and scene indexes are
zero-based; a scene ID can be used instead of its index.

## Quick start

Create a file `slides.typ` with the following content:

```typ
#import "@preview:kino:0.1.0": *
#set page(width: 128mm, height: 96mm)

#let shared-color = blue

// Used by a standard `typst compile slides.typ`.
#show: deck.with(fps: 6)

#slide(title: "Hello Kino")[
  #init(width: 1cm)
  #animate(width: 8cm)
  #cut()
  #animate(width: 3cm)

  #context {
    rect(width: a("width"), height: 1cm, fill: shared-color)
  }
  #finish()
]

#slide(title: "Shared definitions")[
  The second slide can use #text(fill: shared-color)[global definitions].
  #finish()
]
```

Plain Typst value animations now use `smooth` as their default transition.
You can still override any animation with another transition such as
`transition: "linear"` or `transition: "sin"`.

Kino compiles each logical slide independently and caches it by ID. A slide
with title `"Hello Kino"` receives the generated ID `hello-kino`; repeated
titles receive suffixes such as `hello-kino-2`. Untitled slides use `slide-1`,
`slide-2`, and so on. Set an explicit `id` when links must remain stable after
renaming a title. During live preview, only the selected slide is expanded into SVG frames.
Place the `deck` show rule after global page/text configuration and shared
definitions. Its `fps` value is the default for a standard Typst PDF build;
individual `slide` calls can override it with their own `fps` argument (`#slide(fps: 12)[...]`).

## Web asset build

The readable presentation, editor, and runtime sources live under `web/`.
Bun bundles and minifies them into the checked-in templates under `bin/assets/`:

```bash
bun run build
```

Use `bun run check` in CI to verify that the generated assets match their
sources. Bun is only needed when developing Kino; normal exports use the
packaged templates and remain Python-only. The `--template` option can still
load a custom source or generated template.

Packages whose counters occur inside animated content can opt into counter
freezing. For example, with Theorion:

```typ
#slide(id: "theorem", frozen-counters: (theorem-counter,))[
  #theorem[The number stays constant across every animation frame.]
  // animation commands...
  #finish()
]
```

For an in-depth introduction, including
- more export formats
- documentation of animation primitives
- supported types
- advanced command-line options 
- debugging tools

please consult the [manual](docs/manual.pdf).
