#import "@preview/touying:0.7.3": pause
#import "../../lib.typ": a
#import "theme.typ": *

#show: suig-theme.with(footer: [Quentin Bramas · Simulant and myopic stand-up indulgent gathering])

// ------------------------------------------------------------- helpers ------
#let space-c = accent
#let view-c = teal
#let frame-c = rgb("#7a3ea8")
#let state-c = rgb("#b4581c")
#let sense-c = rgb("#3a7d2c")
#let sched-c = rgb("#5f6b7a")
#let fault-c = alert

// Tags for the robots of a recorded round, from the rule each one applies.
// `labels` maps a rule to (label, color) or (label, color, "above"); the arrow
// shows the direction of the recorded move.
#let rule-tags(name, t, labels, rounds: auto) = {
  let frame = state-at(name, t)
  if rounds != auto and frame.round not in rounds { return () }
  if frame.round >= frame.last { return () }
  let states = recordings.at(name).states
  let before = states.at(frame.round).positions
  let after = states.at(frame.round + 1).positions
  let seen = ()
  let tags = ()
  for (i, rule) in frame.rules.enumerate() {
    if rule in labels {
      let entry = labels.at(rule)
      let (label, color) = (entry.at(0), entry.at(1))
      let side = if entry.len() > 2 { entry.at(2) } else { "below" }
      let d = after.at(i) - before.at(i)
      let shown = if d > 0 [#label →] else if d < 0 [← #label] else [#label]
      let p = frame.positions.at(i)
      let key = str(calc.round(p, digits: 2)) + rule
      if key not in seen {
        seen.push(key)
        tags.push((p, shown, color, side))
      }
    }
  }
  tags
}

// ---------------------------------------------------------------- title -----
#title-slide(
  title: [Simulant: Writing Down\ Robot Models],
  subtitle: [and myopic stand-up indulgent gathering on a line],
  author: [Quentin Bramas],
  affiliation: [University of Strasbourg · ICube],
  collaborators: [Gathering results: joint work with H. Kakugawa, S. Kamei, A. Lamani, F. Ooshita, M. Shibata and S. Tixeuil.],
  picture: line-view((0, 4, 8, 9, 10, 12, 15), low: -1, high: 16, width: 1000, views: ((10, 5),), dim: (0, 4)),
)

#slide(title: [Outline])[
  #v(20pt)
  #grid(columns: (90pt, 1fr), row-gutter: 40pt,
    text(size: 34pt, fill: accent, weight: "bold")[01], [*Simulant* \ #note[the usual robot assumptions, written as declarations]],
    text(size: 34pt, fill: accent, weight: "bold")[02], [*Stand-up indulgent gathering* \ #note[the whole setting in one `.sim` block]],
    text(size: 34pt, fill: accent, weight: "bold")[03], [*The $H + 1$ algorithm* \ #note[merging three nodes into one, with myopic robots]],
    text(size: 34pt, fill: accent, weight: "bold")[04], [*Open problems* \ #note[two cases we cannot settle yet]],
  )
]

// =========================================================== 1. Simulant ====
#section-slide([01], [Simulant], [Robot models as executable declarations])

#slide(title: [Simulant])[
  Papers state their model in prose. Simulant states it in a `.sim` file.
  #v(34pt)
  #grid(columns: (1fr, 70pt, 1.15fr), align: horizon,
    card(fill: accent-soft, inset: 26pt)[
      #eyebrow[an experiment]
      #v(14pt)
      #stack(spacing: 16pt,
        [*Model* #h(4pt) #note[what robots are and see]],
        [*Algorithm* #h(4pt) #note[what they decide]],
        [*Task* #h(4pt) #note[what must happen]],
        [*Experiment* #h(4pt) #note[initial configurations]],
      )
    ],
    align(center, text(size: 44pt, fill: faint, sym.arrow.r)),
    stack(spacing: 16pt,
      card(inset: 20pt)[*Simulate* \ #note[step through executions, inspect each view]],
      card(inset: 20pt)[*Explore* \ #note[follow every adversary choice, up to a bound]],
      card(inset: 20pt)[*Prove* \ #note[export the model as Lean definitions]],
    ),
  )
  #v(1fr)
  #note[Open source · #link("https://bramas.github.io/simulant/")[bramas.github.io/simulant] · every execution in this talk is recorded from the simulator.]
]

// The assumptions of a model, as a paper lists them, with the standard
// library definitions that implement each one. `pick` is the one we keep.
#let choices = (
  (label: [Topology], prose: [ring · line · dynamic ring], field: "space", pick: 0, options: (
    (value: "Graphs.Cycle (param n)", caption: [a ring of $n$ nodes],
      source: "def Graphs.Cycle (n : Nat) : Space where\n  vertices := range n\n  neighbors v := [(v + 1) % n, (v + n - 1) % n]\n  …"),
    (value: "Graphs.Line", caption: [the infinite line],
      source: "def Graphs.Line : Space where\n  Vertex := Int\n  neighbors v := [v + 1, v - 1]\n  …"),
    (value: "Graphs.Dynamic (Graphs.Cycle (param n)) 1",
      caption: [built in: the adversary removes up to one edge per round]),
  )),
  (label: [Visibility], prose: [full · up to $phi$ hops], field: "observation", pick: 0, options: (
    (value: "Observe.full", caption: [built in: every node and edge of a finite space]),
    (value: "Observe.radius (param phi)", caption: [built in: the nodes within $phi$ hops]),
  )),
  (label: [Orientation], prose: [chirality · per robot · none], field: "frames", pick: 0, options: (
    (value: "Frames.identity", caption: [built in: the ports as they are, so all robots agree on clockwise]),
    (value: "Frames.portPermutations .perRobot", caption: [built in: each robot permutes its ports once, for good]),
    (value: "Frames.isomorphisms", caption: [built in: any isomorphism of the view, chosen again at each Look]),
  )),
  (label: [Multiplicity], prose: [none · weak · strong], field: "sensors", pick: 2, options: (
    (value: "[occupied]", caption: [none],
      source: "sensor occupied (L : Look) (l : Loc) : Bool :=\n  (L.occupants l).any present"),
    (value: "[localMultiplicity]", caption: [weak, on the robot's own node only: one robot, or several]),
    (value: "[count]", caption: [strong],
      source: "sensor count (L : Look) (l : Loc) : Nat :=\n  (L.occupants l).count present"),
  )),
  (label: [Memory], prose: [oblivious · persistent · lights], field: "memory", pick: 0, options: (
    (value: ".oblivious", caption: [built in: nothing is kept between two activations]),
    (value: ".persistent", caption: [built in: a program counter and local variables persist]),
    (value: "Storage.Lights k", caption: [a light, as a component],
      source: "def Storage.Lights (colors : Nat) : Component where\n  Agent := { light : Nat }\n  actions := [action setLight : Option Nat := none]\n  …"),
  )),
  (label: [Synchrony], prose: [FSYNC · SSYNC · ASYNC], field: "scheduler", pick: 1,
    footnote: [`choose` is the adversary: a simulation follows one choice, exploration all of them.],
    options: (
    (value: "Schedulers.FSync",
      source: "def Schedulers.FSync : Scheduler where\n  fairness := .none\n  schedule C := { activate := C.eligible }"),
    (value: "Schedulers.SSync",
      source: "def Schedulers.SSync : Scheduler where\n  schedule C :=\n    let S := choose (nonemptySubsets C.eligible)\n    { activate := S }"),
    (value: "Schedulers.Async", caption: [the same choice, but Look, Compute and Move are separate events]),
  )),
  (label: [Faults], prose: [none · crashes · at one node], field: "components", pick: 0, options: (
    (value: "[]", caption: [no faults]),
    (value: "[Faults.CrashStop 1]", caption: [one robot may crash, anywhere, at any time]),
    (value: "[Faults.CrashAt]", caption: [crashes at one node],
      source: "def Faults.CrashAt : Component where\n  World := { crashNode : Pos }\n  flags := [flag crashed visible, acts never]\n  …"),
  )),
)

#let ring-sentence = [
  #text(size: 28pt)[“Oblivious robots on a ring of $n$ nodes, with chirality, full visibility and strong multiplicity detection, under SSYNC.”]
  #v(20pt)
  #note[One declaration: simulated, explored and exported to Lean.]
]

#slide(title: [Building a model], id: "build")[
  #let last = 2 * choices.len() + 1
  #init(t: if handout { float(last) } else { 0.0 })
  #if not handout {
    for target in range(1, last + 1) {
      animate(t: float(target), duration: if calc.even(target) { 1.3 } else { 0.6 }, transition: "linear")
      cut()
    }
  }
  #context model-builder(choices, a("t"), name: "ringRobots",
    intro: [
      #lead[A paper fixes these choices in its model section.]
      #v(18pt)
      #note[Simulant has a definition for each option. We pick one per row.]
    ],
    outro: ring-sentence,
  )
]

// The model built above, then models that change some of its fields.
#let ring-rows = (
  ("space", "Graphs.Cycle (param n)"),
  ("observation", "Observe.full"),
  ("frames", "Frames.identity"),
  ("sensors", "[count]"),
  ("memory", ".oblivious"),
  ("scheduler", "Schedulers.SSync"),
  ("components", "[]"),
)
#let with-rows(rows, ..changes) = {
  let changes = changes.named()
  rows.map(((field, value)) => (field, changes.at(field, default: value)))
}
#let ring-model = (name: "ringRobots", rows: ring-rows, side: ring-sentence)

#let async-rows = with-rows(ring-rows, scheduler: "Schedulers.Async")
#let variant-models = (
  ring-model,
  (name: "asyncRingRobots", rows: async-rows, side: [
    #lead[The same robots, asynchronous.]
    #v(18pt)
    #note[Look, Compute and Move become separate events.]
  ]),
  (name: "luminousRobots", rows: with-rows(async-rows, sensors: "[count, colors, ownLight]", components: "[Storage.Lights 3]"), side: [
    #lead[… with a light of three colors.]
    #v(18pt)
    #note[A light is a component; two sensors read the colors.]
  ]),
  (name: "dynamicRingAgents", rows: (
    ("space", "Graphs.Dynamic (Graphs.Cycle (param n)) 1"),
    ("observation", "Observe.radius 1"),
    ("frames", "Frames.identity"),
    ("sensors", "[occupied, edgeTo]"),
    ("memory", ".persistent"),
    ("scheduler", "Schedulers.FSync"),
    ("components", "[]"),
  ), side: [
    #lead[Mobile agents with memory, on a ring that may miss one edge per round.]
    #v(18pt)
    #note[They see their neighbors, and which edges are present.]
  ]),
)

#slide(title: [Other models], id: "variants")[
  #run(variant-models.len() - 1, duration: 0.9)
  #context model-variants(variant-models, a("t"))
]

// ================================================================ 2. SUIG ===
#section-slide([02], [Stand-up indulgent gathering], [The setting of the previous talk, as one block of `.sim`])

#slide(title: [The problem], id: "recap")[
  #run-phases(("plain", 4, (4,), false), ("crash", 6, (6,), false), duration: 0.75)
  #v(1fr)
  #context {
    lane("gather", a("plain"), label: [no crash], label-color: accent, badge: "count")
    v(14pt)
    lane("gather-crash", a("crash"), label: [crash at one node], label-color: alert, badge: "count")
  }
  #v(40pt)
  Without crash, gather anywhere. With crashes, *all correct robots gather at the crash node*.
  #v(10pt)
  #note[FSYNC · oblivious · disoriented · visibility radius $phi$ · no multiplicity detection. Numbers in the discs are for us, not for the robots.]
  #v(1fr)
]

#let suig-models = (
  ring-model,
  (name: "myopicRobots", rows: (
    ("space", "Graphs.Line"),
    ("observation", "Observe.radius (param phi)"),
    ("frames", "Frames.isomorphisms"),
    ("sensors", "[occupied]"),
    ("memory", ".oblivious"),
    ("scheduler", "Schedulers.FSync"),
    ("components", "[Faults.CrashAt]"),
  ), tags: (
    ([a line], space-c),
    ([myopic], view-c),
    ([disoriented], frame-c),
    ([no multiplicity detection], sense-c),
    ([oblivious], state-c),
    ([FSYNC], sched-c),
    ([crashes at one node], fault-c),
  )),
)

#slide(title: [The model], id: "suig-model")[
  #run(1, duration: 1.0)
  #context model-variants(suig-models, a("t"))
]

#slide(title: [The experiment])[
  #grid(columns: (1.5fr, 1fr), column-gutter: 34pt, align: top,
    [
      #set text(size: 31pt)
```sim
experiment hPlusOne where
  model := lineModel
  algorithm := ObliviousHPlusOne
  task := Gathering
  param positions : List Int
    where admissiblePositions positions true
  param phi : Nat
    where phi ≥ requiredVisibility positions 1
  param crashNode : Pos
  agents := positions.length
  position i := pos (positions.at i)
```
    ],
    [
      #set text(size: 26pt)
      #stack(spacing: 24pt,
        [#pill(color: teal)[domain] #h(6pt) $O_"init"$ is odd],
        [#pill(color: teal)[domain] #h(6pt) $phi >= max(4, H_"init" + 1)$],
        [#pill(color: alert)[adversary] #h(6pt) any crash node],
        [#pill(color: accent)[task] #h(6pt) all robots on one node],
      )
      #v(24pt)
      #note[`lineModel` is the public project's `myopicRobots`; with lights, it runs the two-color algorithm. Robots never read $phi$: it only reaches `Observe.radius`.]
    ],
  )
]

#slide(title: [A rule])[
  #let config = (0, 4, 8, 9, 10, 12, 15)
  #grid(columns: (130pt, 1fr), align: horizon,
    text(size: 22pt, weight: "bold", fill: teal)[`lineView`],
    line-view(config, low: -1, high: 16, width: 990, views: ((10, 5),), dim: (0, 4), bits: (10, 5), height: 120),
  )
  #v(14pt)
  #v(1fr)
  #grid(columns: (1fr, 1.2fr), column-gutter: 26pt,
    [
      #set text(size: 29pt)
```sim
def h1Border (v : List Nat) : Bool :=
  let p := v.length / 2
  border v ∧ nonempty v (p + 1) p
```
    ],
    [
      #set text(size: 29pt)
```sim
algorithm ObliviousHPlusOne uses occupied where
  main :=
    let v := lineView
    if h1BorderIdle1 v ∨ … then stay
    else if h1Border v then move Ring.cw
    …
```
    ],
  )
  #v(1fr)
  #note[The robot at node 10 does not know that nodes 0 and 4 exist. Each rule of the paper is one guard, tried in the paper's priority order.]
]

// ========================================================== 3. H + 1 =======
#section-slide([03], [The $H + 1$ algorithm], [Merging three nodes into one, with myopic robots])

#slide(title: [Known results])[
  #grid(columns: (auto, 1fr), column-gutter: 46pt, align: horizon,
    results-map(focus: ((3, 1), (4, 1), (5, 1), (6, 1), (2, 2))),
    [
      #set text(size: 26pt)
      #stack(spacing: 26pt,
        [#pill(color: teal)[✓ solved] #pill(color: alert)[✕ impossible] #pill(color: amber)[? open]],
        [*Previous talk:* two colors at $phi = H$; oblivious at $phi = H + 3$.],
        [*This talk:* oblivious at $phi = max(4, H + 1)$, the framed cells.],
        [Oblivious robots, $O_"init"$ odd.],
        [Without colors, $phi = H$ is impossible for $H in {2, 3}$.],
      )
    ],
  )
  #v(1fr)
  #note[$H$: largest gap between consecutive occupied nodes. $O_"init"$: number of occupied nodes.]
]

#slide(title: [Merging], id: "merge")[
  #run(3, duration: 1.0, stops: (1, 2, 3))
  #v(1fr)
  #context {
    let t = a("t")
    let tags = rule-tags("merge", t, (
      h1Border: ([border], accent),
      h1SecondNeighborMerge: ([merge], teal),
    ), rounds: (1,))
    lane("merge", t, tags: tags)
  }
  #v(50pt)
  #grid(columns: (1fr, 1fr), column-gutter: 44pt,
    [
      An *edge-symmetric* configuration is a dead end: two mirrored halves, forever.
      #v(8pt)
      #note[An odd number of occupied nodes is never edge-symmetric.]
    ],
    [
      So merges remove occupied nodes *in pairs*. At a border, a 3-block merges into its middle node: $3 -> 1$.
    ],
  )
  #v(1fr)
]

#slide(title: [False borders])[
  #let config = (0, 4, 8, 9, 10, 12, 15)
  #v(1fr)
  #grid(columns: (210pt, 1fr), row-gutter: 20pt, column-gutter: 10pt, align: horizon,
    [#eyebrow(color: teal)[Robot at 10]\ #text(size: 24pt)[sees 5 to 15]],
    line-view(config, low: -1, high: 16, width: 920, views: ((10, 5),), dim: (0, 4),
      tags: ((10, [me], teal), (8, [border?], alert))),
    [#eyebrow(color: teal)[Robot at 9]\ #text(size: 24pt)[sees 4 to 14]],
    line-view(config, low: -1, high: 16, width: 920, views: ((9, 5),), dim: (0,),
      tags: ((9, [me], teal), (4, [not a border], teal))),
  )
  #v(40pt)
  From node 10, the block $8, 9, 10$ looks like a border 3-block: node 4 is one hop too far.
  #v(10pt)
  #note[$phi = 5$, $H = 4$. With $phi = H + 1$, a robot two hops into a block cannot always see past it.]
  #v(1fr)
]

#slide(title: [A false merge], id: "false-border-without")[
  #run(13, duration: 0.5, stops: (1, 13), loop: true)
  #v(1fr)
  #context {
    let t = a("t")
    let tags = rule-tags("false-border-without", t, (
      h1SecondNeighborMerge: ([merge], alert),
    ), rounds: (0,))
    lane("false-border-without", t, tags: tags)
    v(50pt)
    let round = state-at("false-border-without", t).round
    if round < 1 {
      lead[Node 10 merges into 9, but node 8 is not a border: it stays.]
    } else if round < 11 {
      lead[Two occupied nodes instead of one: #em-alert[$7 -> 6$], the parity is lost.]
    } else {
      lead[Two adjacent nodes swap forever: #em-alert[gathering fails].]
    }
  }
  #v(16pt)
  #note[Recorded with the public algorithm minus one rule, `neig, false-merge`.]
  #v(1fr)
]

#slide(title: [Fix 1: swap], id: "false-border")[
  #run(12, duration: 0.5, stops: (1, 12))
  #v(1fr)
  #context {
    let t = a("t")
    let tags = rule-tags("false-border", t, (
      h1SecondNeighborMerge: ([merge], teal),
      h1NeighborFalseMerge: ([steps aside], accent, "above"),
    ), rounds: (0,))
    lane("false-border", t, tags: tags)
  }
  #v(40pt)
  #grid(columns: (1fr, 1.45fr), column-gutter: 30pt, align: horizon,
    [
      Node 9 sees node 4: the merge is false. It swaps with the merging robot, so #em-teal[7 occupied nodes remain].
      #v(10pt)
      #note[It knows node 10 cannot see node 4.]
    ],
    [
      #set text(size: 28pt)
```sim
-- X, φ-2 empty nodes, X, [me], X, empty, X
def h1NeighborFalseMerge (v : List Nat) : Bool :=
  let p := v.length / 2
  occupiedAt v 0 ∧ empty v 1 (p - 2) ∧
  occupiedAt v (p - 1) ∧ occupiedAt v (p + 1) ∧
  empty v (p + 2) 1 ∧ occupiedAt v (p + 3)
```
    ],
  )
  #v(1fr)
]

#slide(title: [Fix 2: wait], id: "border-wait")[
  #run-phases(("without", 5, (2, 5), true), ("with", 4, (2, 4), false), duration: 0.8)
  #v(1fr)
  #context {
    let (t1, t2) = (a("without"), a("with"))
    lane("border-wait-without", t1, label: [border always moves], label-color: alert, badge: "symmetry",
      tags: rule-tags("border-wait-without", t1, (h1Border: ([moves], alert),), rounds: (2,)))
    v(14pt)
    lane("border-wait", t2, label: [border waits], label-color: teal, badge: "symmetry",
      tags: rule-tags("border-wait", t2, (h1BorderIdle1: ([waits], teal),), rounds: (2,)))
  }
  #v(40pt)
  In $X X dot X$, a moving border lands next to its neighbor: $X X$ is edge-symmetric, a dead end. Waiting one round gives $X dot X$, which gathers in the middle.
  #v(10pt)
  #note[Rule `border-idle,1`: a border followed by a robot, then an empty node, stays idle.]
  #v(1fr)
]

#slide(title: [Fix 3: split long blocks], id: "long-block")[
  #run-phases(("without", 2, (2,), false), ("with", 4, (1, 4), false), duration: 0.9)
  #v(1fr)
  #context {
    let (t1, t2) = (a("without"), a("with"))
    lane("long-block-without", t1, label: [no block rule], label-color: alert,
      tags: rule-tags("long-block-without", t1, (h1BorderIdle2: ([waits], alert),), rounds: (0,)))
    v(14pt)
    lane("long-block", t2, label: [4-merge], label-color: teal,
      tags: rule-tags("long-block", t2, (h1FourMerge1: ([merge], teal),), rounds: (0,)))
  }
  #v(40pt)
  Without a rule for long blocks, both borders wait forever. In blocks of four or more, the second and third robots move *outwards*: $dot X X X X dot -> dot X dot dot X dot$, again two nodes fewer.
  #v(10pt)
  #note[Rules `4-merge,1` and `4-merge,2` apply anywhere in the configuration.]
  #v(1fr)
]

#slide(title: [Correctness])[
  #card(fill: accent-soft, inset: 24pt)[
    *Theorem.* Oblivious robots solve stand-up indulgent gathering on a line if $phi >= max(4, H_"init" + 1)$ and $O_"init"$ is odd.
  ]
  #v(24pt)
  #enum(spacing: 22pt,
    [*Gaps stay below $phi$.* Every robot can tell whether it, or its neighbor, is a border.],
    [*Without crash,* merges remove occupied nodes in pairs while the borders close in; the last rounds are a finite case analysis.],
    [*With crashes,* the diameter still shrinks to 3 or 4, and a case analysis on the crash position finishes.],
  )
  #v(1fr)
  #note[The three fixes are guards of the public `h-plus-one.sim`. Each counterexample above is that file with one rule removed.]
]

// ===================================================== 4. Open problems ====
#section-slide([04], [Open problems], [Two cells of the map are still empty])

#slide(title: [Open problems])[
  #grid(columns: (auto, 1fr), column-gutter: 46pt, align: horizon,
    results-map(focus: ((4, 0), (5, 0), (6, 0), (2, 1)), dim-others: true),
    [
      #stack(spacing: 30pt,
        [#pill(color: amber)[1] #h(8pt) $phi = H$ for $H >= 4$ \ #note[impossible for $H in {2, 3}$, proved by hand]],
        [#pill(color: amber)[2] #h(8pt) $H = 2$ with $phi = 3$ \ #note[our algorithm needs $phi >= 4$]],
        [We believe *both are impossible* for oblivious robots.],
      )
    ],
  )
]

#slide(title: [Open problem 1: $phi = H$])[
  #grid(columns: (1fr, 1fr), column-gutter: 46pt,
    [
      #eyebrow(color: amber)[Crashes force rules]
      #v(10pt)
      #line-view((0, 3, 6), low: -1, high: 7, width: 500, crashed: (false, true, false), views: ((0, 3),),
        tags: ((0, [must move →], amber),))
      #v(8pt)
      #text(size: 24pt)[Middle robot crashed: a border that sees one robot must move towards it, or gathering never happens.]
    ],
    [
      #eyebrow(color: alert)[… until a symmetry]
      #v(10pt)
      #line-view((0, 1, 2, 5, 7), low: -1, high: 8, width: 500, arrows: ((0, 1, accent), (7, 6, accent)))
      #line-view((1, 1, 2, 5, 6), low: -1, high: 8, width: 500, highlight: (1, 6), highlight-color: alert)
      #text(size: 24pt)[$H = 3$: if the robot at 2 stays, forced rules give $X X dot dot X X$. Its other choices fail too.]
    ],
  )
  #v(1fr)
  The proofs for $H = 2, 3$ chain such forced rules by hand. For $H >= 4$ the views multiply, and we have no general construction yet.
]

#slide(title: [Open problem 2: $H = 2$, $phi = 3$])[
  The algorithm needs $phi >= 4$: for $H = 2$, two hops above the trivial bound. Is $phi = 3$ enough?
  #v(26pt)
  #grid(columns: (1fr, 1fr), column-gutter: 46pt,
    card(inset: 26pt)[
      #eyebrow(color: amber)[Forced rules]
      #v(18pt)
      #grid(columns: (auto, 1fr), column-gutter: 24pt, row-gutter: 30pt, align: horizon,
        rule-view((".", ".", ".", "[X]", "X", "X", "."), move: "right"),
        text(size: 23pt)[border of $X X X$: move in],
        rule-view((".", ".", ".", "[X]", ".", "X", "."), move: "right"),
        text(size: 23pt)[one robot in view: move towards it],
      )
    ],
    [
      Crash scenarios force these rules, and each forced rule removes options for the others.
      #v(16pt)
      #em-amber[Conjecture:] no oblivious algorithm for $H = 2$ and $phi = 3$.
      #v(16pt)
      #note[The case analysis is not complete. Searching rule tables with the forced rules fixed could be a job for Simulant.]
    ],
  )
]

// ============================================================ closing ======
#slide(title: [Conclusion], section: none)[
  #stack(spacing: 30pt,
    grid(columns: (64pt, 1fr), text(fill: accent, weight: "bold", size: 34pt)[1],
      [A paper's assumptions are the *arguments of one definition*; the same `.sim` file is simulated, explored and exported to Lean.]),
    grid(columns: (64pt, 1fr), text(fill: teal, weight: "bold", size: 34pt)[2],
      [Myopic oblivious robots gather with $phi = max(4, H + 1)$ when $O_"init"$ is odd. Blind $3 -> 1$ merges break the parity; *three small rules* repair them.]),
    grid(columns: (64pt, 1fr), text(fill: amber, weight: "bold", size: 34pt)[3],
      [Open: $phi = H$ for $H >= 4$, and $H = 2$ with $phi = 3$.]),
  )
  #v(1fr)
  #grid(columns: (1fr, 1.2fr), column-gutter: 40pt,
    note[#link("https://bramas.github.io/simulant/standup-gathering/")[bramas.github.io/simulant/standup-gathering] \ the algorithms, in the browser],
    note[Q. Bramas, H. Kakugawa, S. Kamei, A. Lamani, F. Ooshita, M. Shibata, S. Tixeuil. _A Visibility vs. Memory Trade-Off for Stand-Up Indulgent Gathering on Lines._ SIROCCO 2025.],
  )
]

#touying-slide-wrapper(self => {
  let self = utils.merge-dicts(self, config-common(freeze-slide-counter: true), config-page(footer: none))
  touying-slide(self: self, align(center + horizon)[
    #text(size: 64pt, weight: "bold")[Thank you]
    #v(16pt)
    #text(size: 30pt, fill: muted)[Questions?]
    #v(44pt)
    #line-view((8, 8, 8, 8, 8, 8, 8), low: 3, high: 13, width: 700)
  ])
})
