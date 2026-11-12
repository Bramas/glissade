// A quiet conference theme for Touying, and the drawings of robots on a line.
#import "@preview/touying:0.7.3": *
#import "../../lib.typ" as glissade
#import "../../lib.typ": init, animate, cut

// ---------------------------------------------------------------- palette ---
// Every color has one meaning across the talk. The neutrals are dark enough
// to survive a projector: nothing that carries information is paler than
// `faint`.
#let ink = rgb("#161a24")
#let muted = rgb("#566173")
#let faint = rgb("#94a0b1")
#let rail = rgb("#c3cbd8") // the line the robots live on
#let hairline = rgb("#dfe4ec")
#let paper = white
#let tint = rgb("#f2f4f8")
#let accent = rgb("#2c5cc5") // robots and emphasis
#let accent-soft = rgb("#e6edfb")
#let teal = rgb("#0b8577") // views, moves, things that work
#let teal-soft = rgb("#dcf1ed")
#let alert = rgb("#c8402f") // crashes and failures
#let alert-soft = rgb("#fbe7e3")
#let amber = rgb("#a86a12") // open questions
#let amber-soft = rgb("#fbefd6")

#let handout = sys.inputs.at("handout", default: "false") == "true"
#let recordings = json("traces.json").traces

// ------------------------------------------------------------ typography ---
#let mono = "DejaVu Sans Mono"
#let note(body) = text(size: 22pt, fill: muted, body)
#let lead(body) = block(above: 0pt, below: 0pt, text(size: 32pt, fill: ink, body))
#let em-accent(body) = text(fill: accent, weight: "bold", body)
#let em-teal(body) = text(fill: teal, weight: "bold", body)
#let em-alert(body) = text(fill: alert, weight: "bold", body)
#let em-amber(body) = text(fill: amber, weight: "bold", body)

#let pill(body, color: accent, fill: auto) = box(
  inset: (x: 12pt, y: 6pt), radius: 99pt,
  fill: if fill == auto { color.lighten(87%) } else { fill },
  text(size: 20pt, weight: "bold", fill: color, body),
)

// A soft panel that groups related content.
#let card(body, fill: tint, stroke: none, inset: 22pt, width: 100%, height: auto) = block(
  width: width, height: height, inset: inset, radius: 12pt, fill: fill, stroke: stroke, body,
)

// Small uppercase label used above titles and in cards.
#let eyebrow(body, color: accent, size: 17pt) = text(size: size, weight: "bold", tracking: 0.14em, fill: color, upper(body))

/// Inline `.sim` code at an exact size (raw text is scaled by 0.8 × 1.1).
#let code(source, size: 18pt) = text(size: size / 0.88, raw(source, lang: "sim"))

// -------------------------------------------------------------- geometry ---
// Drawings are placed in points from the top-left corner of their box: no
// drawing package, so a frame of animation costs a few placements.

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

#let _disc(cx, cy, r, ..style) = at(cx - r, cy - r, circle(radius: r * 1pt, ..style))
#let _segment(x1, y1, x2, y2, stroke) = at(0, 0,
  line(start: (x1 * 1pt, y1 * 1pt), end: (x2 * 1pt, y2 * 1pt), stroke: stroke))
// Content centered on a point.
#let _centered(cx, cy, body, width: 280, height: 44) = at(cx - width / 2, cy - height / 2,
  box(width: width * 1pt, height: height * 1pt, align(center + horizon, body)))
// A straight arrow between two points.
#let _arrow(x1, y1, x2, y2, color, thickness: 2.6, head: 10) = {
  let length = calc.sqrt(calc.pow(x2 - x1, 2) + calc.pow(y2 - y1, 2))
  let (ux, uy) = ((x2 - x1) / length, (y2 - y1) / length)
  let (bx, by) = (x2 - ux * head, y2 - uy * head)
  let half = head * 0.55
  _segment(x1, y1, bx, by, (paint: color, thickness: thickness * 1pt, cap: "round"))
  at(0, 0, polygon(fill: color, stroke: (paint: color, thickness: 1pt, join: "round"),
    (x2 * 1pt, y2 * 1pt),
    ((bx - uy * half) * 1pt, (by + ux * half) * 1pt),
    ((bx + uy * half) * 1pt, (by - ux * half) * 1pt)))
}

// ------------------------------------------------------------------ state ---
#let section-state = state("suig-section", none)

// ---------------------------------------------------------------- slides ----
#let robot-animation = glissade.touying(touying-fn-wrapper, fps: 24)

#let _footer(self) = {
  set text(size: 15pt, fill: faint)
  // Thin progress line, then author and page number.
  utils.touying-progress(ratio => {
    block(width: 100%, height: 3pt, fill: hairline,
      align(left, box(width: ratio * 100%, height: 3pt, fill: accent.lighten(25%))))
  })
  v(9pt)
  // The section name sits in the corner, next to the page number.
  pad(x: 72pt, grid(columns: (1fr, auto, auto), column-gutter: 22pt,
    self.store.footer-left,
    context {
      let label = if self.store.section == auto { section-state.get() } else { self.store.section }
      if label != none { text(fill: muted, label) }
    },
    context text(fill: muted)[#utils.slide-counter.display() / #utils.last-slide-number],
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

#let title-slide(title: [], subtitle: [], author: [], affiliation: [], collaborators: none, picture: none, eyebrow: none) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-common(freeze-slide-counter: true),
    config-page(footer: none, margin: (x: 84pt, top: 78pt, bottom: 60pt)))
  touying-slide(self: self, {
    if eyebrow != none {
      text(size: 17pt, weight: "bold", tracking: 0.14em, fill: accent, upper(eyebrow))
      v(26pt)
    }
    block(above: 0pt, below: 0pt, {
      set par(leading: 0.36em)
      text(size: 62pt, weight: "bold", fill: ink, title)
    })
    v(30pt)
    text(size: 31pt, fill: accent, subtitle)
    v(1fr)
    if picture != none { picture }
    v(1fr)
    grid(columns: (1fr, auto), align: (left + bottom, right + bottom),
      {
        text(size: 28pt, weight: "bold", author)
        linebreak()
        text(size: 22pt, fill: muted, affiliation)
      },
      if collaborators != none {
        set align(right)
        text(size: 18pt, fill: muted, collaborators)
      },
    )
  })
})

/// The plan of the talk: one row per section of the theme.
#let outline-slide(title: [Outline]) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-page(footer: _footer), config-store(section: none))
  let sections = self.store.sections
  touying-slide(self: self, {
    block(above: 0pt, below: 30pt, text(size: 42pt, weight: "bold", fill: ink, title))
    v(1fr)
    grid(columns: (96pt, 1fr), row-gutter: 0pt,
      ..sections.enumerate().map(((k, s)) => (
        grid.cell(inset: (y: 19pt), stroke: if k > 0 { (top: 1.5pt + hairline) },
          text(size: 40pt, fill: accent, weight: "bold", "0" + str(k + 1))),
        grid.cell(inset: (y: 19pt), stroke: if k > 0 { (top: 1.5pt + hairline) }, {
          text(weight: "bold", s.title)
          linebreak()
          note(s.note)
        }),
      )).flatten(),
    )
    v(1.4fr)
  })
})

/// A divider: large section number, title and one-line summary, above the
/// plan of the talk with the current section marked.
#let section-slide(index) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-page(footer: _footer), config-store(section: none))
  let sections = self.store.sections
  let current = sections.at(index - 1)
  touying-slide(self: self, {
    section-state.update(current.title)
    v(1.25fr)
    grid(columns: (200pt, 1fr), column-gutter: 26pt, align: horizon,
      text(size: 132pt, weight: "light", fill: accent.lighten(40%), "0" + str(index)),
      {
        text(size: 52pt, weight: "bold", fill: ink, current.title)
        v(16pt)
        text(size: 27pt, fill: muted, current.summary)
      },
    )
    v(1fr)
    grid(columns: (1fr,) * sections.len(), column-gutter: 16pt,
      ..sections.enumerate().map(((k, s)) => {
        let now = k + 1 == index
        let done = k + 1 < index
        stack(spacing: 12pt,
          block(width: 100%, height: 5pt, radius: 3pt,
            fill: if now { accent } else if done { accent.lighten(62%) } else { hairline }),
          text(size: 18pt, weight: if now { "bold" } else { "regular" },
            fill: if now { ink } else if done { muted } else { faint },
            [#("0" + str(k + 1)) #h(6pt) #s.title]),
        )
      }),
    )
    v(8pt)
  })
})

/// The last slide: a short message above a picture.
#let closing-slide(title: [], subtitle: none, picture: none) = touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-common(freeze-slide-counter: true), config-page(footer: none))
  touying-slide(self: self, align(center + horizon, {
    text(size: 68pt, weight: "bold", title)
    if subtitle != none {
      v(18pt)
      text(size: 31pt, fill: muted, subtitle)
    }
    if picture != none {
      v(40pt)
      picture
    }
  }))
})

#let suig-theme(footer: [], sections: (), body) = {
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
    config-store(footer-left: footer, section: auto, sections: sections),
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
      show raw: set text(font: mono)
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
// Robots start and stop gently at every round: a round is a unit of the
// model, and the pause between two moves is what lets the audience count them.
#let _move = "ease-in-out"

/// One scalar `t` per animated slide, from round 0 to `last`. The speaker
/// continues at every round listed in `stops`. With `loop: n`, the last `n`
/// rounds repeat until the speaker continues.
#let run(last, duration: 0.7, stops: auto, loop: false, start: 0) = {
  init(t: if handout { float(last) } else { float(start) })
  if not handout {
    for round in range(start + 1, last + 1) {
      animate(t: float(round), duration: duration, transition: _move)
      if stops == auto or round in stops { cut(loop: if round == last { loop } else { false }) }
    }
  }
}

/// Several executions on one slide, played one after the other so that only
/// one thing moves at a time. Each phase is (variable, last round, stops, loop):
/// the speaker continues at every round in `stops`, and `loop: n` repeats the
/// last `n` rounds of that phase until the speaker continues.
#let run-phases(..phases, duration: 0.7) = {
  let phases = phases.pos()
  let start = (:)
  for (name, last, ..) in phases { start.insert(name, if handout { float(last) } else { 0.0 }) }
  init(..start)
  if not handout {
    for (name, last, stops, loop) in phases {
      for round in range(1, last + 1) {
        animate(..((name): float(round)), duration: duration, transition: _move)
        if round in stops or round == last { cut(loop: if round == last { loop } else { false }) }
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
  let (from, to) = (start.positions, finish.positions)
  // Two robots that exchange their order would pass through each other and
  // read as one. They leave the line for the time of the move instead: the
  // one going right passes above, the one going left below.
  let swing = calc.sin(progress * 180deg)
  let lifts = range(from.len()).map(a => {
    let crosses = progress > 0 and range(from.len()).any(b => (from.at(a) - from.at(b)) * (to.at(a) - to.at(b)) < 0)
    if crosses { (if to.at(a) > from.at(a) { 1.3 } else { -1.3 }) * swing } else { 0 }
  })
  // Nodes where robots coming from different nodes meet in this round.
  let merging = to.dedup().filter(node => range(to.len()).filter(a => to.at(a) == node).map(a => from.at(a)).dedup().len() > 1)
  let arrival = ease(progress, 0.7, 1)
  let landed = progress > 0.9
  (
    // Robots a hair away from their node are drawn on it: those that merge
    // show their count as they land, not one frame later.
    positions: from.zip(to).map(((x, y)) => float(x) + (if progress > 0.985 { 1 } else { progress }) * (y - x)),
    lifts: lifts,
    pulses: if progress > 0.7 { merging.map(node => (node, arrival)) } else { () },
    crashed: if progress > 0 { finish.crashed } else { start.crashed },
    round: i,
    progress: progress,
    occupied: if landed { finish.occupiedCount } else { start.occupiedCount },
    nodes: if landed { finish.occupied } else { start.occupied },
    settled: if landed { next } else { i },
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
/// - lifts: per robot, how far it leaves the line, in robot radii (up is
///   positive). Robots are grouped only when they share position and lift.
/// - pulses: ((position, progress), ...) rings that open where robots merge.
/// - rail-y: the distance from the top of the box to the line (its middle by
///   default).
#let line-view(
  positions, low: auto, high: auto, width: 1100, crashed: (),
  views: (), dim: (), tags: (), labels: false, height: 120, rail-y: auto,
  highlight: none, highlight-color: teal, bits: none,
  lifts: (), pulses: (), radius: 22, names: (),
) = {
  if low == auto { low = int(calc.floor(calc.min(..positions))) - 1 }
  if high == auto { high = int(calc.ceil(calc.max(..positions))) + 1 }
  let margin = 30
  let step = (width - 2 * margin) / calc.max(1, high - low)
  let x = p => margin + (p - low) * step
  let y0 = if rail-y == auto { height / 2 } else { rail-y }
  let r = calc.min(radius, step * 0.36)
  // The lane keeps its full size, so that changing labels never move the layout.
  box(width: width * 1pt, height: height * 1pt, {
    for (center, reach) in views {
      let a = x(calc.max(low, center - reach)) - step * 0.44
      let b = x(calc.min(high, center + reach)) + step * 0.44
      at(a, y0 - r - 13, rect(width: (b - a) * 1pt, height: (2 * r + 26) * 1pt, radius: 14pt,
        fill: teal-soft, stroke: 1.8pt + teal))
    }
    if highlight != none {
      let (a, b) = highlight
      at(x(a) - step * 0.42, y0 - r - 9, rect(width: (x(b) - x(a) + step * 0.84) * 1pt, height: (2 * r + 18) * 1pt,
        radius: 12pt, fill: none, stroke: (paint: highlight-color, thickness: 2pt, dash: "dashed")))
    }
    _segment(0, y0, width, y0, 2pt + rail)
    for node in range(low, high + 1) {
      _disc(x(node), y0, 4.5, fill: paper, stroke: 1.6pt + faint)
      if labels { _centered(x(node), y0 + r + 22, text(size: 17pt, fill: faint)[#node]) }
    }
    // The 0/1 occupancy vector a robot reads, written under its window.
    if bits != none {
      let (center, reach) = bits
      for node in range(center - reach, center + reach + 1) {
        let occupied = positions.any(p => calc.abs(p - node) < 0.01)
        _centered(x(node), y0 + r + 40, text(size: 22pt, weight: "bold", font: mono,
          fill: if node == center { accent } else { teal }, if occupied [1] else [0]))
      }
    }
    for (node, progress) in pulses {
      _disc(x(node), y0, r * (1.05 + 0.85 * progress), fill: none,
        stroke: (2.6 - 1.2 * progress) * 1pt + alpha(accent, 0.6 * (1 - progress)))
    }
    // Group robots that share a (possibly interpolated) position.
    let groups = (:)
    for (i, p) in positions.enumerate() {
      let lift = lifts.at(i, default: 0)
      let key = str(calc.round(p, digits: 3)) + "/" + str(calc.round(lift, digits: 3))
      let entry = groups.at(key, default: (p: p, lift: lift, n: 0, crashed: 0, name: none))
      entry.n += 1
      // `names` gives some robots a letter, so that the text can refer to them.
      if entry.name == none { entry.name = names.at(i, default: none) }
      if crashed.at(i, default: false) { entry.crashed += 1 }
      groups.insert(key, entry)
    }
    for (_, g) in groups {
      let (cx, cy) = (x(g.p), y0 - g.lift * r)
      let all-crashed = g.crashed == g.n
      let fill = if all-crashed { alert } else { accent }
      if dim.any(d => calc.abs(d - g.p) < 0.01) { fill = fill.lighten(72%) }
      // The white ring keeps overlapping robots apart; a red one marks a
      // crashed robot under correct ones.
      _disc(cx, cy, r, fill: fill,
        stroke: if g.crashed > 0 and not all-crashed { 3.6pt + alert } else { 3pt + paper })
      if all-crashed {
        let d = r * 0.38
        let stroke = (paint: paper, thickness: 3pt, cap: "round")
        _segment(cx - d, cy - d, cx + d, cy + d, stroke)
        _segment(cx - d, cy + d, cx + d, cy - d, stroke)
      } else if g.n > 1 {
        _centered(cx, cy, text(size: r * 0.95pt, weight: "bold", fill: paper)[#g.n])
      } else if g.name != none {
        _centered(cx, cy - r * 0.08, text(size: r * 0.95pt, weight: "bold", fill: paper, g.name))
      }
    }
    // A tag is (position, label, color) or (position, label, color, "above").
    for tag in tags {
      let (p, label, color) = (tag.at(0), tag.at(1), tag.at(2))
      let above = tag.len() > 3 and tag.at(3) == "above"
      _centered(x(p), if above { y0 - r - 25 } else { y0 + r + 25 },
        text(size: 20pt, weight: "bold", fill: color, label))
    }
  })
}

// Union of every position of a trace (to keep its lane fixed).
#let span-of(name) = {
  let all = recordings.at(name).states.map(s => s.positions).flatten()
  (calc.min(..all), calc.max(..all))
}

/// Whether the occupied nodes mirror each other across an edge (robots have
/// no multiplicity detection, so the counts are ignored).
#let edge-symmetric(occupied) = {
  let total = occupied.first() + occupied.last()
  calc.rem(total, 2) != 0 and occupied.all(p => occupied.contains(total - p))
}

#let _badge(label, fg, bg) = box(inset: (x: 12pt, y: 6pt), radius: 8pt, fill: bg,
  text(size: 20pt, weight: "bold", fill: fg, label))
#let _nodes(count) = [#count #if count == 1 [node] else [nodes]]

/// Occupied-node counter with its parity, colored by what it means here.
#let parity-badge(count) = {
  let odd = calc.rem(count, 2) == 1
  _badge([#_nodes(count) · #if odd [odd] else [even]], if odd { teal } else { alert }, if odd { teal-soft } else { alert-soft })
}

/// The number of occupied nodes, without judging it.
#let count-badge(occupied) = if occupied.len() == 1 { _badge([gathered], teal, teal-soft) } else {
  _badge(_nodes(occupied.len()), muted, tint)
}

#let symmetry-badge(occupied) = if occupied.len() == 1 { _badge([gathered], teal, teal-soft) } else if edge-symmetric(occupied) {
  _badge([edge-symmetric], alert, alert-soft)
} else { _badge(_nodes(occupied.len()), muted, tint) }

// Whether two robots of a trace ever exchange their order: its lane then
// needs room above and below the line.
#let _swaps(name) = {
  let states = recordings.at(name).states
  range(states.len() - 1).any(k => {
    let (from, to) = (states.at(k).positions, states.at(k + 1).positions)
    range(from.len()).any(a => range(a).any(b => (from.at(a) - from.at(b)) * (to.at(a) - to.at(b)) < 0))
  })
}

/// The number of occupied nodes at each round reached so far, one cell per
/// recorded round: what happened earlier stays on the slide.
#let round-history(name, settled) = {
  let states = recordings.at(name).states
  grid(columns: states.len() + 1, column-gutter: 6pt, align: horizon,
    pad(right: 12pt, eyebrow(color: muted)[Occupied nodes]),
    ..states.enumerate().map(((k, state)) => {
      let odd = calc.rem(state.occupiedCount, 2) == 1
      let (fg, bg) = if odd { (teal, teal-soft) } else { (alert, alert-soft) }
      let seen = k <= settled
      box(width: 44pt, height: 40pt, radius: 8pt,
        fill: if seen { bg } else { none },
        stroke: if k == settled { 2.4pt + fg } else if seen { none } else { 1.5pt + hairline },
        align(center + horizon, if seen { text(size: 21pt, weight: "bold", fill: fg)[#state.occupiedCount] }))
    }),
  )
}

/// A recorded execution at time `t`: a header with its label, a badge and the
/// round, then the line across the whole slide. The badge is the number of
/// occupied nodes with its parity (`"parity"`), alone (`"count"`), or whether
/// the configuration is edge-symmetric (`"symmetry"`). `tags: none` leaves no
/// room for tags; `history` adds the counts of the past rounds under the line.
#let lane(name, t, low: auto, high: auto, label: none, label-color: muted,
  tags: none, views: (), dim: (), stats: true, badge: "parity", history: false, width: 1136, names: ()) = {
  let frame = state-at(name, t)
  let (lo, hi) = span-of(name)
  if low == auto { low = lo - 1 }
  if high == auto { high = hi + 1 }
  // Room around the line: a robot's radius, plus what swaps and tags need.
  let r = calc.min(22, (width - 60) / calc.max(1, high - low) * 0.36)
  let swaps = _swaps(name)
  let above = if swaps { 2.3 * r + 12 } else { r + 14 }
  let below = if swaps or tags != none { calc.max(2.3 * r + 12, r + 44) } else { r + 14 }
  stack(spacing: 0pt,
    box(width: width * 1pt, height: 36pt, grid(columns: (1fr, auto, 112pt), column-gutter: 14pt,
      align: (left + horizon, right + horizon, right + horizon),
      if label != none { text(size: 23pt, weight: "bold", fill: label-color, label) },
      if stats {
        if badge == "parity" { parity-badge(frame.occupied) }
        else if badge == "count" { count-badge(frame.nodes) }
        else { symmetry-badge(frame.nodes) }
      },
      if stats { text(size: 21pt, weight: "bold", fill: muted)[Round #frame.round] },
    )),
    line-view(frame.positions, low: low, high: high, width: width, crashed: frame.crashed,
      tags: if tags == none { () } else { tags }, views: views, dim: dim,
      height: above + below, rail-y: above, lifts: frame.lifts, pulses: frame.pulses, names: names),
    if history { pad(top: 14pt, round-history(name, frame.settled)) },
  )
}

/// Tags for the robots of a recorded execution, from the rule each one
/// applies. `labels` maps a rule to (label, color) or (label, color, "above");
/// an arrow in the label shows the direction of the recorded move. Tags stay
/// on the node the robot starts from: they fade in as the previous round ends,
/// so the audience reads the decision before the move, and fade out as the
/// robots leave.
#let rule-tags(name, t, labels, rounds: auto) = {
  let trace = recordings.at(name)
  let frame = state-at(name, t)
  let tags-of(round, opacity) = {
    if opacity <= 0.001 or round >= frame.last or (rounds != auto and round not in rounds) { return () }
    let before = trace.states.at(round).positions
    let after = trace.states.at(round + 1).positions
    let seen = ()
    let tags = ()
    for (i, rule) in trace.rules.at(round).enumerate() {
      if rule in labels {
        let entry = labels.at(rule)
        let (label, color) = (entry.at(0), entry.at(1))
        let d = after.at(i) - before.at(i)
        let key = str(before.at(i)) + rule
        if key not in seen {
          seen.push(key)
          tags.push((before.at(i), if d > 0 [#label →] else if d < 0 [← #label] else [#label],
            alpha(color, opacity), if entry.len() > 2 { entry.at(2) } else { "below" }))
        }
      }
    }
    tags
  }
  tags-of(frame.round, 1 - ease(frame.progress, 0.05, 0.5))
  tags-of(frame.round + 1, if frame.progress > 0 { ease(frame.progress, 0.72, 1) } else { 0 })
}

// ------------------------------------------------------ rule pictograms -----
/// A local view as in the paper: `cells` from left to right, with "[X]" the
/// observer, "X" a robot, "." an empty node, "∅" / "¬∅" / "*" for the unseen
/// rest of a side. `move` is "left", "right" or "stay".
#let rule-view(cells, move: "stay", color: accent) = {
  let w = 40
  let (pad, y0) = (16, 40)
  let me = cells.position(c => c == "[X]")
  let xs = range(cells.len()).map(i => pad + i * w)
  let plain = c => c not in ("∅", "¬∅", "*")
  box(width: ((cells.len() - 1) * w + 2 * pad) * 1pt, height: 56pt, {
    for i in range(cells.len() - 1) {
      if plain(cells.at(i)) and plain(cells.at(i + 1)) {
        _segment(xs.at(i), y0, xs.at(i + 1), y0, 2pt + rail)
      }
    }
    for (i, c) in cells.enumerate() {
      let cx = xs.at(i)
      if c == "[X]" { at(cx - 12, y0 - 12, rect(width: 24pt, height: 24pt, radius: 5pt, fill: color)) }
      else if c == "X" { _disc(cx, y0, 11, fill: ink) }
      else if c == "." { _disc(cx, y0, 5.5, fill: paper, stroke: 1.6pt + faint) }
      else { _centered(cx, y0, text(size: 18pt, fill: muted, c)) }
    }
    let mx = xs.at(me)
    if move == "stay" {
      _centered(mx, 10, text(size: 16pt, weight: "bold", fill: color)[stays])
    } else {
      let dir = if move == "right" { 1 } else { -1 }
      _arrow(mx, 12, mx + dir * 36, 12, color)
    }
  })
}

// ----------------------------------------------------- results map ----------
// Marks are drawn, not typeset: a check or a cross from a math font is too
// thin to read from the back of a room.
#let _mark(kind, size, color) = box(width: size * 1pt, height: size * 1pt, {
  let stroke = (paint: color, thickness: size * 0.14pt, cap: "round", join: "round")
  if kind == "solved" {
    at(0, 0, curve(stroke: stroke,
      curve.move((0.12 * size * 1pt, 0.54 * size * 1pt)),
      curve.line((0.39 * size * 1pt, 0.8 * size * 1pt)),
      curve.line((0.88 * size * 1pt, 0.22 * size * 1pt))))
  } else if kind == "impossible" {
    _segment(0.2 * size, 0.2 * size, 0.8 * size, 0.8 * size, stroke)
    _segment(0.2 * size, 0.8 * size, 0.8 * size, 0.2 * size, stroke)
  } else {
    align(center + horizon, text(size: size * 1.25pt, weight: "bold", fill: color)[?])
  }
})

/// A status with its mark, for the legend of the map.
#let status-pill(kind, label, opacity: 1) = {
  let (fg, bg) = (solved: (teal, teal-soft), impossible: (alert, alert-soft), open: (amber, amber-soft)).at(kind)
  box(inset: (x: 12pt, y: 7pt), radius: 99pt, fill: alpha(bg, opacity), {
    box(baseline: 2pt, _mark(kind, 16, alpha(fg, opacity)))
    h(8pt)
    text(size: 20pt, weight: "bold", fill: alpha(fg, opacity), label)
  })
}

/// Solvability for oblivious robots when O_init is odd: columns H_init,
/// rows phi - H_init. `focus` lists cells (h, extra) to emphasize.
/// `reveal(h, extra, status)` controls each cell's opacity without moving it.
/// The statuses are those of the SIROCCO 2025 paper. `updates` lists newer
/// results as (h, extra, status): with `update` going from 0 to 1, these cells
/// turn to their new status and get a "new" badge.
/// `class: "odd-or"` gives the map for the wider class of the journal version:
/// O_init or M_init odd, the robots not knowing which. Oblivious robots solve
/// it with phi >= H + 3; impossibility for O_init odd carries over.
#let results-map(focus: (), dim-others: false, cell: 92pt, reveal: (h, e, s) => 1,
  updates: (), update: 0, class: "odd", label-width: 118pt, label-size: 22pt, mark-size: 25) = {
  let status(h, e) = if class == "odd" {
    if h == 1 { "solved" }
    else if e == 0 { if h <= 3 { "impossible" } else { "open" } }
    else if h == 2 and e == 1 { "open" }
    else { "solved" }
  } else {
    if h == 1 or e == 3 { "solved" }
    else if e == 0 and h <= 3 { "impossible" }
    else { "open" }
  }
  let style = (
    solved: (teal-soft, teal),
    impossible: (alert-soft, alert),
    open: (amber-soft, amber),
  )
  let heights = (0, 1, 2, 3)
  let hs = (1, 2, 3, 4, 5, 6)
  let body = ()
  for e in heights.rev() {
    body.push(align(right + horizon, text(size: label-size, fill: muted,
      if e == 0 { $phi = H$ } else { $phi = H + #e$ })))
    for h in hs {
      let s = status(h, e)
      let newer = updates.find(u => u.at(0) == h and u.at(1) == e)
      let k = if newer == none { 0 } else { calc.clamp(update, 0, 1) }
      let s2 = if newer == none { s } else { newer.at(2) }
      let (bg, fg) = style.at(s)
      let (bg2, fg2) = style.at(s2)
      bg = blend(bg, bg2, k)
      fg = blend(fg, fg2, k)
      let focused = focus.contains((h, e))
      if dim-others and not focused { bg = bg.lighten(50%); fg = fg.lighten(58%) }
      let shown = calc.clamp(reveal(h, e, s), 0, 1)
      // The old mark fades out in the first half of the update, the new one
      // fades in during the second half.
      let mark = if k < 0.5 { _mark(s, mark-size, alpha(fg, shown * (1 - 2 * k))) }
        else { _mark(s2, mark-size, alpha(fg, shown * (2 * k - 1))) }
      body.push(box(width: cell, height: cell * 0.68, radius: 9pt,
        fill: blend(tint, bg, shown),
        stroke: if focused { 3pt + alpha(fg, shown) } else { none },
        {
          align(center + horizon, mark)
          if k * shown > 0.001 {
            place(top + right, dx: 10pt, dy: -11pt,
              box(inset: (x: 6pt, y: 3pt), radius: 6pt, fill: alpha(fg2, k * shown),
                text(size: 13pt, weight: "bold", fill: alpha(paper, k * shown))[NEW]))
          }
        }))
    }
  }
  body.push([])
  for h in hs { body.push(align(center, text(size: label-size, fill: muted, if h == 6 { $H >= 6$ } else { $H = #h$ }))) }
  grid(columns: (label-width,) + hs.map(_ => cell), column-gutter: 9pt, row-gutter: 9pt, ..body)
}

// ------------------------------------------------------- model builder ------
// A model is drawn as a card of rows, one per assumption. Rows start as the
// choices a paper makes in prose and become `field := value` lines of `.sim`.
// Everything is placed on a fixed grid so that values can travel between the
// option cards on the right and their row on the left.

#let geo = (width: 1136, height: 492, card: 610, top: 64, row: 56, pad: 24, panel: 640, gap: 12, inset: 16)

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
    at(geo.pad, 22, text(size: 17pt, weight: "bold", tracking: 0.14em, fill: alpha(accent, 1 - header-out), upper[A robot model]))
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
            text(size: 20pt, fill: alpha(muted, shown), note)))
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
