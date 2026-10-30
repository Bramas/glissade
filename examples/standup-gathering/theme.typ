#import "../../lib.typ" as glissade
#import "../../lib.typ": init, animate, cut
#import "@preview/touying:0.7.3" as touying
#import touying.themes.simple: simple-theme, slide as theme-slide
#import "@preview/cetz:0.5.1"

#let ink = black
#let blue = rgb("#174c9b")
#let teal = rgb("#075e47")
#let coral = rgb("#ad2424")
#let paper = white
#let edge = rgb("#555555")
#let handout = sys.inputs.at("handout", default: "false") == "true"
#let recordings = json("traces.json").traces

#let small(body) = text(size: 21pt, fill: black, body)
#let remark(body) = block(above: 10pt, below: 0pt, text(size: 25pt, body))

// Touying owns logical slides and pause overlays; Glissade renders only the
// continuous animation inside an animated slide.
#let robot-animation = glissade.touying(touying.touying-fn-wrapper, fps: 12)
#let talk-slide(n, id, title, animated: false, body) = theme-slide[
  #metadata((standup_slide: (id: id, title: title, number: str(n))))
  #text(size: 37pt, weight: "bold", title)
  #v(5pt)
  #line(length: 100%, stroke: 0.7pt + black)
  #v(16pt)
  #if animated { robot-animation(id: id, body) } else { body }
]

// One scalar animation state per slide; cuts are the speaker's reveal points.
#let run(last, duration: 0.7, stops: auto, loop: false) = {
  init(t: if handout { float(last) } else { 0.0 })
  if not handout {
    for round in range(1, last + 1) {
      animate(t: float(round), duration: duration)
      if stops == auto or round in stops { cut(loop: loop and round == last) }
    }
  }
}

#let state-at(name, time) = {
  let trace = recordings.at(name)
  let last = trace.states.len() - 1
  let i = calc.min(last, calc.max(0, int(calc.floor(time))))
  let next = calc.min(last, i + 1)
  let progress = if i == last { 0 } else { calc.clamp(time - i, 0, 1) }
  let start = trace.states.at(i)
  let finish = trace.states.at(next)
  (
    positions: start.positions.zip(finish.positions).map(((x, y)) => float(x) + progress * (y - x)),
    crashed: if progress > 0 { finish.crashed } else { start.crashed },
    round: i,
    transition: progress > 0,
    occupied: start.occupiedCount,
    diameter: start.diameter,
  )
}

#let line-view(
  positions, low: auto, high: auto, width: 1100, crashed: (),
  observer: none, radius: none, arrows: (), highlight: none, labels: true,
) = {
  if low == auto { low = int(calc.floor(calc.min(..positions))) - 1 }
  if high == auto { high = int(calc.ceil(calc.max(..positions))) + 1 }
  let step = width / calc.max(1, high - low)
  let x = p => (p - low) * step
  let size = calc.min(12, step * 0.30)
  cetz.canvas(length: 1pt, {
    import cetz.draw: *
    rect((-18, -8), (width + 18, 143), fill: paper, stroke: none)
    if radius != none and observer != none {
      let a = calc.max(low, observer - radius)
      let b = calc.min(high, observer + radius)
      rect((x(a) - 10, 18), (x(b) + 10, 112), fill: blue.lighten(96%), stroke: 1.4pt + blue)
    }
    if highlight != none {
      rect((x(highlight.at(0)) - 15, 23), (x(highlight.at(1)) + 15, 95), fill: none, stroke: 1.4pt + black)
    }
    line((-8, 49), (width + 8, 49), stroke: 1.4pt + edge)
    for node in range(low, high + 1) {
      circle((x(node), 49), radius: 4, fill: white, stroke: 1pt + edge)
      if labels { content((x(node), 13), text(size: 15pt, fill: black)[#node]) }
    }
    let used = ()
    for (i, p) in positions.enumerate() {
      let key = calc.round(p, digits: 4)
      if not key in used {
        used.push(key)
        let same = positions.enumerate().filter(((j, q)) => calc.abs(q - p) < 0.001).map(pair => pair.at(0))
        let failed = same.filter(j => crashed.len() > j and crashed.at(j)).len()
        circle((x(p), 49), radius: size, fill: if failed == same.len() { coral } else { blue }, stroke: 2pt + white)
        if same.len() > 1 {
          content((x(p), 84), text(size: 16pt, weight: "bold", fill: ink)[×#same.len()])
        }
        if failed > 0 {
          line((x(p) - size * 0.45, 49 - size * 0.45), (x(p) + size * 0.45, 49 + size * 0.45), stroke: 2.2pt + white)
          line((x(p) - size * 0.45, 49 + size * 0.45), (x(p) + size * 0.45, 49 - size * 0.45), stroke: 2.2pt + white)
          content((x(p), 113), text(size: 16pt, fill: coral, weight: "bold")[crash])
        }
      }
    }
    if observer != none {
      circle((x(observer), 49), radius: size + 6, stroke: 2.5pt + teal)
      content((x(observer), 130), text(size: 15pt, fill: teal, weight: "bold")[observer])
    }
    for (i, movement) in arrows.enumerate() {
      let start = movement.at(0)
      let finish = movement.at(1)
      if start != finish {
        let direction = if finish > start { 1 } else { -1 }
        let y = 102 + calc.rem(i, 2) * 16
        line((x(start) + direction * 8, y), (x(finish) - direction * 8, y), mark: (end: ">"), stroke: 2pt + teal)
      }
    }
  })
}

#let trace-view(name, time, width: 1100, metrics: true, low: auto, high: auto) = {
  let trace = recordings.at(name)
  let frame = state-at(name, time)
  if low == auto { low = calc.min(..trace.positions) - 1 }
  if high == auto { high = calc.max(..trace.positions) + 1 }
  line-view(frame.positions, low: low, high: high, width: width, crashed: frame.crashed)
  if metrics {
    v(4pt)
    // Reserve each metric's width so transition arrows and changing digits
    // cannot move the following labels, including in the two-column slide.
    small(grid(
      columns: (170pt, 80pt, 80pt, 80pt), column-gutter: 24pt,
      if frame.transition { [Round #frame.round → #(frame.round + 1)] } else { [Round #frame.round] },
      $phi = #trace.phi$,
      $O_t = #frame.occupied$,
      $D_t = #frame.diameter$,
    ))
  }
}

#let round-caption(name, time, labels) = {
  let frame = state-at(name, time)
  let index = calc.min(frame.round, labels.len() - 1)
  remark(labels.at(index))
}

