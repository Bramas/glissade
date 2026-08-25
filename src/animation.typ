#import "states.typ": (
  active-slide, slide-scope,
)
#import "primitives.typ": build-timeline
#import "utils.typ": get_block_duration, get_default_dict, get_scaler
#import "transitions.typ": get_transition

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
    type(element.value) == dictionary and "glissade_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "animation-effect() must be evaluated inside a Glissade slide frame")
  let scope = scopes.last().value.glissade_animation_scope
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
    type(element.value) == dictionary and "glissade_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "a() must be evaluated inside a Glissade slide frame")
  let scope = scopes.last().value.glissade_animation_scope
  build_mapping(scope.variables, scope.block, name)(scope.time)
}

/// Returns the one-based logical slide number for the current frame.
#let slide-number() = {
  let scopes = query(selector(metadata).before(here())).filter(element => (
    type(element.value) == dictionary and "glissade_animation_scope" in element.value
  ))
  assert(scopes.len() > 0, message: "slide-number() must be used inside a Glissade slide")
  scopes.last().value.glissade_animation_scope.index
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
  let values-input = sys.inputs.at("glissade-frozen-values", default: "")
  if frozen-counters.len() > 0 {
    if first {
      if values-input != "" {
        let values = json(bytes(values-input))
        for ((counter, value)) in frozen-counters.zip(values) {
          _restore-counter(counter, value)
        }
      }
      metadata(("glissade_counter_checkpoint": id))
    } else {
      let checkpoints = query(selector(metadata).before(here())).filter(element => (
        type(element.value) == dictionary
          and element.value.at("glissade_counter_checkpoint", default: none) == id
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

#let _max-block(variables) = {
  let blocks = variables.values().join().keys().map(int)
  if blocks.len() == 0 { 0 } else { calc.max(..blocks) }
}

#let _timeline-blocks(variables, fps, cut-blocks: (), loop-blocks: ()) = {
  let max-block = _max-block(variables)
  let effective-cuts = cut-blocks
  if max-block > 0 and not max-block in effective-cuts {
    effective-cuts = effective-cuts + (max-block,)
  }
  let elapsed = 0
  let total-frames = 0
  let blocks = ()
  for b in range(1, max-block + 1) {
    let duration = get_block_duration(variables, b)
    let frames = int(calc.round(fps * duration))
    blocks.push((
      "index": b,
      "start": elapsed,
      "end": elapsed + duration,
      "duration": duration,
      "start_frame": total-frames,
      "end_frame": total-frames + frames,
      "cut": b in effective-cuts,
      "loop": b in loop-blocks,
    ))
    elapsed += duration
    total-frames += frames
  }
  (
    blocks: blocks,
    duration: elapsed,
    frames: total-frames + 1,
  )
}

#let _render-frame-content(
  body,
  id,
  index,
  variables,
  frame,
  fps,
  marker: none,
) = {
  let max-block = _max-block(variables)
  let block-index = 1
  let time = 0
  if max-block > 0 {
    let offset = 0
    for b in range(1, max-block + 1) {
      let duration = get_block_duration(variables, b)
      let frames = int(calc.round(fps * duration))
      if frame < offset + frames or b == max-block {
        block-index = b
        time = if frames == 0 {
          duration
        } else {
          duration * calc.min(frames, frame - offset) / frames
        }
        break
      }
      offset += frames
    }
  }
  [
    #active-slide.update(_ => id)
    #slide-scope(id)
    #metadata(("glissade_animation_scope": (
      variables: variables,
      block: block-index,
      time: time,
      index: index,
    )))
    #if marker != none { metadata(marker) }
    #body
  ]
}

#let _render-slideshow(body, id, index, variables, frozen-counters: ()) = {
  let max_block = _max-block(variables)
  for b in range(1, max_block + 2) {
    page(_frame([
      #active-slide.update(_ => id)
      #slide-scope(id)
      #metadata(("glissade_animation_scope": (variables: variables, block: b, time: 0, index: index)))
      #metadata(("glissade_new_frame": true))
      #_frame-preamble(id, frozen-counters, first: b == 1)
      #body
    ]))
  }
}

#let _render-query-document(body, fps, id, index, title, autoplay, frozen-counters, variables, cut_blocks, loop_blocks) = context {
  let max_block = _max-block(variables)
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
        "glissade": (
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
      "glissade_timeline": (
      "id": id,
      "index": index,
      "title": title,
      "autoplay": autoplay,
      "frozen_values": frozen-counters.map(counter => (counter.get)()),
      "fps": fps,
      "duration": elapsed,
      "frames": total_frames + local_frames + 1,
      "blocks": blocks,
    ),
  ))
  page(_frame([
    #active-slide.update(_ => id)
    #slide-scope(id)
    #metadata(("glissade_animation_scope": (variables: variables, block: 1, time: 0, index: index)))
    #body
  ]))
}

/// The main show rule. Must be applied before any animation primitive is used.
#let animation(
  /// -> content
  body,
  id: "1",
  index: 1,
  title: none,
  autoplay: false,
  frozen-counters: (),
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
    _render-query-document(body, fps, id, index, title, autoplay, frozen-counters, variables, cut_blocks, loop_blocks)
  } else if fps == 0 {
    _render-slideshow(body, id, index, variables, frozen-counters: frozen-counters)
  } else {
      let max_block = _max-block(variables)
      if max_block == 0 {
        page(_frame([
          #active-slide.update(_ => id)
          #slide-scope(id)
          #metadata(("glissade_frame": 0, "glissade_slide": id))
          #metadata(("glissade_animation_scope": (variables: variables, block: 1, time: 0, index: index)))
          #metadata(("glissade_new_frame": true))
          #_frame-preamble(id, frozen-counters, first: true)
          #body
        ]))
      }
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
            #active-slide.update(_ => id)
            #slide-scope(id)
            #metadata(("glissade_frame": frame, "glissade_slide": id))
            #metadata(("glissade_animation_scope": (variables: variables, block: b, time: new_time, index: index)))
            #metadata(("glissade_new_frame": true))
            #_frame-preamble(id, frozen-counters, first: b == 1 and frame == 0)
            #body
          ]))
        }

        if b in effective-cuts {
          metadata((
            "glissade": (
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

/// Embeds a Glissade timeline in a Touying slide. Bind Touying's public
/// `touying-fn-wrapper` once, then use the result like a content function:
/// `#let glissade-animation = touying-animation.with(touying-fn-wrapper)`.
#let touying-animation(
  touying-fn-wrapper,
  body,
  /// Identifier for this embedded timeline. Keep it unique when a document
  /// contains multiple Touying animations.
  id: "animation",
  /// Frames per second reserved as Touying subslides.
  fps: -1,
) = {
  let forced-fps = sys.inputs.at("glissade-force-fps", default: "")
  if forced-fps != "" {
    fps = int(forced-fps)
  } else if fps < 0 {
    fps = int(sys.inputs.at("fps", default: 30))
  }
  assert(fps > 0, message: "touying-animation requires fps greater than zero")
  let built = build-timeline(body)
  let timeline = _timeline-blocks(
    built.timeline,
    fps,
    cut-blocks: built.cuts,
    loop-blocks: built.loops,
  )
  let render(
    self: none,
    body,
    variables,
    timeline,
    id,
    fps,
    start: 1,
  ) = {
    let local-frame = calc.max(
      0,
      calc.min(timeline.frames - 1, self.subslide - start),
    )
    let rendered = _render-frame-content(
      body,
      id,
      1,
      variables,
      local-frame,
      fps,
      marker: if self.subslide >= start
        and self.subslide < start + timeline.frames {
        (
          "glissade_touying_frame": (
            id: id,
            frame: local-frame,
            frames: timeline.frames,
            fps: fps,
            duration: timeline.duration,
            blocks: timeline.blocks,
          ),
        )
      } else {
        none
      },
    )
    if self.subslide < start {
      (self.methods.cover.with(self: self))(rendered)
    } else {
      rendered
    }
  }
  touying-fn-wrapper(
    render,
    last-subslide: start => (
      start + timeline.frames - 1,
      (start: start),
    ),
    body,
    built.timeline,
    timeline,
    id,
    fps,
  )
}

/// Creates a Glissade animation function with document-wide Touying defaults.
/// The returned function can still receive per-animation arguments such as
/// `id` or an overriding `fps`.
#let touying(touying-fn-wrapper, fps: 30) = {
  assert(fps > 0, message: "touying requires fps greater than zero")
  touying-animation.with(touying-fn-wrapper, fps: fps)
}

/// Add a cut at the end of the current block.
#let cut(
  /// Whether the pre-cut segment should loop during browser playback.
  /// -> bool
  loop: false,
) = metadata(("glissade_operation": (kind: "cut", loop: loop)))

/// Collects one logical slide for the `deck` show rule. The animation ends
/// automatically at the end of the slide body.
#let slide(
  body,
  id: auto,
  title: none,
  autoplay: false,
  frozen-counters: (),
  fps: -1,
) = {
  metadata((
    "glissade_slide_definition": (
      id: id,
      title: title,
      autoplay: autoplay,
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
      and "glissade_slide_definition" in content.value
  ) {
    (content.value.glissade_slide_definition,)
  } else if content.has("children") {
    content.children.map(_collect-slides).flatten()
  } else if content.has("child") {
    _collect-slides(content.child)
  } else {
    ()
  }
}

#let _generated-slide-id(item, index) = {
  if item.id != auto {
    str(item.id)
  } else if type(item.title) == str {
    let slug = lower(item.title).replace(regex("[^a-z0-9]+"), "-").trim("-")
    if slug == "" { "slide-" + str(index) } else { slug }
  } else {
    "slide-" + str(index)
  }
}

/// Renders all collected slides. Use as `#show: deck.with(fps: 6)` to set the
/// default frame rate used by an ordinary `typst compile`.
#let deck(body, fps: 5) = {
  let definitions = _collect-slides(body)
  assert(
    definitions.len() > 0,
    message: "Glissade deck found no Glissade slide definitions. "
      + "In a Touying presentation, keep the Touying theme as the document show rule "
      + "and set fps on touying-animation instead.",
  )
  let normalized = ()
  let used-ids = (:)
  for (offset, item) in definitions.enumerate() {
    let base = _generated-slide-id(item, offset + 1)
    let occurrences = used-ids.at(base, default: 0)
    if item.id != auto {
      assert(occurrences == 0, message: "duplicate Glissade slide id: " + base)
    }
    occurrences += 1
    used-ids.insert(base, occurrences)
    item.id = if occurrences == 1 { base } else { base + "-" + str(occurrences) }
    normalized.push(item)
  }
  definitions = normalized

  let selected = sys.inputs.at("glissade-slide", default: "")
  let effective-fps = int(sys.inputs.at("fps", default: str(fps)))
  let forced-fps = sys.inputs.at("glissade-force-fps", default: "")
  for (offset, item) in definitions.enumerate() {
    let index = offset + 1
    if selected == "" or selected == item.id or selected == str(index) {
      animation(
        item.body,
        id: item.id,
        index: index,
        title: item.title,
        autoplay: item.autoplay,
        frozen-counters: item.frozen-counters,
        fps: if forced-fps != "" {
          int(forced-fps)
        } else if item.fps < 0 {
          effective-fps
        } else {
          item.fps
        },
      )
    }
  }
}
