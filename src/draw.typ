#import "@preview/cetz:0.5.1": draw

#let _formula-interpolate(from, to, progress) = (
  kino-type: "formula-transition",
  from: from,
  to: to,
  progress: progress,
)

/// Marks one independently matched part inside a formula.
/// Identical bodies are matched automatically; `key` resolves ambiguities.
#let part(body, key: auto) = {
    let rendered = math.equation(block: false, body)
    let effective-key = if key == auto { repr(rendered) } else { str(key) }
    block[ #metadata((
      kino-formula-part: true,
      key: effective-key,
      body: rendered,
    )) $#body$]
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

#let _tag-formula(body, probe-id) = {
  metadata((
    kino-formula-origin: true,
    kino-formula-probe: probe-id,
  ))
  show metadata: element => {
    if (
      type(element.value) == dictionary
        and element.value.at("kino-formula-part", default: false)
        and element.value.at("kino-formula-probe", default: none) == none
    ) {
      metadata(element.value + (kino-formula-probe: probe-id))
    } else {
      element
    }
  }
  body
}

#let _probe-elements(probe-id) = query(metadata).filter(element => (
  type(element.value) == dictionary
    and element.value.at("kino-formula-probe", default: none) == probe-id
))

#let _probe-layout(probe-id) = {
  let elements = _probe-elements(probe-id)
  let origin = elements.find(element => (
    element.value.at("kino-formula-origin", default: false)
  ))
  if origin == none {
    return (origin: none, parts: ())
  }

  let origin-position = locate(origin.location()).position()
  let occurrences = (:)
  let parts = ()
  for element in elements.filter(element => (
    element.value.at("kino-formula-part", default: false)
  )) {
    let key = element.value.key
    let occurrence = occurrences.at(key, default: 0)
    occurrences.insert(key, occurrence + 1)
    let position = locate(element.location()).position()
    parts.push((
      key: key,
      occurrence: occurrence,
      body: element.value.body,
      position: (
        position.at("x") - origin-position.at("x"),
        origin-position.at("y") - position.at("y"),
      ),
    ))
  }
  (origin: origin-position, parts: parts)
}

#let _formula-opacity(body, opacity, foreground, background) = {
  let opacity = calc.clamp(opacity, 0, 1)
  // Alpha transparency around Cetz content currently produces malformed SVG
  // clipping. Mixing into the canvas background gives the same visual fade
  // without introducing an alpha group.
  text(fill: color.mix((foreground, opacity), (background, 1 - opacity)), body)
}

/// Draws a formula transition inside a Cetz canvas. Complete formulas are
/// cross-faded while matched parts move between their real Typst positions.
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
  let instance-id = if id == auto {
    repr((position, transition.from.body, transition.to.body))
  } else {
    str(id)
  }
  // Every animation frame is a separate page. Including the page prevents
  // probes belonging to other frames from being selected by the query.
  instance-id += ":page-" + str(here().page())
  let source-id = instance-id + ":source"
  let target-id = instance-id + ":target"
  let source-body = _tag-formula(transition.from.body, source-id)
  let target-body = _tag-formula(transition.to.body, target-id)
  let visible-source-body = _tag-formula(
    transition.from.body,
    instance-id + ":visible-source",
  )
  let visible-target-body = _tag-formula(
    transition.to.body,
    instance-id + ":visible-target",
  )
  let source-layout = _probe-layout(source-id)
  let target-layout = _probe-layout(target-id)
  let source-opacity = 1 - calc.clamp(progress / 0.25, 0, 1)
  let target-opacity = calc.clamp((progress - 0.75) / 0.25, 0, 1)
  let output = ()
  // Keep probes exactly where the real formulas are typeset so Typst retains
  // their metadata during standalone SVG compilation. Marked parts contain
  // nested equations and do not inherit a background-colored text fill, so
  // cover the complete probe area before drawing anything visible.
  output += draw.content(
    position,
    source-body,
    anchor: "base-west",
  )
  output += draw.content(
    position,
    target-body,
    anchor: "base-west",
  )
  let source-size = measure(transition.from.body)
  let target-size = measure(transition.to.body)
  let probe-width = calc.max(source-size.width, target-size.width)
  let probe-height = calc.max(source-size.height, target-size.height)
  output += draw.content(
    (rel: (-10pt, 0pt), to: position),
    box(
      width: probe-width + 20pt,
      height: 2 * probe-height + 20pt,
      fill: background,
    ),
    anchor: "west",
  )

  let visible-position = position

  if source-opacity > 0 {
    output += draw.content(
      visible-position,
      _formula-opacity(
        visible-source-body,
        source-opacity,
        foreground,
        background,
      ),
      anchor: "base-west",
    )
  }
  if target-opacity > 0 {
    output += draw.content(
      visible-position,
      _formula-opacity(
        visible-target-body,
        target-opacity,
        foreground,
        background,
      ),
      anchor: "base-west",
    )
  }

  // Locations become available on Typst's next introspection pass.
  if source-layout.origin == none or target-layout.origin == none {
    return output
  }

  let source = source-layout.parts
  let target = target-layout.parts
  let movement-progress = calc.clamp((progress - 0.25) / 0.5, 0, 1)
  let used-targets = ()
  for source-part in source {
    let target-key = map.at(source-part.key, default: source-part.key)
    let target-index = target.enumerate().position(((index, part)) => (
      part.key == target-key
        and part.occurrence == source-part.occurrence
        and not index in used-targets
    ))
    if target-index != none {
      used-targets.push(target-index)
      let target-part = target.at(target-index)
      let x = (
        source-part.position.at(0)
          + (target-part.position.at(0) - source-part.position.at(0))
            * movement-progress
      )
      let y = (
        source-part.position.at(1)
          + (target-part.position.at(1) - source-part.position.at(1))
            * movement-progress
      )
      output += draw.content(
        (rel: (x, y), to: position),
        source-part.body,
        anchor: "base-west",
      )
    }
  }
  output
}
