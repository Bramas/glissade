#import "@preview/cetz:0.5.1": draw

#let _formula-interpolate(from, to, progress) = (
  kino-type: "formula-transition",
  from: from,
  to: to,
  progress: progress,
)

#let _part-marker-start-fill = rgb("#ff4fd8")
#let _part-marker-end-fill = rgb("#00d5ff")

#let _part-marker(fill) = box(width: 0pt, height: 0pt, inset: 0pt)[
  #rect(width: 0.2pt, height: 0.2pt, fill: fill, stroke: none)
]

#let _wrap-part(body) = math.attach(
  math.limits(body),
  t: pad([#none #_part-marker(_part-marker-start-fill)], -1em),
  b: pad([#none #_part-marker(_part-marker-end-fill)], -1em),
)

/// Marks one independently matched part inside a formula.
/// Identical bodies are matched automatically; `key` resolves ambiguities.
#let part(body, key: auto) = {
    let rendered = math.equation(block: false, body)
    let effective-key = if key == auto { repr(rendered) } else { str(key) }
    metadata((
      kino-formula-part: true,
      key: effective-key,
      body: rendered,
    ))
    _wrap-part(body)
  }

#let _collect-parts(content) = {
  if (
    content.func() == metadata
      and type(content.value) == dictionary
      and content.value.at("kino-formula-part", default: false)
  ) {
    ((key: content.value.key, body: content.value.body),)
  } else if content.has("children") {
    content.children.map(_collect-parts).flatten()
  } else if content.has("child") {
    _collect-parts(content.child)
  } else if content.has("body") {
    _collect-parts(content.body)
  } else {
    ()
  }
}

/// Wraps a formula as a semantic Kino value. Every visible animated fragment
/// should be wrapped in `part`; Typst still validates and typesets the full body.
#let formula(body) = (
  kino-type: "formula",
  kino-interpolate: _formula-interpolate,
  body: body,
  parts: _collect-parts(body),
)

/// Draws a formula transition inside a Cetz canvas. Shows discrete frames:
/// early frames display the source formula, final frame shows the target formula.
/// `id` must be unique if a transition is drawn more than once on a page.
#let kino-content(
  position,
  value,
  id: auto,
  map: (:),
  foreground: black,
  background: white,
) = {
  let transition = if value.at("kino-type", default: none) == "formula-transition" {
    value
  } else {
    (from: value, to: value, progress: 0)
  }
  let progress = transition.progress
  
  // Show source formula until final frame, then show target
  if progress < 1 {
    // Display source formula
    draw.content(
      position,
      transition.from.body,
      anchor: "base-west",
    )
  } else {
    // Display target formula (final frame)
    draw.content(
      position,
      transition.to.body,
      anchor: "base-west",
    )
  }
}
