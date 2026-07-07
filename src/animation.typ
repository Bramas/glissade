#import "states.typ": (
  active-slide, frozen-values, slide-scope,
)
#import "primitives.typ": build-timeline
#import "utils.typ": get_block_duration, get_default_dict, get_scaler
#import "transitions.typ": get_transition

/// Terminates the animation. Mandatory.
#let finish() = metadata(("kino_operation": (kind: "finish")))

// Main function for computing `a`("x")
#let build_mapping(variables, block, name) = {
  let name_dict = variables.at(name, default: get_default_dict())
  let end = block
  let start = block - 1
  while not str(start) in name_dict.keys() {
    start -= 1
  }
  let (start_value, _, _, _, _, _) = name_dict.at(str(start)).at(-1)
  let scaler = get_scaler(name_dict.at("0").at(0).at(0))

  if str(end) in name_dict.keys() {
    let mapping(time) = {
      let start_value_bis = start_value
      for (end_value, hold, duration, dwell, trans, _) in name_dict.at(str(end)) {
        if hold <= time {
          if time < hold + duration + dwell {
            trans = get_transition(trans)
            time = calc.min(1, calc.max(0, time - hold) / duration)
            return scaler(start_value_bis, end_value, trans(time))
          } else { start_value_bis = end_value }
        } else { break }
      }
      return start_value_bis
    }
    return mapping
  } else {
    return _ => start_value
  }
}

/// Returns the morph effect attached to the active transition for a state.
#let animation-effect(name) = {
  let scopes = query(selector(metadata).before(here())).filter(element => (
    type(element.value) == dictionary and "kino_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "animation-effect() must be evaluated inside a Kino slide frame")
  let scope = scopes.last().value.kino_animation_scope
  let name-dict = scope.variables.at(name, default: (:))
  let entries = name-dict.at(str(scope.block), default: ())
  let active = none
  for (_, hold, duration, dwell, _, effect) in entries {
    if hold <= scope.time {
      active = effect
      if scope.time <= hold + duration + dwell { break }
    }
  }
  active
}

/// Evaluates an animation variable in context.
#let a(
  /// -> str
  name,
) = {
  let scopes = query(selector(metadata).before(here())).filter(element => (
    type(element.value) == dictionary and "kino_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "a() must be evaluated inside a Kino slide frame")
  let scope = scopes.last().value.kino_animation_scope
  build_mapping(scope.variables, scope.block, name)(scope.time)
}

/// Returns the one-based logical slide number for the current frame.
#let slide-number() = {
  let scopes = query(selector(metadata).before(here())).filter(element => (
    type(element.value) == dictionary and "kino_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "slide-number() must be used inside a Kino slide")
  scopes.last().value.kino_animation_scope.index
}

#let _restore-counter(counter, value) = {
  if type(counter) == dictionary {
    if "get-inherited-levels" in counter {
      let inherited = (counter.get-inherited-levels)()
      let missing = calc.max(0, inherited + 1 - value.len())
      value = ((0,) * missing) + value
    }
    (counter.update)(value)
  } else {
    counter.update(value)
  }
}

#let _frame-preamble(id, frozen-counters, first: false) = context {
  let values-input = sys.inputs.at("kino-frozen-values", default: "")
  if frozen-counters.len() > 0 {
    if first {
      if values-input != "" {
        let values = json(bytes(values-input))
        for ((counter, value)) in frozen-counters.zip(values) {
          _restore-counter(counter, value)
        }
      }
      metadata(("kino_counter_checkpoint": id))
    } else {
      let checkpoints = query(selector(metadata).before(here())).filter(element => (
        type(element.value) == dictionary
          and element.value.at("kino_counter_checkpoint", default: none) == id
      ))
      if checkpoints.len() > 0 {
        let location = checkpoints.first().location()
        for counter in frozen-counters {
          if type(counter) == dictionary {
            _restore-counter(counter, (counter.at)(selector(location)))
          } else {
            _restore-counter(counter, counter.at(selector(location)))
          }
        }
      }
    }
  }
}

// A logical animation frame must always produce exactly one physical page.
// Without this unbreakable container, tall content can spill into a second SVG
// and make the player alternate between fragments of the same frame.
#let _frame(body) = block(width: 100%, height: 100%, body)

// Register a slide's animation operations exactly once before rendering its
// frames. Keeping this probe out of the page flow avoids repeated timeline
// updates and lets a normal `typst compile` converge for every slide.
#let _probe(id, body, frozen-counters) = context {
  let values = frozen-counters.map(counter => (counter.get)())
  frozen-values(id).update(_ => values)
  hide(box(
    width: 0pt,
    height: 0pt,
    clip: true,
    [#active-slide.update(_ => id)#body],
  ))
}

#let slideshow(body, id, index, variables, frozen-counters: ()) = {
  let max_block = calc.max(..variables.values().join().keys().map(int))
  for b in range(1, max_block + 2) {
    page(_frame([
      #active-slide.update(_ => id)
      #slide-scope(id)
      #metadata(("kino_animation_scope": (variables: variables, block: b, time: 0, index: index)))
      #metadata(("kino_new_frame": true))
      #_frame-preamble(id, frozen-counters, first: b == 1)
      #body
    ]))
  }
}

#let fake(body, fps, id, index, title, frozen-counters, variables, cut_blocks, loop_blocks, collector: none) = context {
  let max_block = calc.max(..variables.values().join().keys().map(int))
  let effective-cuts = cut_blocks
  if not max_block in effective-cuts {
    effective-cuts = effective-cuts + (max_block,)
  }

  let total_frames = 0
  let local_frames = 0
  let segment = 0
  let elapsed = 0
  let blocks = ()

  for b in range(1, max_block + 1) {
    let duration = get_block_duration(variables, b)

    let frames = int(calc.round(fps * duration))
    blocks.push((
      "index": b,
      "start": elapsed,
      "end": elapsed + duration,
      "duration": duration,
      "start_frame": total_frames + local_frames,
      "end_frame": total_frames + local_frames + frames,
      "cut": b in effective-cuts,
      "loop": b in loop_blocks,
    ))
    elapsed += duration
    local_frames += frames

    if b in effective-cuts {
      metadata((
        "kino": (
          "fps": fps,
          "duration": duration,
          "frames": local_frames + 1,
          "from": total_frames,
          "segment": segment,
          "loop": b in loop_blocks,
        ),
      ))
      total_frames += local_frames
      local_frames = 0
      segment += 1
    }
  }
  metadata((
      "kino_timeline": (
      "id": id,
      "index": index,
      "title": title,
      "frozen_values": frozen-counters.map(counter => (counter.get)()),
      "fps": fps,
      "duration": elapsed,
      "frames": total_frames + local_frames + 1,
      "blocks": blocks,
    ),
  ))
  page(_frame([
    #if collector != none { box(width: 0pt, height: 0pt, hide(collector)) }
    #active-slide.update(_ => id)
    #slide-scope(id)
    #metadata(("kino_animation_scope": (variables: variables, block: 1, time: 0, index: index)))
    #body
  ]))
}

/// The main show rule. Must be applied before any animation primitive is used. The body must contain a call to @finish.
#let animation(
  /// -> content
  body,
  id: "1",
  index: 1,
  title: none,
  frozen-counters: (),
  collector: none,
  /// Frames per second of animation. Overrides command line parameters.
  /// -> int
  fps: -1,
) = {
  if fps < 0 { fps = int(sys.inputs.at("fps", default: 5)) }
  let built = build-timeline(body)
  let variables = built.timeline
  let cut_blocks = built.cuts
  let loop_blocks = built.loops
  if int(sys.inputs.at("query", default: 0)) == 1 {
    fake(body, fps, id, index, title, frozen-counters, variables, cut_blocks, loop_blocks, collector: collector)
  } else if fps == 0 {
    slideshow(body, id, index, variables, frozen-counters: frozen-counters)
  } else {
      let max_block = calc.max(..variables.values().join().keys().map(int))
      let effective-cuts = cut_blocks
      if not max_block in effective-cuts {
        effective-cuts = effective-cuts + (max_block,)
      }
      let total_frames = 0
      let local_frames = 0
      let segment = 0

      for b in range(1, max_block + 1) {
        let duration = get_block_duration(variables, b)
        let frames = int(calc.round(fps * duration))
        local_frames += frames

        let rendered-frames = if b == max_block { frames + 1 } else { frames }
        for frame in range(rendered-frames) {
          let new_time = (duration * frame) / frames
          page(_frame([
            #if b == 1 and frame == 0 and collector != none {
              box(width: 0pt, height: 0pt, hide(collector))
            }
            #active-slide.update(_ => id)
            #slide-scope(id)
            #metadata(("kino_frame": frame, "kino_slide": id))
            #metadata(("kino_animation_scope": (variables: variables, block: b, time: new_time, index: index)))
            #metadata(("kino_new_frame": true))
            #_frame-preamble(id, frozen-counters, first: b == 1 and frame == 0)
            #body
          ]))
        }

        if b in effective-cuts {
          metadata((
            "kino": (
              "fps": fps,
              "duration": duration,
              "frames": local_frames + 1,
              "from": total_frames,
              "segment": segment,
              "loop": b in loop_blocks,
            ),
          ))
          total_frames += local_frames
          local_frames = 0
          segment += 1
        }
      }
  }
}

/// Add a cut at the end of the current block.
#let cut(
  /// Whether the pre-cut segment should loop (revealjs only)
  /// -> bool
  loop: false,
) = metadata(("kino_operation": (kind: "cut", loop: loop)))

/// Collects one logical slide for the `deck` show rule.
#let slide(
  body,
  id: auto,
  title: none,
  frozen-counters: (),
  fps: -1,
) = {
  metadata((
    "kino_slide_definition": (
      id: id,
      title: title,
      frozen-counters: frozen-counters,
      fps: fps,
      body: body,
    ),
  ))
}

#let _collect-slides(content) = {
  if (
    content.func() == metadata
      and type(content.value) == dictionary
      and "kino_slide_definition" in content.value
  ) {
    (content.value.kino_slide_definition,)
  } else if content.has("children") {
    content.children.map(_collect-slides).flatten()
  } else if content.has("child") {
    _collect-slides(content.child)
  } else {
    ()
  }
}

/// Renders all collected slides. Use as `#show: deck.with(fps: 6)` to set the
/// default frame rate used by an ordinary `typst compile`.
#let deck(body, fps: 5) = {
  let definitions = _collect-slides(body)
  definitions = definitions.enumerate().map(((offset, item)) => {
    item.id = if item.id == auto { str(offset + 1) } else { str(item.id) }
    item
  })
  let ids = definitions.map(item => item.id)
  assert(ids.dedup().len() == ids.len(), message: "duplicate Kino slide id")

  // Phase one is embedded invisibly into the first rendered page so timeline
  // registration cannot create a leading blank page.
  let registrations = none

  // Phase two: render from the now-complete slide-local timelines.
  let selected = sys.inputs.at("kino-slide", default: "")
  let effective-fps = int(sys.inputs.at("fps", default: str(fps)))
  let emitted = false
  for (offset, item) in definitions.enumerate() {
    let index = offset + 1
    if selected == "" or selected == item.id or selected == str(index) {
      animation(
        item.body,
        id: item.id,
        index: index,
        title: item.title,
        frozen-counters: item.frozen-counters,
        collector: if emitted { none } else { registrations },
        fps: if item.fps < 0 { effective-fps } else { item.fps },
      )
      emitted = true
    }
  }
}
