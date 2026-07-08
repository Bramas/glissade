# Glissade

Glissade is a Typst animation and presentation toolkit built for the web. Write
slides and animation state in Typst, preview them in a live editor, then export
a self-contained HTML presentation with resolution-independent SVG frames.

Glissade focuses on three things:

- a compact Typst API for timelines, transitions, cuts, and shared slide state;
- browser-native morphing and draw-in effects for formulas and vector graphics;
- a practical presentation workflow with live rebuilding, navigation, and
  portable HTML output.

[Documentation](https://bramas.github.io/glissade/) ·
[PDF manual](https://bramas.github.io/glissade/manual.pdf) ·
[Examples](examples)

## Quick start

```typ
#import "@preview/glissade:0.1.0": *
#set page(width: 128mm, height: 96mm)
#show: deck.with(fps: 12)

#slide(title: "Hello Glissade")[
  #init(width: 1cm)
  #animate(width: 8cm)
  #cut()
  #animate(width: 3cm)

  #context {
    rect(width: a("width"), height: 1cm, fill: blue)
  }
  #finish()
]
```

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
- `O` opens the slide overview and `F` enters fullscreen.

Playback pauses at every `cut()` and at the final frame. The generated HTML
contains the runtime and compressed SVG frames in one portable file.

## Development

The readable browser sources live under `web/`. Bun bundles them into the
checked-in templates under `bin/assets/`:

```bash
bun run build
bun run check
```

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
