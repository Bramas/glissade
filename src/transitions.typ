/// Linear transition
#let linear(t) = t

/// Manim-like smooth transition based on a normalized sigmoid.
#let smooth(t, inflection: 10) = {
  let sigmoid = x => 1 / (1 + calc.exp(-x))
  let start = sigmoid(-inflection / 2)
  let end = sigmoid(inflection / 2)
  let value = sigmoid(inflection * (t - 0.5))
  calc.clamp((value - start) / (end - start), 0, 1)
}

/// Quadratic transition (power of two)
#let quad(t) = calc.pow(t, 2)

/// Cubic transition (power of three)
#let cubic(t) = calc.pow(t, 3)

/// Quartic transition (power of four)
#let quart(t) = calc.pow(t, 4)

/// Sine transition
#let sin(t) = 1 - calc.cos(t * calc.pi / 2)

/// Circular transition (square root)
#let circ(t) = calc.sqrt(t)

/// Concatenates two transitions
#let concat(
  /// -> transition
  trans1,
  /// -> transition
  trans2,
) = {
  t => {
    if t < 0.5 { trans1(t * 2) / 2 } else { 0.5 + trans2(t * 2 - 1) / 2 }
  }
}

/// Cubic ease-in: starts slowly, ends at full speed.
#let ease-in(t) = calc.pow(t, 3)

/// Cubic ease-out: starts at full speed, settles gently.
#let ease-out(t) = 1 - calc.pow(1 - t, 3)

/// Cubic ease-in-out: a gentler curve than `smooth`, which spends most of its
/// time almost still and can look abrupt on short moves.
#let ease-in-out(t) = if t < 0.5 { 4 * calc.pow(t, 3) } else { 1 - calc.pow(-2 * t + 2, 3) / 2 }

#let _transitions = (
  "linear": linear,
  "smooth": smooth,
  "quad": quad,
  "cubic": cubic,
  "quart": quart,
  "sin": sin,
  "circ": circ,
  "ease-in": ease-in,
  "ease-out": ease-out,
  "ease-in-out": ease-in-out,
)

/// Resolves a transition given by name; functions are returned as they are.
#let get_transition(tr) = {
  if type(tr) == str {
    assert(tr in _transitions, message: "unknown transition \"" + tr + "\"; expected one of " + _transitions.keys().join(", ") + ", or a function")
    _transitions.at(tr)
  } else {
    tr
  }
}
