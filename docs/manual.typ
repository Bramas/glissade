#import "@preview/tidy:0.4.3"
#import "@preview/codly:1.3.0": *
#import "template.typ": *
#import "../src/show_timeline.typ": _show-timeline
#show: codly-init.with()

#let colors = tidy.styles.default.colors
#{
  colors.insert("second", rgb("#e7d9ff"))
  colors.insert("transition", rgb("#f9dfff"))
}

#let show-module(docs) = {
  v(3em)
  tidy.show-module(docs, show-outline: false, colors: colors)
}

#show: project.with(
  title: "Glissade, with Kino animation primitives",
  subtitle: "Animated Typst slides for the browser.",
  authors: ("Quentin Bramas",),
  version: "0.1.0",
  date: "2025-9-12",
  license: "MIT",
  url: "https://github.com/Bramas/glissade",
)

#columns(2, gutter: 5%)[

  Glissade is a Typst toolkit for creating animated slide decks and exporting
  them to the web. You write ordinary Typst pages, add animation state where it
  matters, and export a self-contained HTML presentation with SVG frames and a
  browser runtime.

  Glissade keeps the strongest part of Kino: the variable timeline model that
  turns Typst values into animation frames. It builds around that model with a
  slide-oriented workflow, browser playback controls, a live editor, and
  semantic morphing for formulas and vector graphics.

  = Glissade document structure<structure>

  A Glissade presentation usually starts with the `deck` show rule and contains
  one or more `slide` blocks:
  ```typst
  #import "@preview/glissade:0.1.0": *
  #set page(width: 128mm, height: 96mm)
  #show: deck.with(fps: 12)

  #slide(title: "A first animation")[
    #init(width: 1cm)
    #animate(width: 8cm)

    #context {
      rect(width: a("width"), height: 1cm)
    }
    #finish()
  ]
  ```

  `deck` collects slides and renders them as a sequence of independent scenes.
  Each `slide` has its own animation timeline, optional title, generated or
  explicit id, and optional frame rate. The body of a slide uses the same
  animation primitives as a standalone Kino-style animation.

  For small experiments, the lower-level `animation` show rule is still
  available:
  ```typst
  #show: animation
  // animation primitives & content
  #finish()
  ```

  = Slides<slides>

  `slide` is the main Glissade unit. Use one slide per logical step in a talk:
  title slides, theorem statements, diagrams, proofs, and transitions can each
  have their own timeline.

  ```typst
  #slide(id: "idea", title: "Main idea")[
    #init(opacity: 0%)
    #animate(opacity: 100%, duration: 0.6)
    #cut()
    #animate(opacity: 30%)

    #context {
      text(fill: rgb(20, 30, 70).transparentize(100% - a("opacity")))[
        The important object appears first, then makes room.
      ]
    }
    #finish()
  ]
  ```

  `id` is used by the live editor and by HTML export metadata. If omitted,
  Glissade derives it from the slide title, then falls back to `slide-1`,
  `slide-2`, and so on. `title` is shown in the browser overview. `fps` can be
  set per slide when one scene needs more or fewer frames than the rest of the
  deck.

  `cut()` creates a playback boundary inside a slide. In the browser, Right or
  Page Down advances through these boundaries, Space plays and pauses, and the
  overview makes it possible to jump between slides.

  = Morphing formulas and vector graphics<morph>

  Glissade can let the browser interpolate visible SVG elements instead of only
  replacing pre-rendered frames. This is useful for equations and diagrams where
  the viewer should track objects across a transformation.

  For formulas, wrap meaningful pieces with `part` and render the animated
  state with `glissade-morph`:
  ```typst
  #init(eq: formula($ part(a) = part(b) $))
  #animate(eq: formula($ part(a) / part(c) = part(b) / part(c) $))

  #context {
    glissade-morph("eq")
  }
  #finish()
  ```

  Identical parts are matched automatically. When two pieces look the same but
  should be tracked separately, pass an explicit `key`.

  The same renderer can be used for vector drawings. A drawing state can be
  wrapped as `cetz-shape`, then displayed through `glissade-morph`. The HTML
  runtime reads the markers emitted by Typst and animates the corresponding SVG
  paths in the browser. This keeps the PDF/SVG extraction simple while allowing
  richer presentation effects such as shape morphing or draw-border-then-fill
  reveals.

  = Kino animation primitives<kino-primitives>

  The animation timeline engine in Glissade comes from
  #link("https://github.com/aualbert/kino")[Kino], created by Augustin Albert.
  Kino established the core mechanism for declaring animated Typst variables,
  evaluating them at each frame, and extracting frames as SVG. Glissade keeps
  those primitives, documents them here, and builds the slide and browser
  workflow around them.

  This section describes the basic variable model.
  It focuses on the `animation` show rule and the functions `a`, `cut` and
  `finish`.

  Variables can be animated using animation primitives (e.g., `animate`), initialized using `init`, and their value accessed using `a`.
  The type of an animation variable cannot change during an animation.
  Supported types are `int`, `float`, `ratio`, `angle`, `array` of `function`.
  The size of an array and the types of its elements must be fixed.
  The functions must be defined at $0$, and the type of its image cannot change, e.g.
  ```typst
  #init(a: 0)
  #init(r: (45%, .0))
  #init(f: x => (y => x*y))
  ```
  Animation variables can then be evaluated using `a`, passing the variable name as argument.
  Context must also be provided, e.g.
  ```typst
  #context {
     a("a") + a("f")(.4)(.3)
  }
  ```
  To animate a variable from its current value to a new one, use an animation primitive (see @primitives).
  For example, the following primitives generate $1$ second of frames at a given framerate.
  In this animation, `a("a")` successively evaluates to $0$, $1$ and $2$.
  Meanwhile, `a(r)` interpolates continuously from `(45%, .0)` to `(60%, 1)`.
  Note that given the initial value of `r`, the argument `(60%, 1)` is interpreted as `(60%, 1.0)`.
  ```typst
  #animate( a: 2)
  #meanwhile( r: (60%, 1))
  ```
  If you animate a non-initialized variable, the system infers an initial value of the correct type, e.g.
  ```typst
  // the initial value
  // of g is _ => (0.,)
  #animate(g: t => (t,))
  ```
  If a variable `x` is neither initialized nor animated, `a("x")` evaluates to 0%.
  Finally, the function `cut` splits the output into playback segments.
  In HTML export, cuts become browser navigation boundaries. In video and
  reveal.js export, cuts define how generated media is split.

  #let docs = tidy.parse-module(read("../src/animation.typ"), scope: (
    _show_timeline: _show-timeline,
  ))

  #show-module(docs)

  = Animation primitives<primitives>

  This section describes the different animation primitives.
  They roughly share the same parameters, so we describe only the `animate` primitive in detail.

  Behind the scenes, the system converts each call to an animation primitive into a timeline.
  This timeline describes the value of animation variables at each time step of the animation.
  The internal timeline can be visualized as follows:

  #let var = (
    "x": (
      "0": ((0, 0, 0, 0, 0, none),),
      "1": ((0, 0, 1, 0, 0, none),),
      "2": ((0, 1, 1.3, .3, 0, none),),
    ),
    "y": (
      "0": ((0, 0, 0, 0, 0, none),),
      "1": ((0, .5, 2, 0, 0, none),),
    ),
  )

  #[
    #set align(center)
    #_show-timeline(var)
  ]

  As seen above, a timeline is divided into blocks.
  Blocks become very useful when coordinating several animation variables.
  Any call to `animate` creates a new block, but you can also specify a block as a parameter.
  By default, the system inserts a cut between each block (see @export).

  Finally, when calling an animation primitive, you can specify how variables are interpolated using the `animation` parameter (see @transitions for details).
  You can also specify the duration of the animation in seconds.

  #let docs = tidy.parse-module(read("../src/primitives.typ"), scope: (
    _show_timeline: _show-timeline,
  ))
  #show-module(docs)

  = Transitions<transitions>

  This section describes the built-in transitions used by the animation primitives.
  A transition is a mathematical function $[0,1] -> [0,1]$.
  Wherever a built-in transition name is expected, you can provide a custom transition instead.
  In addition, you can concatenate transitions using `concat`.

  #let docs = tidy.parse-module(read("../src/transitions.typ"))
  #show-module(docs)

  = Export and live development<export>

  The `glissade.py` command is the bridge between Typst and the browser. It
  compiles the Typst document, reads Glissade metadata, extracts SVG frames, and
  packages the result for the requested output.

  During authoring, use the live editor:
  ```bash
  python3 bin/glissade.py --root . slides.typ dev --fps 12
  ```

  The editor serves the presentation locally, rebuilds on demand, exposes a
  draggable playhead, and lets you jump between slides. Use `--host` and
  `--port` when the default `127.0.0.1:8765` is not convenient.

  For sharing a talk, the recommended output is dependency-free HTML:
  ```bash
  python3 bin/glissade.py --root . slides.typ html --fps 24 --title "My talk"
  ```

  This writes a standalone HTML file next to the input. By default, SVG frames
  are embedded, minified, compressed, optimized into smaller SVG deltas when
  possible, and decompressed lazily in the browser. Use `--no-embed-frames` if
  you prefer external frame files, `--no-minify-svg` while debugging SVG output,
  `--no-optimize-frames` to keep every frame as a complete SVG, or
  `--no-compress-frames` if compression makes local inspection harder.

  `--root` should point to the Typst project root. This matters when the
  document imports files outside its own directory, for example `../src/...`.
  `--timeout` controls how long Typst or media operations may run.

  Glissade also keeps the older Kino-style outputs:

  - `slides` produces a static PDF view.
  - `video` renders animation segments as video files and requires `ffmpeg`.
  - `revealjs` embeds generated videos into a reveal.js presentation.

  These outputs are useful for compatibility, but the Glissade-first workflow is
  `dev` while editing and `html` for presenting.
]
\

#figure(caption: "Command-line syntax of glissade.py")[
  #set align(left)
  #set text(
    font: "DejaVu Sans Mono",
    size: 9.3pt,
    tracking: -.1pt,
    weight: 500,
  )
  glissade.py [-h] [--root ROOT] [--timeout TIMEOUT] INPUT OUTPUT ...
  \
  \ OUTPUT:
  \ #h(0.6cm) slides
  \ #h(0.6cm) video #h(1.18cm) [--cut {none|scene|all}] [--fps FPS] [--ppi PPI] [--format FORMAT]
  \ #h(0.6cm) revealjs #h(.62cm) [--cut {none|scene|all}] [--fps FPS] [--ppi PPI] [--title TITLE] [--progress] [--template TEMPLATE]
  \ #h(0.6cm) html #h(1.39cm) [--cut {none|scene|all}] [--fps FPS] [--ppi PPI] [--title TITLE] [--progress]
  \ #h(2.49cm) [--embed-frames] [--minify-svg] [--compress-frames] [--optimize-frames] [--template TEMPLATE]
  \ #h(0.6cm) dev #h(1.54cm) [--cut {none|scene|all}] [--fps FPS] [--ppi PPI] [--host HOST] [--port PORT] [--template TEMPLATE]
  \
]<cmdsyntax>
