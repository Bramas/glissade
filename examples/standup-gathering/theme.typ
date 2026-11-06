// A quiet conference theme for Touying, and the drawings of robots on a line.
#import "@preview/touying:0.7.3": *
#import "@preview/cetz:0.5.1"
#import "../../lib.typ" as glissade
#import "../../lib.typ": init, animate, cut

// ---------------------------------------------------------------- palette ---
// Every color has one meaning across the talk.
#let ink = rgb("#1b1f2a")
#let muted = rgb("#5f6b7a")
#let faint = rgb("#a3acb9")
#let hairline = rgb("#e4e8ef")
#let paper = white
#let tint = rgb("#f6f7fa")
#let accent = rgb("#2c5cc5") // robots and emphasis
#let accent-soft = rgb("#e9effb")
#let teal = rgb("#0f8b7d") // views, moves, things that work
#let teal-soft = rgb("#e2f3f0")
#let alert = rgb("#c8402f") // crashes and failures
#let alert-soft = rgb("#fbeae7")
#let amber = rgb("#b7791f") // open questions
#let amber-soft = rgb("#fbf1dd")

#let handout = sys.inputs.at("handout", default: "false") == "true"
#let recordings = json("traces.json").traces

// ------------------------------------------------------------ typography ---
#let note(body) = text(size: 21pt, fill: muted, body)
#let lead(body) = block(above: 0pt, below: 0pt, text(size: 32pt, fill: ink, body))
#let em-accent(body) = text(fill: accent, weight: "bold", body)
#let em-teal(body) = text(fill: teal, weight: "bold", body)
#let em-alert(body) = text(fill: alert, weight: "bold", body)
#let em-amber(body) = text(fill: amber, weight: "bold", body)

#let pill(body, color: accent, fill: auto) = box(
  inset: (x: 10pt, y: 5pt), radius: 99pt,
  fill: if fill == auto { color.lighten(88%) } else { fill },
  text(size: 19pt, weight: "bold", fill: color, body),
)

// A soft panel that groups related content.
#let card(body, fill: tint, stroke: none, inset: 22pt, width: 100%) = block(
  width: width, inset: inset, radius: 12pt, fill: fill, stroke: stroke, body,
)

// Small uppercase label used above titles and in cards.
#let eyebrow(body, color: accent) = text(size: 16pt, weight: "bold", tracking: 0.14em, fill: color, upper(body))

// ------------------------------------------------------------------ state ---
#let section-state = state("suig-section", none)

// ---------------------------------------------------------------- slides ----
#let robot-animation = glissade.touying(touying-fn-wrapper, fps: 12)

#let _footer(self) = {
  set text(size: 14pt, fill: faint)
  // Thin progress line, then author and page number.
  utils.touying-progress(ratio => {
    block(width: 100%, height: 2.5pt, fill: hairline, radius: 2pt,
      align(left, box(width: ratio * 100%, height: 2.5pt, fill: accent.lighten(30%), radius: 2pt)))
  })
  v(9pt)
  grid(columns: (1fr, auto),
    self.store.footer-left,
    context [#utils.slide-counter.display() / #utils.last-slide-number],
  )
}

/// A content slide: section label, title, then the body. With `id`, the body
/// is a Glissade animation embedded as Touying subslides.
#let slide(title: none, id: none, section: auto, config: (:), body) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-page(footer: _footer))
  let content = {
    if title != none {
      context {
        let label = if section == auto { section-state.get() } else { section }
        if label != none { eyebrow(label) }
      }
      v(8pt)
      block(above: 0pt, below: 30pt, text(size: 42pt, weight: "bold", fill: ink, title))
    }
    if id != none { robot-animation(id: id, body) } else { body }
  }
  touying-slide(self: self, config: config, content)
})

#let title-slide(title: [], subtitle: [], author: [], affiliation: [], collaborators: none, picture: none) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-common(freeze-slide-counter: true), config-page(footer: none, margin: (x: 84pt, y: 0pt)))
  touying-slide(self: self, {
    set align(horizon)
    eyebrow[Mobile robots · Formal models]
    v(18pt)
    text(size: 58pt, weight: "bold", fill: ink, title)
    v(10pt)
    text(size: 30pt, fill: accent, subtitle)
    v(34pt)
    line(length: 120pt, stroke: 2pt + accent)
    v(22pt)
    text(size: 27pt, weight: "bold", author)
    linebreak()
    text(size: 21pt, fill: muted, affiliation)
    if collaborators != none {
      v(14pt)
      text(size: 17pt, fill: muted, collaborators)
    }
    if picture != none {
      v(30pt)
      picture
    }
  })
})

/// A divider: large section number, title and one-line summary.
#let section-slide(number, title, summary) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-page(footer: _footer))
  touying-slide(self: self, {
    section-state.update(title)
    set align(horizon)
    grid(columns: (170pt, 1fr), column-gutter: 30pt,
      text(size: 120pt, weight: "light", fill: accent.lighten(55%), number),
      {
        text(size: 48pt, weight: "bold", fill: ink, title)
        v(14pt)
        text(size: 26pt, fill: muted, summary)
      },
    )
  })
})

#let suig-theme(footer: [], body) = {
  show: touying-slides.with(
    config-page(
      width: 1280pt, height: 720pt,
      margin: (x: 72pt, top: 54pt, bottom: 70pt),
      footer-descent: 22pt,
      fill: paper,
    ),
    config-common(
      slide-fn: slide,
      handout: handout,
      breakable: false,
      enable-frozen-states-and-counters: false,
    ),
    config-colors(primary: accent, neutral-lightest: paper, neutral-darkest: ink),
    config-store(footer-left: footer),
    config-methods(init: (self: none, body) => {
      set text(font: "Lato", size: 30pt, fill: ink, weight: "regular")
      show math.equation: set text(font: "New Computer Modern Math")
      set par(leading: 0.62em, spacing: 0.9em)
      set list(indent: 4pt, body-indent: 14pt, spacing: 16pt, marker: text(fill: accent, sym.bullet))
      set enum(indent: 4pt, body-indent: 14pt, spacing: 16pt)
      show strong: set text(weight: "bold")
      show link: set text(fill: accent)
      set raw(syntaxes: "sim.sublime-syntax", theme: "sim.tmTheme")
      // Typst already sets raw text to 0.8em; these factors apply on top.
      show raw: set text(font: "DejaVu Sans Mono")
      show raw.where(block: false): set text(size: 1.1em)
      show raw.where(block: true): set text(size: 0.8em)
      show raw.where(block: true): it => block(
        width: 100%, inset: (x: 22pt, y: 18pt), radius: 12pt, fill: tint, it,
      )
      body
    }),
  )
  body
}

// ------------------------------------------------------ animation driver ----
/// One scalar `t` per animated slide, from round 0 to `last`. The speaker
/// continues at every round listed in `stops`; `loop` repeats the last round.
#let run(last, duration: 0.7, stops: auto, loop: false, start: 0) = {
  init(t: if handout { float(last) } else { float(start) })
  if not handout {
    for round in range(start + 1, last + 1) {
      animate(t: float(round), duration: duration)
      if stops == auto or round in stops { cut(loop: loop and round == last) }
    }
  }
}

/// The interpolated configuration of a recorded trace at time `t`.
#let state-at(name, t) = {
  let trace = recordings.at(name)
  let last = trace.states.len() - 1
  let i = calc.min(last, calc.max(0, int(calc.floor(t))))
  let next = calc.min(last, i + 1)
  let progress = if i == last { 0 } else { calc.clamp(t - i, 0, 1) }
  let start = trace.states.at(i)
  let finish = trace.states.at(next)
  (
    positions: start.positions.zip(finish.positions).map(((x, y)) => float(x) + progress * (y - x)),
    crashed: if progress > 0 { finish.crashed } else { start.crashed },
    round: i,
    progress: progress,
    occupied: if progress > 0.5 { finish.occupiedCount } else { start.occupiedCount },
    nodes: if progress > 0.5 { finish.occupied } else { start.occupied },
    rules: if i < trace.rules.len() { trace.rules.at(i) } else { () },
    last: last,
  )
}

// ------------------------------------------------------------ the line ------
/// Robots on a line. `positions` may be fractional (interpolation).
/// - views: ((center, radius), ...) drawn as rounded windows.
/// - dim: positions drawn faded (e.g. outside a robot's view).
/// - tags: ((position, label, color), ...) small labels under robots; add
///   "above" as a fourth element to put the label above the line.
/// - arrows: ((from, to, color), ...) moves drawn above the line.
#let line-view(
  positions, low: auto, high: auto, width: 1100, crashed: (),
  views: (), dim: (), tags: (), arrows: (), labels: false, height: 104,
  highlight: none, highlight-color: teal, bits: none,
) = {
  if low == auto { low = int(calc.floor(calc.min(..positions))) - 1 }
  if high == auto { high = int(calc.ceil(calc.max(..positions))) + 1 }
  let step = width / calc.max(1, high - low)
  let x = p => (p - low) * step
  let y0 = 52
  let r = calc.min(16, step * 0.36)
  cetz.canvas(length: 1pt, {
    import cetz.draw: *
    // Reserve the full lane so that changing labels never move the layout.
    rect((-14, 0), (width + 14, height), stroke: none, fill: none)
    for (center, radius) in views {
      let a = x(calc.max(low, center - radius)) - step * 0.42
      let b = x(calc.min(high, center + radius)) + step * 0.42
      rect((a, y0 - 25), (b, y0 + 25), radius: 11, fill: teal.lighten(90%), stroke: 1.4pt + teal)
    }
    if highlight != none {
      let (a, b) = highlight
      rect((x(a) - step * 0.4, y0 - 21), (x(b) + step * 0.4, y0 + 21), radius: 10, fill: none,
        stroke: (paint: highlight-color, thickness: 1.6pt, dash: "dashed"))
    }
    line((-10, y0), (width + 10, y0), stroke: 1.2pt + hairline.darken(12%))
    for node in range(low, high + 1) {
      circle((x(node), y0), radius: 3, fill: white, stroke: 1pt + faint)
      if labels { content((x(node), y0 - 36), text(size: 15pt, fill: faint)[#node]) }
    }
    // The 0/1 occupancy vector a robot reads, written under its window.
    if bits != none {
      let (center, radius) = bits
      for node in range(center - radius, center + radius + 1) {
        let occupied = positions.any(p => calc.abs(p - node) < 0.01)
        content((x(node), y0 - 42), text(size: 20pt, weight: "bold", font: "DejaVu Sans Mono",
          fill: if node == center { accent } else { teal }, if occupied [1] else [0]))
      }
    }
    // Group robots that share a (possibly interpolated) position.
    let groups = (:)
    for (i, p) in positions.enumerate() {
      let key = str(calc.round(p, digits: 3))
      let entry = groups.at(key, default: (p: p, n: 0, crashed: 0))
      entry.n += 1
      if crashed.len() > i and crashed.at(i) { entry.crashed += 1 }
      groups.insert(key, entry)
    }
    for (_, g) in groups {
      let faded = dim.any(d => calc.abs(d - g.p) < 0.01)
      let all-crashed = g.crashed == g.n
      let fill = if all-crashed { alert } else { accent }
      if faded { fill = fill.lighten(70%) }
      let stroke = if g.crashed > 0 and not all-crashed { 3pt + alert } else { 2pt + white }
      circle((x(g.p), y0), radius: r, fill: fill, stroke: stroke)
      if all-crashed {
        let d = r * 0.42
        line((x(g.p) - d, y0 - d), (x(g.p) + d, y0 + d), stroke: 2.2pt + white)
        line((x(g.p) - d, y0 + d), (x(g.p) + d, y0 - d), stroke: 2.2pt + white)
      } else if g.n > 1 {
        content((x(g.p), y0), text(size: 17pt, weight: "bold", fill: white)[#g.n])
      }
    }
    // A tag is (position, label, color) or (position, label, color, "above").
    for tag in tags {
      let (p, label, color) = (tag.at(0), tag.at(1), tag.at(2))
      let y = if tag.len() > 3 and tag.at(3) == "above" { y0 + r + 19 } else { y0 - r - 19 }
      content((x(p), y), text(size: 18pt, weight: "bold", fill: color, label))
    }
    for (from, to, color) in arrows {
      if from != to {
        let dir = if to > from { 1 } else { -1 }
        bezier((x(from) + dir * 4, y0 + r + 6), (x(to) - dir * 4, y0 + r + 6),
          ((x(from) + x(to)) / 2, y0 + r + 26), stroke: 2pt + color, mark: (end: ">", fill: color))
      }
    }
  })
}

// Union of every position of a trace (to keep its lane fixed).
#let span-of(name) = {
  let all = recordings.at(name).states.map(s => s.positions).flatten()
  (calc.min(..all), calc.max(..all))
}

/// Occupied-node counter with its parity, colored by what it means here.
#let parity-badge(count) = {
  let odd = calc.rem(count, 2) == 1
  box(inset: (x: 10pt, y: 6pt), radius: 8pt, fill: if odd { teal-soft } else { alert-soft },
    text(size: 19pt, weight: "bold", fill: if odd { teal } else { alert })[
      #count #if count == 1 [node] else [nodes] · #if odd [odd] else [even]
    ])
}

/// Whether the occupied nodes mirror each other across an edge (weak
/// multiplicity: robots cannot see the counts, so they are ignored).
#let edge-symmetric(occupied) = {
  let total = occupied.first() + occupied.last()
  calc.rem(total, 2) != 0 and occupied.all(p => occupied.contains(total - p))
}

#let symmetry-badge(occupied) = {
  let (label, fg, bg) = if occupied.len() == 1 { ([gathered], teal, teal-soft) }
    else if edge-symmetric(occupied) { ([edge-symmetric], alert, alert-soft) }
    else { ([#occupied.len() nodes], muted, tint) }
  box(inset: (x: 10pt, y: 6pt), radius: 8pt, fill: bg, text(size: 19pt, weight: "bold", fill: fg, label))
}

/// A recorded execution at time `t`: the line, the round and either the
/// number of occupied nodes with its parity (`badge: "parity"`) or whether the
/// configuration is edge-symmetric (`badge: "symmetry"`).
#let lane(name, t, low: auto, high: auto, label: none, label-color: muted,
  tags: (), views: (), dim: (), stats: true, badge: "parity", height: 104) = {
  let frame = state-at(name, t)
  let (lo, hi) = span-of(name)
  if low == auto { low = lo - 1 }
  if high == auto { high = hi + 1 }
  let label-width = if label != none { 180 } else { 0 }
  let width = 1136 - label-width - 180 - 36
  let view = line-view(frame.positions, low: low, high: high, width: width,
    crashed: frame.crashed, tags: tags, views: views, dim: dim, height: height)
  let side = if stats {
    stack(spacing: 8pt,
      text(size: 19pt, weight: "bold", fill: muted)[Round #frame.round],
      if badge == "parity" { parity-badge(frame.occupied) } else { symmetry-badge(frame.nodes) },
    )
  }
  grid(columns: (label-width * 1pt, width * 1pt, 180pt), column-gutter: 18pt, align: horizon,
    if label != none { text(size: 21pt, weight: "bold", fill: label-color, label) },
    view, side)
}

// ------------------------------------------------------ rule pictograms -----
/// A local view as in the paper: `cells` from left to right, with "[X]" the
/// observer, "X" a robot, "." an empty node, "∅" / "¬∅" / "*" for the unseen
/// rest of a side. `move` is "left", "right" or "stay".
#let rule-view(cells, move: "stay", color: accent) = {
  let w = 34
  let me = cells.position(c => c == "[X]")
  cetz.canvas(length: 1pt, {
    import cetz.draw: *
    let xs = range(cells.len()).map(i => i * w)
    for i in range(cells.len() - 1) {
      if cells.at(i) not in ("∅", "¬∅", "*") and cells.at(i + 1) not in ("∅", "¬∅", "*") {
        line((xs.at(i), 0), (xs.at(i + 1), 0), stroke: 1pt + faint)
      }
    }
    for (i, c) in cells.enumerate() {
      let p = (xs.at(i), 0)
      if c == "[X]" { rect((p.at(0) - 10, -10), (p.at(0) + 10, 10), fill: color, stroke: none) }
      else if c == "X" { circle(p, radius: 9, fill: ink, stroke: none) }
      else if c == "." { circle(p, radius: 6, fill: white, stroke: 1.2pt + muted) }
      else { content(p, text(size: 16pt, fill: muted, c)) }
    }
    let mx = xs.at(me)
    if move == "stay" {
      arc((mx - 7, 16), start: 200deg, stop: -20deg, radius: 11, stroke: 2pt + color, mark: (end: ">", fill: color))
    } else {
      let dir = if move == "right" { 1 } else { -1 }
      line((mx, 21), (mx + dir * 30, 21), stroke: 2.4pt + color, mark: (end: ">", fill: color))
    }
  })
}

// ----------------------------------------------------- results map ----------
/// Solvability for oblivious robots when O_init is odd: columns H_init,
/// rows phi - H_init. `focus` lists cells (h, extra) to emphasize.
#let results-map(focus: (), dim-others: false, cell: 76pt) = {
  let status(h, e) = {
    if h == 1 { "solved" }
    else if e == 0 { if h <= 3 { "impossible" } else { "open" } }
    else if h == 2 and e == 1 { "open" }
    else { "solved" }
  }
  let style = (
    solved: (teal-soft, teal, sym.checkmark),
    impossible: (alert-soft, alert, sym.times),
    open: (amber-soft, amber, [?]),
  )
  let heights = (0, 1, 2, 3)
  let hs = (1, 2, 3, 4, 5, 6)
  let body = ()
  for e in heights.rev() {
    body.push(align(right + horizon, text(size: 21pt, fill: muted,
      if e == 0 { $phi = H$ } else { $phi = H + #e$ })))
    for h in hs {
      let s = status(h, e)
      let (bg, fg, mark) = style.at(s)
      let focused = focus.contains((h, e))
      let faded = dim-others and not focused
      body.push(box(width: cell, height: cell * 0.7, radius: 8pt,
        fill: if faded { bg.lighten(55%) } else { bg },
        stroke: if focused { 2.5pt + fg } else { none },
        align(center + horizon, text(size: 24pt, weight: "bold", fill: if faded { fg.lighten(55%) } else { fg }, mark))))
    }
  }
  body.push([])
  for h in hs { body.push(align(center, text(size: 21pt, fill: muted, if h == 6 { $H >= 6$ } else { $H = #h$ }))) }
  grid(columns: (110pt,) + hs.map(_ => cell), column-gutter: 8pt, row-gutter: 8pt, ..body)
}
