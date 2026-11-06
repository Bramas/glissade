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
  // The section name sits in the corner, next to the page number.
  pad(x: 72pt, grid(columns: (1fr, auto, auto), column-gutter: 22pt,
    self.store.footer-left,
    context {
      let label = if self.store.section == auto { section-state.get() } else { self.store.section }
      if label != none { text(fill: muted, label) }
    },
    context [#utils.slide-counter.display() / #utils.last-slide-number],
  ))
}

/// A content slide: a title, then the body. With `id`, the body is a Glissade
/// animation embedded as Touying subslides. `section` overrides the section
/// name shown in the footer.
#let slide(title: none, id: none, section: auto, config: (:), body) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-page(footer: _footer), config-store(section: section))
  let content = {
    if title != none {
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
  let self = utils.merge-dicts(self, config-page(footer: _footer), config-store(section: none))
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
    config-store(footer-left: footer, section: auto),
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

/// Several executions on one slide, played one after the other so that only
/// one thing moves at a time. Each phase is (variable, last round, stops, loop):
/// the speaker continues at every round in `stops`, and `loop` repeats the
/// last round of that phase until the speaker continues.
#let run-phases(..phases, duration: 0.7) = {
  let phases = phases.pos()
  let start = (:)
  for (name, last, ..) in phases { start.insert(name, if handout { float(last) } else { 0.0 }) }
  init(..start)
  if not handout {
    for (name, last, stops, loop) in phases {
      for round in range(1, last + 1) {
        animate(..((name): float(round)), duration: duration)
        if round in stops or round == last { cut(loop: loop and round == last) }
      }
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

/// Whether the occupied nodes mirror each other across an edge (robots have
/// no multiplicity detection, so the counts are ignored).
#let edge-symmetric(occupied) = {
  let total = occupied.first() + occupied.last()
  calc.rem(total, 2) != 0 and occupied.all(p => occupied.contains(total - p))
}

/// The number of occupied nodes, without judging it.
#let count-badge(occupied) = {
  let (label, fg, bg) = if occupied.len() == 1 { ([gathered], teal, teal-soft) } else { ([#occupied.len() nodes], muted, tint) }
  box(inset: (x: 10pt, y: 6pt), radius: 8pt, fill: bg, text(size: 19pt, weight: "bold", fill: fg, label))
}

#let symmetry-badge(occupied) = {
  let (label, fg, bg) = if occupied.len() == 1 { ([gathered], teal, teal-soft) }
    else if edge-symmetric(occupied) { ([edge-symmetric], alert, alert-soft) }
    else { ([#occupied.len() nodes], muted, tint) }
  box(inset: (x: 10pt, y: 6pt), radius: 8pt, fill: bg, text(size: 19pt, weight: "bold", fill: fg, label))
}

/// A recorded execution at time `t`: the line, the round and a badge: the
/// number of occupied nodes with its parity (`"parity"`), alone (`"count"`), or
/// whether the configuration is edge-symmetric (`"symmetry"`).
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
      if badge == "parity" { parity-badge(frame.occupied) }
      else if badge == "count" { count-badge(frame.nodes) }
      else { symmetry-badge(frame.nodes) },
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

// ------------------------------------------------------- model builder ------
// A model is drawn as a card of rows, one per assumption. Rows start as the
// choices a paper makes in prose and become `field := value` lines of `.sim`.
// Everything is placed on a fixed grid so that values can travel between the
// option cards on the right and their row on the left.

#let mono = "DejaVu Sans Mono"
#let geo = (width: 1136, height: 492, card: 610, top: 64, row: 56, pad: 24, panel: 640, gap: 12, inset: 16)

/// Inline `.sim` code at an exact size (raw text is scaled by 0.8 × 1.1).
#let code(source, size: 18pt) = text(size: size / 0.88, raw(source, lang: "sim"))

/// Smooth step of `t` from `a` to `b`, clamped to [0, 1].
#let ease(t, a, b) = {
  let x = calc.clamp((t - a) / (b - a), 0, 1)
  x * x * (3 - 2 * x)
}
#let lerp(a, b, x) = a + (b - a) * x
#let alpha(color, opacity) = color.transparentize((1 - calc.clamp(opacity, 0, 1)) * 100%)
#let blend(a, b, x) = color.mix((a, (1 - x) * 100%), (b, x * 100%), space: rgb)

// Places `body` with its top-left corner at (x, y), in points.
#let at(x, y, body) = place(top + left, dx: x * 1pt, dy: y * 1pt, body)

/// Covers a region with the background color: 0 shows it, 1 hides it.
#let veil(x, y, w, h, amount, bg: paper) = if amount > 0.001 {
  at(x, y, rect(width: w * 1pt, height: h * 1pt, stroke: none, fill: alpha(bg, amount)))
}

#let _row-y(k) = geo.top + k * geo.row
#let _code-dy = 17
#let _indent = 2

/// The `field := ` prefix of a row, drawn as plain monospace text so that it
/// can fade.
#let _field(name, opacity: 1) = text(font: mono, size: 18pt, {
  text(fill: alpha(ink, opacity), name)
  text(fill: alpha(muted, opacity), " := ")
})

#let _card-background() = at(0, 0, rect(width: geo.card * 1pt, height: geo.height * 1pt, radius: 14pt, fill: tint))

#let _band(k, strength, color: accent-soft) = if strength > 0.001 {
  at(8, _row-y(k) + 2, rect(width: (geo.card - 16) * 1pt, height: (geo.row - 4) * 1pt, radius: 9pt,
    fill: blend(tint, color, strength)))
}

/// One option on the right: the `.sim` value, a caption and, for library
/// definitions, their source.
#let _option-card(option, x, y, w, height, chosen: 0) = {
  at(x, y, rect(width: w * 1pt, height: height * 1pt, radius: 12pt, fill: tint,
    stroke: if chosen > 0.001 { 2.4pt + alpha(accent, chosen) } else { none }))
  at(x + geo.inset, y + geo.inset, block(width: (w - 2 * geo.inset) * 1pt, {
    set par(leading: 0.42em, spacing: 0pt)
    let caption = option.at("caption", default: none)
    let source = option.at("source", default: none)
    if caption != none and source != none {
      // Short caption on the title line, to leave room for the source.
      code(option.value)
      h(1fr)
      text(size: 18pt, fill: muted, caption)
    } else {
      code(option.value)
      if caption != none {
        v(9pt)
        text(size: 18pt, fill: muted, caption)
      }
    }
    if option.at("source", default: none) != none {
      v(12pt)
      code(option.source, size: 15pt)
    }
  }))
}

#let _panel-cards(choice) = {
  let n = choice.options.len()
  let foot = if choice.at("footnote", default: none) != none { 70 } else { 0 }
  let h = (geo.height - foot - geo.gap * (n - 1)) / n
  let w = geo.width - geo.panel
  range(n).map(i => (x: geo.panel, y: i * (h + geo.gap), w: w, h: h))
}

/// The build of a model, one assumption at a time, as a function of `t`.
/// For row k: at 2k + 1 the row is highlighted and its options appear on the
/// right; at 2k + 2 the chosen value moves into the row. At 2n + 1 the card is
/// a complete `.sim` definition named `name`, and `outro` replaces the options.
#let model-builder(choices, t, name: "", intro: none, outro: none) = context {
  let n = choices.len()
  let cw = measure(text(font: mono, size: 18pt, "0")).width / 1pt
  let final = 2 * n
  box(width: geo.width * 1pt, height: geo.height * 1pt, {
    _card-background()
    // Header: a label, then the definition line.
    let header-out = ease(t, final, final + 0.5)
    at(geo.pad, 22, text(size: 16pt, weight: "bold", tracking: 0.14em, fill: alpha(accent, 1 - header-out), upper[A robot model]))
    if t > final + 0.5 {
      at(geo.pad, 20, code("def " + name + " : Model where"))
      veil(geo.pad - 4, 12, geo.card - geo.pad - 8, 34, 1 - ease(t, final + 0.5, final + 1), bg: tint)
    }
    // Rows.
    let flights = ()
    for (k, choice) in choices.enumerate() {
      let y = _row-y(k)
      let on = ease(t, 2 * k, 2 * k + 1) - ease(t, 2 * k + 2, 2 * k + 3)
      _band(k, on)
      let prose = 1 - ease(t, 2 * k + 1.2, 2 * k + 1.45)
      if prose > 0.001 {
        at(geo.pad, y + 12, text(size: 24pt, weight: "bold", fill: alpha(blend(ink, accent, on), prose), choice.label))
        at(geo.pad + 196, y + 14, text(size: 22pt, fill: alpha(muted, prose), choice.prose))
      }
      let x0 = geo.pad + _indent * cw
      let field = ease(t, 2 * k + 1.6, 2 * k + 1.9)
      if field > 0.001 { at(x0, y + _code-dy, _field(choice.field, opacity: field)) }
      // The chosen value travels from its option card to the row.
      let travel = ease(t, 2 * k + 1.2, 2 * k + 1.85)
      if t > 2 * k + 1.2 {
        let card = _panel-cards(choice).at(choice.pick)
        let from = (card.x + geo.inset, card.y + geo.inset)
        let to = (x0 + (choice.field.len() + 4) * cw, y + _code-dy)
        flights.push(at(lerp(from.at(0), to.at(0), travel), lerp(from.at(1), to.at(1), travel),
          code(choice.options.at(choice.pick).value)))
      }
    }
    // Right panel: intro, then the options of each row, then the outro.
    if intro != none and t < 0.5 {
      at(geo.panel, 0, block(width: (geo.width - geo.panel) * 1pt, height: geo.height * 1pt, align(horizon, intro)))
      veil(geo.panel, 0, geo.width - geo.panel, geo.height, ease(t, 0, 0.5))
    }
    for (k, choice) in choices.enumerate() {
      let shown = ease(t, 2 * k + 0.5, 2 * k + 1) - ease(t, 2 * k + 2, 2 * k + 2.5)
      if shown > 0.001 {
        let cards = _panel-cards(choice)
        let chosen = ease(t, 2 * k + 1, 2 * k + 1.2)
        for (i, option) in choice.options.enumerate() {
          let c = cards.at(i)
          let mine = i == choice.pick
          _option-card(option, c.x, c.y, c.w, c.h, chosen: if mine { chosen } else { 0 })
          let hide = 1 - shown + if mine { 0 } else { 0.62 * chosen * shown }
          veil(c.x - 2, c.y - 2, c.w + 4, c.h + 4, hide)
        }
        let note = choice.at("footnote", default: none)
        if note != none {
          at(geo.panel + 4, geo.height - 56, block(width: (geo.width - geo.panel - 8) * 1pt,
            text(size: 19pt, fill: alpha(muted, shown), note)))
        }
      }
    }
    if outro != none and t > final + 0.5 {
      at(geo.panel, 0, block(width: (geo.width - geo.panel) * 1pt, height: geo.height * 1pt, align(horizon, outro)))
      veil(geo.panel, 0, geo.width - geo.panel, geo.height, 1 - ease(t, final + 0.5, final + 1))
    }
    for flight in flights { flight }
  })
}

/// A complete model card, changing from one model to the next as `t` goes
/// from i to i + 1. Rows that differ from the first model are highlighted.
/// Each model is (name, rows: ((field, value), ...), side: content).
#let model-variants(models, t) = context {
  let cw = measure(text(font: mono, size: 18pt, "0")).width / 1pt
  let i = calc.min(models.len() - 1, int(calc.floor(t)))
  let j = calc.min(models.len() - 1, i + 1)
  let p = if i == j { 0 } else { t - i }
  let (a, b) = (models.at(i), models.at(j))
  let base = models.first()
  let changed(m, k) = m.rows.at(k) != base.rows.at(k)
  let x0 = geo.pad + _indent * cw
  box(width: geo.width * 1pt, height: geo.height * 1pt, {
    _card-background()
    // Header.
    let (head, cover) = if p < 0.45 { (a, ease(p, 0, 0.45)) } else { (b, 1 - ease(p, 0.45, 0.9)) }
    at(geo.pad, 20, code("def " + head.name + " : Model where"))
    veil(geo.pad - 4, 12, geo.card - geo.pad - 8, 34, cover, bg: tint)
    for k in range(a.rows.len()) {
      let y = _row-y(k)
      let strength = lerp(if changed(a, k) { 1 } else { 0 }, if changed(b, k) { 1 } else { 0 }, ease(p, 0, 0.3))
      _band(k, strength)
      let bg = blend(tint, accent-soft, strength)
      let (field, old) = a.rows.at(k)
      let new = b.rows.at(k).at(1)
      at(x0, y + _code-dy, _field(field))
      let vx = x0 + (field.len() + 4) * cw
      if old == new {
        at(vx, y + _code-dy, code(old))
      } else if p < 0.6 {
        at(vx, y + _code-dy, code(old))
        veil(vx - 2, y + 8, geo.card - vx - 10, geo.row - 16, ease(p, 0.3, 0.6), bg: bg)
      } else {
        at(vx, y + _code-dy, code(new))
        veil(vx - 2, y + 8, geo.card - vx - 10, geo.row - 16, 1 - ease(p, 0.6, 0.9), bg: bg)
      }
    }
    // Right side: what the model says, in words, or one label per row.
    let (side, cover) = if p < 0.45 { (a, ease(p, 0, 0.45)) } else { (b, 1 - ease(p, 0.45, 0.9)) }
    if side.at("tags", default: none) != none {
      for (k, tag) in side.tags.enumerate() {
        if tag != none {
          let (label, color) = tag
          at(geo.card + 22, _row-y(k) + 11, pill(label, color: color))
        }
      }
    } else {
      at(geo.panel, 0, block(width: (geo.width - geo.panel) * 1pt, height: geo.height * 1pt, align(horizon, side.side)))
    }
    veil(geo.card + 12, 0, geo.width - geo.card - 12, geo.height, cover)
  })
}
