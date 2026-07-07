#let _formula-interpolate(from, to, progress) = (
  kino-type: "formula-transition",
  from: from,
  to: to,
  progress: progress,
)

#let _part-marker-start-fill = rgb("#ff4fd8")
#let _part-marker-end-fill = rgb("#00d5ff")
#let _morph-marker-start-fill = rgb("#19c37d")
#let _morph-marker-end-fill = rgb("#ff8a00")

#let _part-marker(fill) = box(width: 0pt, height: 0pt, inset: 0pt)[
  #rect(width: 0.2pt, height: 0.2pt, fill: fill, stroke: none)
]

#let _morph-marker(fill) = box(width: 0pt, height: 0pt, inset: 0pt)[
  #rect(width: 0.2pt, height: 0.2pt, fill: fill, stroke: none)
]

#let _wrap-part(body) = math.attach(
  math.limits(body),
  t: pad([#none #_part-marker(_part-marker-start-fill)], -1em),
  b: pad([#none #_part-marker(_part-marker-end-fill)], -1em),
)

#let _wrap-morph(body) = [
  #metadata((kino-morph: true))
  #_morph-marker(_morph-marker-start-fill)
  #box(inset: 0pt, outset: 0pt)[#body]
  #_morph-marker(_morph-marker-end-fill)
]

#let _formula-frame(value) = {
  if type(value) == dictionary and value.at("kino-type", default: none) == "formula-transition" {
    if value.progress < 1 { value.from } else { value.to }
  } else {
    value
  }
}

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
  } else {
    let parts = ()
    if content.has("children") {
      parts += content.children.map(_collect-parts).flatten()
    }
    if content.has("child") {
      parts += _collect-parts(content.child)
    }
    if content.has("body") {
      parts += _collect-parts(content.body)
    }
    if content.has("base") {
      parts += _collect-parts(content.base)
    }
    if content.has("num") {
      parts += _collect-parts(content.num)
    }
    if content.has("denom") {
      parts += _collect-parts(content.denom)
    }
    if content.has("t") {
      parts += _collect-parts(content.t)
    }
    if content.has("b") {
      parts += _collect-parts(content.b)
    }
    if content.has("tl") {
      parts += _collect-parts(content.tl)
    }
    if content.has("tr") {
      parts += _collect-parts(content.tr)
    }
    if content.has("bl") {
      parts += _collect-parts(content.bl)
    }
    if content.has("br") {
      parts += _collect-parts(content.br)
    }
    if content.has("sub") {
      parts += _collect-parts(content.sub)
    }
    if content.has("sup") {
      parts += _collect-parts(content.sup)
    }
    parts
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

/// Renders a semantic Kino value as ordinary Typst content.
/// Formula states render their currently visible formula body.
#let kino-morph(value, id: auto, effect: auto) = {
  let visible = _formula-frame(value)
  let body = if type(visible) == dictionary and visible.at("kino-type", default: none) == "formula" {
    visible.body
  } else {
    value
  }
  let effective-id = if id == auto { none } else { str(id) }
  let effective-effect = if effect == auto { none } else { str(effect) }
  metadata((
    kino-morph-root: true,
    id: effective-id,
    effect: effective-effect,
  ))
  _wrap-morph(body)
}
