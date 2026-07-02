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

The generated HTML includes the presentation runtime and SVG frames in a
single file. Animations remain resolution-independent, so
neither reveal.js nor ffmpeg is needed. Use the arrow keys to navigate, space
to pause or resume an animation, and `F` to enter fullscreen. Playback pauses
at every `cut()` and at the final frame;
press space again to continue after a cut. The exported page is a clean
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

## Quick start

Create a file `slides.typ` with the following content:

```typ
#import "@preview:kino:0.1.0": *
#set page(width: 128mm, height: 96mm)

#let shared-color = blue

// Used by a standard `typst compile slides.typ`.
#show: deck.with(fps: 6)

#slide(id: "hello", title: "Hello Kino")[
  #init(width: 1cm)
  #animate(width: 8cm)
  #cut()
  #animate(width: 3cm)

  #context {
    rect(width: a("width"), height: 1cm, fill: shared-color)
  }
  #finish()
]

#slide(id: "goodbye", title: "Shared definitions")[
  The second slide can use #text(fill: shared-color)[global definitions].
  #finish()
]
```

Kino compiles each logical slide independently and caches it by its stable
`id`. During live preview, only the selected slide is expanded into SVG frames.
Place the `deck` show rule after global page/text configuration and shared
definitions. Its `fps` value is the default for a standard Typst PDF build;
individual `slide` calls can override it with their own `fps` argument ( `#slide(id: "special", fps: 12)[...]` ).

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
