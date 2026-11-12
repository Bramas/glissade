#import "@preview/touying:0.7.3": pause
#import "../../lib.typ": a
#import "theme.typ": *

// The four parts of the talk: the outline, the dividers and the footer use them.
#let sections = (
  (title: [Simulant],
    note: [the usual robot assumptions, written as declarations],
    summary: [Robot models as executable declarations]),
  (title: [Stand-up indulgent gathering],
    note: [the whole setting in one `.sim` block],
    summary: [The setting of the previous talk, as one block of `.sim`]),
  (title: [The $H + 1$ algorithm],
    note: [merging three nodes into one, with myopic robots],
    summary: [Merging three nodes into one, with myopic robots]),
  (title: [Open problems],
    note: [two cases settled this week, one left],
    summary: [Two cases settled this week, one left]),
)

#show: suig-theme.with(
  footer: [Quentin Bramas · Simulant and myopic stand-up indulgent gathering],
  sections: sections,
)

// ------------------------------------------------------------- helpers ------
#let space-c = accent
#let view-c = teal
#let frame-c = rgb("#7a3ea8")
#let state-c = rgb("#b4581c")
#let sense-c = rgb("#3a7d2c")
#let sched-c = rgb("#5f6b7a")
#let fault-c = alert
// The robots at nodes 4, 8, 9, 10 of the false-border example, named so that
// the text can point at them; the letters follow the robots when they move.
#let abcd = (none, [a], [b], [c], [d])
#let rb(name) = text(fill: accent, weight: "bold", name)

// ---------------------------------------------------------------- title -----
#title-slide(
  eyebrow: [Mobile robots · Formal models],
  title: [Simulant: Writing Down\ Robot Models],
  subtitle: [and myopic stand-up indulgent gathering on a line],
  author: [Quentin Bramas],
  affiliation: [University of Strasbourg · ICube],
  collaborators: [Gathering results: joint work with H. Kakugawa, S. Kamei,\ A. Lamani, F. Ooshita, M. Shibata and S. Tixeuil.],
  picture: line-view((0, 4, 8, 9, 10, 12, 15), low: -1, high: 16, width: 1112, views: ((10, 5),), dim: (0, 4)),
)

#outline-slide()

// =========================================================== 1. Simulant ====
#section-slide(1)

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
  (label: [Sensors], prose: [multiplicity · states · edges · …], field: "sensors", pick: 2,
    footnote: [A model lists its sensors; an algorithm declares the ones it uses.],
    options: (
    (value: "[occupied]", caption: [no multiplicity detection],
      source: "sensor occupied … := (L.occupants l).any present"),
    (value: "[localMultiplicity]", caption: [weak multiplicity detection, on the robot's own node]),
    (value: "[count]", caption: [strong multiplicity detection],
      source: "sensor count … := (L.occupants l).count present"),
    (value: "[otherStates]", caption: [the public states of the other agents on the robot's node]),
    (value: "[edgeTo]", caption: [is this edge present?],
      source: "sensor edgeTo … := L.edgePresent L.here l"),
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
    ("sensors", "[otherStates, edgeTo]"),
    ("memory", ".persistent"),
    ("scheduler", "Schedulers.FSync"),
    ("components", "[]"),
  ), side: [
    #lead[Mobile agents with memory, on a ring that may miss one edge per round.]
    #v(18pt)
    #note[They read the states of the agents on their node, and which edges are present.]
  ]),
)

#slide(title: [Other models], id: "variants")[
  #run(variant-models.len() - 1, duration: 0.9)
  #context model-variants(variant-models, a("t"))
]

#slide(title: [Tasks])[
  A *task* gives each configuration a verdict; its *goal* says which executions succeed.
  #v(18pt)
  #grid(columns: (1fr, 250pt), column-gutter: 26pt, row-gutter: 18pt, align: horizon,
    {
      set text(size: 29pt)
      ```sim
      /-- Eventually, and forever, at most one present robot per position. -/
      task Dispersion (C : Config) : Verdict :=
        let robots := C.agents.filter present
        if robots.all fun a => robots.count (fun b => b.pos = a.pos) = 1
        then .success else .inProgress

      goal Dispersion := eventually always .success
      ```
    },
    stack(spacing: 14pt, pill(color: teal)[eventually always], note[from some point on, forever]),
    {
      set text(size: 29pt)
      ```sim
      /-- Every position has been visited, eventually. -/
      task Exploration (C : Config) : Verdict :=
        if C.positions.all fun p => C.world.visited.contains p
        then .success else .inProgress

      goal Exploration := eventually .success
      ```
    },
    stack(spacing: 14pt, pill(color: teal)[eventually], note[`visited` is a field of the component `Monitors.Visited`]),
  )
  #v(1fr)
  #note[Tasks read positions; robots never do. The third kind of goal is `always ¬ .failure`.]
]

// ================================================================ 2. SUIG ===
#section-slide(2)

#slide(title: [The problem], id: "recap")[
  #run-phases(("plain", 4, (4,), false), ("crash", 6, (6,), false), duration: 0.8)
  #context {
    lane("gather", a("plain"), label: [No crash], label-color: accent, badge: "count")
    v(4pt)
    lane("gather-crash", a("crash"), label: [Crash at one node], label-color: alert, badge: "count")
  }
  #v(1fr)
  Without crash, gather anywhere. With crashes, *all correct robots gather at the crash node*.
  #v(10pt)
  #note[FSYNC · oblivious · disoriented · visibility radius $phi$ · no multiplicity detection. Numbers in the discs are for us, not for the robots.]
  #v(0.5fr)
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

#slide(title: [The task])[
  #{
    ```sim
    /-- Every present robot is on the same position, eventually. -/
    task Gathering (C : Config) : Verdict :=
      let robots := C.agents.filter present
      if robots.all fun a => robots.all fun b => a.pos = b.pos
      then .success else .inProgress

    goal Gathering := eventually .success
    ```
  }
  #v(1fr)
  #grid(columns: (1fr, 1fr, 1fr), column-gutter: 22pt,
    card(inset: 20pt, height: 160pt)[#text(size: 24pt)[The library's `Gathering`, unchanged.]],
    card(inset: 20pt, height: 160pt)[#text(size: 24pt)[`Faults.CrashAt` raises `flag crashed visible`: a crashed robot is not correct, but still *present*.]],
    card(fill: accent-soft, inset: 20pt, height: 160pt)[#text(size: 24pt)[So with a crash, every robot on one node means #em-accent[at the crash node].]],
  )
  #v(1fr)
]

#slide(title: [The experiment])[
  #let rows = (
    ("experiment hPlusOne where", none),
    ("  model := myopicRobots", none),
    ("  algorithm := ObliviousHPlusOne", none),
    ("  task := Gathering", none),
    ("  param positions : List Int", none),
    ("    where admissiblePositions positions true", [at least 2 robots, $O_"init"$ odd]),
    ("  param phi : Nat", none),
    ("    where phi ≥ requiredVisibility positions 1", [$phi >= max(4, H_"init" + 1)$]),
    ("  param crashNode : Pos", [any node]),
    ("  agents := positions.length", none),
    ("  position i := pos (positions.at i)", none),
  )
  #let row = 38pt
  #grid(columns: (auto, 1fr), column-gutter: 24pt,
    block(radius: 12pt, fill: tint, inset: (x: 24pt, y: 12pt),
      stack(..rows.map(((line, _)) => box(height: row, align(horizon, code(line, size: 23pt)))))),
    block(inset: (y: 12pt), stack(..rows.enumerate().map(((i, (_, domain))) => box(height: row, align(horizon,
      if i == 0 { eyebrow(color: teal, size: 16pt)[domain, where the adversary chooses] }
      else if domain != none { text(size: 24pt, fill: teal, weight: "bold", domain) }))))),
  )
]

#slide(title: [The algorithm])[
  #grid(columns: (1.2fr, 1fr), column-gutter: 34pt, align: horizon,
    {
      set text(size: 28pt)
      ```sim
      algorithm ObliviousHPlusOne uses occupied where
        main :=
          let v := lineView
          let vm := mirrored v
          -- border-idle,1
          if h1BorderIdle1 v ∨ h1BorderIdle1 vm then
            stay
          …
          -- border
          else if h1Border v then
            move Ring.cw
          …
      ```
    },
    {
      set text(size: 26pt)
      grid(columns: (auto, 1fr), column-gutter: 14pt, row-gutter: 26pt, align: horizon,
        pill(color: sense-c)[sensors], [`uses occupied`],
        pill(color: state-c)[memory], [none: the current view decides],
        pill(color: muted)[not named], [space, scheduler, faults, $phi$],
      )
    },
  )
  #pause
  #v(1fr)
  #card(inset: (x: 22pt, y: 18pt))[
    #set text(size: 20pt)
    #eyebrow(color: muted)[The compiler checks these needs against the model]
    #v(10pt)
    #grid(columns: (310pt, 1fr), row-gutter: 12pt, column-gutter: 16pt,
      [`sensors := [count]`], text(fill: alert)[`uses sensor 'occupied', which the model does not provide`],
      [two `move`s in a row], text(fill: alert)[`in an oblivious model, the algorithm cannot continue after this move (it would need memory)`],
      [`scheduler := Schedulers.SSync`], text(fill: teal)[compiles unchanged],
    )
  ]
  #v(1fr)
]

#slide(title: [A rule])[
  #let config = (0, 4, 8, 9, 10, 12, 15)
  #grid(columns: (130pt, 1fr), align: horizon,
    text(size: 22pt, weight: "bold", fill: teal)[`lineView`],
    line-view(config, low: -1, high: 16, width: 1000, views: ((10, 5),), dim: (0, 4), bits: (10, 5), height: 150, names: abcd),
  )
  #v(1fr)
  #grid(columns: (1fr, 1fr), column-gutter: 26pt,
    [
      #set text(size: 29pt)
```sim
def lineView : List Nat :=
  Line.window.map fun l =>
    if occupied l then 1 else 0
```
    ],
    [
      #set text(size: 29pt)
```sim
def h1Border (v : List Nat) : Bool :=
  let p := v.length / 2
  border v ∧ nonempty v (p + 1) p
```
    ],
  )
  #v(1fr)
  #note[`lineView` reads the window through the sensor `occupied`; each rule of the paper is one guard on it, tried in the paper's priority order. Robot #rb[d] does not see the two faded robots.]
]

// ========================================================== 3. H + 1 =======
#section-slide(3)

#slide(title: [Known results], id: "known-results")[
  #run(4, start: 1, duration: 0.4)
  #v(1fr)
  #context {
    let t = a("t")
    let shown(step) = calc.clamp(t - step + 1, 0, 1)
    // The H = 1 column is already known; the earlier oblivious bound gives
    // the H + 3 row. The new bound fills the remaining solved cells.
    let reveal(h, e, status) = shown(
      if status == "solved" { if h == 1 or e == 3 { 1 } else { 2 } }
      else if status == "impossible" { 3 }
      else { 4 }
    )
    grid(columns: (auto, 1fr), column-gutter: 40pt, align: horizon,
      results-map(focus: ((3, 1), (4, 1), (5, 1), (6, 1), (2, 2)), reveal: reveal, cell: 80pt),
      {
        set text(size: 26pt)
        stack(spacing: 26pt,
          [#status-pill("solved")[solved] #status-pill("impossible", opacity: shown(3))[impossible] #status-pill("open", opacity: shown(4))[open]],
          [*Previous talk:* two colors at $phi = H$; oblivious at $phi = H + 3$.],
          text(fill: alpha(ink, shown(2)))[*This talk:* oblivious at\ $phi = max(4, H + 1)$, the framed cells.],
          [Oblivious robots, $O_"init"$ odd.],
          text(fill: alpha(ink, shown(3)))[Without colors, $phi = H$ is impossible for $H in {2, 3}$.],
        )
      },
    )
  }
  #v(1.3fr)
  #note[$H$: largest gap between consecutive occupied nodes. $O_"init"$: number of occupied nodes.]
]

#slide(title: [Merging], id: "merge")[
  #run(3, duration: 1.0, stops: (1, 2, 3))
  #v(0.6fr)
  #context {
    let t = a("t")
    let tags = rule-tags("merge", t, (
      h1Border: ([border], accent),
      h1SecondNeighborMerge: ([merge], teal),
    ), rounds: (1,))
    lane("merge", t, tags: tags)
  }
  #v(1fr)
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
  #v(0.5fr)
  #grid(columns: (196pt, 1fr), row-gutter: 14pt, column-gutter: 10pt, align: horizon,
    [#eyebrow(color: teal)[Robot d]\ #text(size: 25pt)[does not see #rb[a]]],
    line-view(config, low: -1, high: 16, width: 930, views: ((10, 5),), dim: (0, 4), names: abcd,
      tags: ((10, [me], teal), (8, [border?], alert))),
    [#eyebrow(color: teal)[Robot c]\ #text(size: 25pt)[sees #rb[a]]],
    line-view(config, low: -1, high: 16, width: 930, views: ((9, 5),), dim: (0,), names: abcd,
      tags: ((9, [me], teal), (4, [not a border], teal))),
  )
  #v(1fr)
  For #rb[d], the block #rb[b]#rb[c]#rb[d] looks like a border 3-block: #rb[a] is one hop too far.
  #v(10pt)
  #note[$phi = 5$, $H = 4$. With $phi = H + 1$, a robot two hops into a block cannot always see past it.]
  #v(1fr)
]

#slide(title: [A false merge], id: "false-border-without")[
  #run(13, duration: 0.6, stops: (1, 13), loop: 2)
  #v(0.4fr)
  #context {
    let t = a("t")
    let tags = rule-tags("false-border-without", t, (
      h1SecondNeighborMerge: ([merge], alert),
    ), rounds: (0,))
    lane("false-border-without", t, tags: tags, history: true, names: abcd)
    v(1fr)
    let round = state-at("false-border-without", t).round
    if round < 1 {
      lead[#rb[d] merges into #rb[c], but #rb[b] is not a border: it stays.]
    } else if round < 11 {
      lead[Two occupied nodes instead of one: #em-alert[$7 -> 6$], the parity is lost.]
    } else {
      lead[Two adjacent nodes swap forever: #em-alert[gathering fails].]
    }
  }
  #v(16pt)
  #note[Recorded with the public algorithm minus one rule, `neig, false-merge`.]
  #v(0.6fr)
]

#slide(title: [Fix 1: swap], id: "false-border")[
  #run(12, duration: 0.6, stops: (1, 12))
  #v(0.4fr)
  #context {
    let t = a("t")
    let tags = rule-tags("false-border", t, (
      h1SecondNeighborMerge: ([merge], teal),
      h1NeighborFalseMerge: ([steps aside], accent, "above"),
    ), rounds: (0,))
    lane("false-border", t, tags: tags, names: abcd)
  }
  #v(1fr)
  #grid(columns: (1fr, 1.45fr), column-gutter: 30pt, align: horizon,
    [
      #rb[c] sees #rb[a]: the merge is false. #rb[c] swaps with #rb[d], so #em-teal[7 occupied nodes remain].
      #v(10pt)
      #note[#rb[c] knows that #rb[d] cannot see #rb[a].]
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
  #run-phases(("without", 5, (2, 5), 2), ("with", 4, (2, 4), false), duration: 0.8)
  #context {
    let (t1, t2) = (a("without"), a("with"))
    lane("border-wait-without", t1, label: [The border always moves], label-color: alert, badge: "symmetry",
      tags: rule-tags("border-wait-without", t1, (h1Border: ([moves], alert),), rounds: (2,)))
    v(4pt)
    lane("border-wait", t2, label: [The border waits], label-color: teal, badge: "symmetry",
      tags: rule-tags("border-wait", t2, (h1BorderIdle1: ([waits], teal),), rounds: (2,)))
  }
  #v(1fr)
  In $X X dot X$, a moving border lands next to its neighbor: $X X$ is edge-symmetric, a dead end. Waiting one round gives $X dot X$, which gathers in the middle.
  #v(10pt)
  #note[Rule `border-idle,1`: a border followed by a robot, then an empty node, stays idle.]
  #v(0.5fr)
]

#slide(title: [Fix 3: split long blocks], id: "long-block")[
  #run-phases(("without", 2, (2,), false), ("with", 4, (1, 4), false), duration: 0.9)
  #context {
    let (t1, t2) = (a("without"), a("with"))
    lane("long-block-without", t1, label: [No rule for long blocks], label-color: alert,
      tags: rule-tags("long-block-without", t1, (h1BorderIdle2: ([waits], alert),), rounds: (0,)))
    v(4pt)
    lane("long-block", t2, label: [With the 4-merge rules], label-color: teal,
      tags: rule-tags("long-block", t2, (h1FourMerge1: ([merge], teal),), rounds: (0,)))
  }
  #v(1fr)
  Without a rule for long blocks, both borders wait forever. In blocks of four or more, the second and third robots move *outwards*: $dot X X X X dot -> dot X dot dot X dot$, again two nodes fewer.
  #v(10pt)
  #note[Rules `4-merge,1` and `4-merge,2` apply anywhere in the configuration.]
  #v(0.3fr)
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
#section-slide(4)

// The map as the paper left it, then the results of this week (search over
// every rule table, guided by a SAT solver; the proofs are under review).
#slide(title: [Open problems], id: "open")[
  #run(1, duration: 1.2)
  #v(1fr)
  #context {
    let u = ease(a("t"), 0, 1)
    grid(columns: (auto, 1fr), column-gutter: 46pt, align: horizon,
      results-map(focus: ((4, 0), (5, 0), (6, 0), (2, 1)), dim-others: true, cell: 86pt,
        updates: ((2, 1, "impossible"), (2, 0, "impossible"), (3, 0, "impossible")), update: u),
      if u < 0.5 {
        stack(spacing: 30pt,
          [#pill(color: amber)[1] #h(8pt) $phi = H$ for $H >= 4$ \ #note[impossible for $H in {2, 3}$, proved by hand]],
          [#pill(color: amber)[2] #h(8pt) $H = 2$ with $phi = 3$ \ #note[our algorithm needs $phi >= 4$]],
          [We believe *both are impossible* for oblivious robots.],
        )
      } else {
        stack(spacing: 30pt,
          [#pill(color: alert)[2] #h(8pt) $H = 2$, $phi = 3$: #em-alert[impossible] \ #note[so $phi >= 4$ is optimal for $H = 2$]],
          [#pill(color: alert)[+] #h(8pt) $phi = H <= 3$: #em-alert[no gathering] \ #note[even without crash, not only SUIG]],
          [#pill(color: amber)[1] #h(8pt) $phi = H$, $H >= 4$: #em-amber[open] \ #note[for SUIG, and for gathering]],
        )
      },
    )
    v(0.7fr)
    text(size: 22pt, fill: alpha(muted, u))[New this week: a SAT solver and a search for failing executions, with the help of AI. The proofs are under review.]
    v(0.3fr)
  }
]

#slide(title: [Open problem: $phi = H$, $H >= 4$], id: "open-h4")[
  #grid(columns: (1.25fr, 1fr), column-gutter: 26pt,
    card(fill: amber-soft, inset: 22pt, height: 150pt)[
      #eyebrow(color: amber)[Two questions in one]
      #v(10pt)
      #text(size: 24pt)[Can oblivious robots *gather* with $phi = H$? If not, no SUIG either: a SUIG algorithm gathers when nothing crashes.]
    ],
    card(inset: 22pt, height: 150pt)[
      #eyebrow(color: amber)[Conjecture]
      #v(10pt)
      #text(size: 24pt)[For every $H >= 2$, $phi = H$ is not enough, *even to gather*.]
    ],
  )
  #v(1fr)
  #align(center, line-view((0, 4, 8, 12, 16, 20), low: -1, high: 21, width: 1060, height: 110,
    views: ((8, 4),), tags: ((8, [me], teal), (4, [border?], amber), (12, [border?], amber))))
  #v(1fr)
  #grid(columns: (1fr, 1fr, 1fr), column-gutter: 20pt,
    ..(
      ([Memory is placement],
        [Oblivious robots pass nothing to the next round but their positions. Yet something must pass, like the parity of the occupied nodes: an even count can turn edge-symmetric.]),
      ([No slack],
        [Across a gap of $H$, a robot sees its neighbor at the edge of its view and nothing beyond: is it a border? Stepping away disconnects.]),
      ([Two blind borders],
        [Both ends must keep the count odd together, yet neither sees what the other did, and the middle cannot relay it without disconnecting.]),
    ).map(((head, body)) => card(inset: 18pt, height: 205pt)[
      #eyebrow(color: amber, size: 15pt)[#head]
      #v(8pt)
      #text(size: 20pt, body)
    ])
  )
]

// A sketch, not a proof: steps 1 to 3 hold for any phi >= H, so the missing
// lemma is where phi = H must be used.
#slide(title: [A plan for $phi = H$], id: "plan")[
  #set text(size: 23pt)
  #grid(columns: (48pt, 1fr), row-gutter: 18pt, align: (center + top, left + top),
    pill[1], [*Gathering suffices.* If gathering is impossible, so is SUIG.],
    pill[2], [*Frozen middle.* With every gap equal to $H$, an inner robot has a symmetric view: if it moved, the adversary would send two neighbors apart, to distance $H + 2$. So the middle waits, and the two ends evolve independently.],
    pill[3], [*Gluing.* If two ends $P$ and $Q$ of opposite parity reach the same state, start from $P thin C^k thin overline(Q)$, an odd count: the ends meet as mirror images around the frozen middle, edge-symmetric.],
  )
  #v(1fr)
  #card(fill: amber-soft, inset: 20pt)[
    #eyebrow(color: amber)[The missing lemma]
    #v(8pt)
    Periodic ends are not enough: one bit of state can hold the parity. Steps 1 to 3 also hold for $phi = H + 1$, where our algorithm keeps the parity by merging in pairs. So the lemma must use $phi = H$: *two ends of opposite parity reach the same state.*
  ]
  #v(12pt)
  #note[$C^k$: $k$ gaps of $H$, with an odd gap in the middle ($H - 1$ if $H$ is even); $overline(Q)$: $Q$ mirrored. With $phi = H$, the first robot of the chain cannot step towards the end, and the end cannot see past it.]
]

// ============================================================ closing ======
#slide(title: [Conclusion], section: none)[
  #stack(spacing: 30pt,
    grid(columns: (64pt, 1fr), text(fill: accent, weight: "bold", size: 34pt)[1],
      [A paper's assumptions are the *arguments of one definition*; the same `.sim` file is simulated, explored and exported to Lean.]),
    grid(columns: (64pt, 1fr), text(fill: teal, weight: "bold", size: 34pt)[2],
      [Myopic oblivious robots gather with $phi = max(4, H + 1)$ when $O_"init"$ is odd. Blind $3 -> 1$ merges break the parity; *three small rules* repair them.]),
    grid(columns: (64pt, 1fr), text(fill: amber, weight: "bold", size: 34pt)[3],
      [New, under review: $H = 2$ needs $phi >= 4$, and $phi = H in {2, 3}$ rules out gathering itself. Open: $phi = H$ for $H >= 4$.]),
  )
  #v(1fr)
  #grid(columns: (1fr, 1.2fr), column-gutter: 40pt,
    note[#link("https://bramas.github.io/simulant/standup-gathering/")[bramas.github.io/simulant/standup-gathering] \ the algorithms, in the browser],
    note[Q. Bramas, H. Kakugawa, S. Kamei, A. Lamani, F. Ooshita, M. Shibata, S. Tixeuil. _A Visibility vs. Memory Trade-Off for Stand-Up Indulgent Gathering on Lines._ SIROCCO 2025.],
  )
]

#closing-slide(
  title: [Thank you],
  subtitle: [Questions?],
  picture: line-view((8, 8, 8, 8, 8, 8, 8), low: 3, high: 13, width: 760),
)
