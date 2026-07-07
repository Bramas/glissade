#import "utils.typ": check_types, get_block_duration, get_default_dict

#let _operation(kind, fields: (:)) = metadata(("kino_operation": ((kind: kind) + fields)))

#let init(..args) = _operation("init", fields: (args: args.named()))

#let animate(
  block: -1,
  hold: 0,
  duration: 1,
  dwell: 0,
  transition: "smooth",
  morph-effect: none,
  ..args,
) = _operation("animate", fields: (
    block: block, hold: hold, duration: duration, dwell: dwell,
    transition: transition, morph-effect: morph-effect, args: args.named(),
))

#let meanwhile(
  hold: 0,
  duration: 1,
  dwell: 0,
  transition: "smooth",
  morph-effect: none,
  ..args,
) = _operation("meanwhile", fields: (
    hold: hold, duration: duration, dwell: dwell,
    transition: transition, morph-effect: morph-effect, args: args.named(),
))

#let then(
  hold: 0,
  duration: 1,
  dwell: 0,
  transition: "smooth",
  morph-effect: none,
  ..args,
) = _operation("then", fields: (
    hold: hold, duration: duration, dwell: dwell,
    transition: transition, morph-effect: morph-effect, args: args.named(),
))

/// Introduces content from an empty state using a morph effect.
#let create(
  block: -1,
  hold: 0,
  duration: 1,
  dwell: 0,
  transition: "smooth",
  morph-effect: "draw-border-then-fill",
  ..args,
) = {
  let values = args.named()
  assert(values.len() > 0, message: "create requires at least one named state")
  for (name, value) in values {
    assert(type(value) == content, message: "create currently supports content states only")
  }
  let initial = (:)
  for name in values.keys() { initial.insert(name, []) }
  _operation("init", fields: (args: initial))
  _operation("animate", fields: (
    block: block,
    hold: hold,
    duration: duration,
    dwell: dwell,
    transition: transition,
    morph-effect: morph-effect,
    args: values,
  ))
}

#let wait(block: -1, duration: 1) = _operation("wait", fields: (
  block: block, duration: duration,
))

#let _collect-operations(content) = {
  if (
    content.func() == metadata
      and type(content.value) == dictionary
      and "kino_operation" in content.value
  ) {
    (content.value.kino_operation,)
  } else if content.has("children") {
    content.children.map(_collect-operations).flatten()
  } else if content.has("child") {
    _collect-operations(content.child)
  } else {
    ()
  }
}

#let _add(timeline, block, args, hold, duration, dwell, transition, morph-effect, mode) = {
  let shift = if mode == "append" { get_block_duration(timeline, block) } else { 0 }
  for (name, value) in args {
    let name-dict = timeline.at(name, default: get_default_dict(type: value))
    let block-list = name-dict.at(str(block), default: ())
    if name in timeline { check_types((name-dict.at("0").at(0).at(0), value)) }
    if mode == "place" { assert(block-list.len() == 0, message: "collision in block " + str(block)) }
    block-list.push((value, hold + shift, duration, dwell, transition, morph-effect))
    name-dict.insert(str(block), block-list)
    timeline.insert(name, name-dict)
  }
  timeline
}

#let build-timeline(body) = {
  let timeline = ("builtin_pause_counter": get_default_dict())
  let current = 1
  let maximum = 1
  let cuts = ()
  let loops = ()
  for operation in _collect-operations(body) {
    let kind = operation.kind
    if kind == "init" {
      timeline = _add(timeline, 0, operation.args, 0, 1, 0, "linear", none, "append")
    } else if kind == "animate" {
      let implicit-block = operation.block < 0
      let block = if implicit-block { maximum } else { operation.block }
      current = block
      timeline = _add(
        timeline,
        block,
        operation.args,
        operation.hold,
        operation.duration,
        operation.dwell,
        operation.transition,
        operation.morph-effect,
        if implicit-block { "append" } else { "place" },
      )
      maximum = if implicit-block { maximum + 1 } else { maximum }
    } else if kind in ("meanwhile", "then") {
      timeline = _add(timeline, current, operation.args, operation.hold, operation.duration, operation.dwell, operation.transition, operation.morph-effect, if kind == "meanwhile" { "place" } else { "append" })
    } else if kind == "wait" {
      let block = if operation.block < 0 { current } else { operation.block }
      timeline = _add(timeline, block, (builtin_pause_counter: 0%), 0, operation.duration, 0, "linear", none, "append")
    } else if kind == "cut" {
      cuts.push(current)
      if operation.loop { loops.push(current) }
    }
  }
  (timeline: timeline, cuts: cuts, loops: loops)
}
