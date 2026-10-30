#import "@preview/touying:0.7.3": pause, config-page, config-common, config-colors
#import "../../lib.typ": a
#import "theme.typ": *

#set text(font: "Libertinus Serif", size: 27pt, fill: black)
#set par(leading: 0.55em, spacing: 0.65em)
#set list(indent: 18pt, body-indent: 12pt, spacing: 10pt)
#set enum(indent: 20pt, body-indent: 12pt, spacing: 10pt)
#show raw: set text(font: "DejaVu Sans Mono", size: 19pt, fill: black)
#show link: set text(fill: blue)
#show: simple-theme.with(
  header: none,
  header-right: none,
  footer: [Quentin Bramas · Stand-Up Indulgent Gathering],
  subslide-preamble: none,
  config-page(
    width: 1280pt, height: 720pt,
    margin: (x: 64pt, top: 44pt, bottom: 52pt),
    fill: white,
  ),
  config-common(
    handout: handout, breakable: false,
    show-strong-with-alert: false,
    enable-frozen-states-and-counters: false,
  ),
  config-colors(neutral-light: black, primary: blue),
)

#talk-slide(1, "title", "Stand-Up Indulgent Gathering")[
  #v(16pt)
  #text(size: 34pt)[Myopic oblivious robots on a line]
  #v(18pt)
  #text(size: 28pt)[Quentin Bramas]
  #v(15pt)
  #small[Joint work with Hirotsugu Kakugawa, Sayaka Kamei, Anissa Lamani,\ Fukuhito Ooshita, Masahiro Shibata and Sébastien Tixeuil.]
  #v(25pt)
  #line-view((0, 3, 5, 8, 11), low: -1, high: 12, crashed: (false, false, true, false, false), width: 1090)
]

#talk-slide(2, "model-choices", "Mobile entities: space and observations")[
  #grid(columns: (1.1fr, 1fr), gutter: 50pt,
    [
```lean
def Graphs.Line : Space where
  Vertex := Int
  neighbors v := [v + 1, v - 1]
  automorphisms :=
    .translationsAndReflection
```
    ],
    [
      $V = ZZ, quad E = { (i, i + 1) : i in ZZ }$.
      #v(12pt)
      A location is not a global coordinate available to the algorithm.
      #v(12pt)
      Views are considered up to the selected symmetries.
    ],
  )
  #pause
  #v(18pt)
```lean
sensor occupied (L : Look) (l : Loc) : Bool :=
  (L.occupants l).any present
```
  #v(10pt)
  $op("occupied")(l) equiv (exists r : p(r) = l)$.
  One robot and several robots at the same node produce the same observation.
]

#talk-slide(3, "simulant-syntax", "The oblivious robot model")[
```lean
def lineModel : Model :=
  obliviousRobots Graphs.Line
    (Observe.radius (param phi))
    Frames.isomorphisms [occupied]
    (components := [Faults.CrashAt])
```
  #pause
  #v(14pt)
  #grid(columns: (1fr, 1fr), gutter: 45pt,
    [
      *Capabilities*
      - Radius-$phi$ occupancy view.
      - No common left/right direction.
      - No multiplicity or crash-status sensor.
    ],
    [
      *Model-family defaults*
```lean
memory    := .oblivious
movement  := .alongEdges
scheduler := Schedulers.FSync
```
    ],
  )
  #pause
  #v(15pt)
  #small[`agentsWithMemory` changes the memory discipline to `.persistent`; the space, sensors, faults and scheduler remain explicit model arguments.]
]

#talk-slide(4, "formal-components", "Fault components and proof obligations")[
  #grid(columns: (1.45fr, 1fr), gutter: 32pt,
    [
      #text(size: 18pt)[
```lean
def Faults.CrashAt : Component where
  World := { crashNode : Pos }
  flags := [flag crashed visible, acts never]
  init := { crashNode := param crashNode }
  beforeMove C :=
    let S := choose (subsets
      (C.agents.filter fun a =>
        correct a ∧
        a.pos = C.world.crashNode))
    { raise crashed := S }
```
      ]
    ],
    [
      State and effects belong to a named component.
      #v(15pt)
      The same definition is used with different algorithms and schedulers.
      #v(15pt)
      The component fixes the crash location and the semantics of a crash.
    ],
  )
  #pause
  #v(14pt)
  *Component-level properties*, independent of the gathering algorithm:

  $ op("crashed")_(r)(t) => p_(r)(t + 1) = p_(r)(t) $

  $ op("crashed")_(r)(t) and op("crashed")_(s)(t) => p_(r)(t) = p_(s)(t) $

  #pause
  #v(10pt)
  #small[Lean export supplies semantic definitions, `Statement` and `NonVacuity`. Component lemmas can be reused; algorithm correctness is a separate proof obligation.]
]

#talk-slide(5, "simulator-demo", "Simulant: a short demonstration", animated: true)[
  #small[#link("https://bramas.github.io/simulant/standup-gathering/")[bramas.github.io/simulant/standup-gathering/]]
  #v(16pt)
  1. Load the left-border crash preset and step through the execution.
  2. Inspect a robot's local view and the rule it applies.
  3. Open the model definition and the generated Lean model.
  #v(18pt)
  #small[Recorded execution, if the live demo is unavailable:]
  #run(5, duration: 0.55, stops: (2, 5))
  #context trace-view("h1-border-crash", a("t"), width: 1090)
]

#talk-slide(6, "line-model", "Local views on the line")[
  At node $i$, a robot observes an occupancy sequence of length $2 phi + 1$:
  $cal(V)_i = (o_(i-phi), dots, [o_i], dots, o_(i+phi)), quad o_j in {0, 1}.$
  #pause
  #line-view((0, 3, 5, 8, 11), low: -1, high: 12, observer: 5, radius: 3, width: 1090)
  #small[Example: $phi = 3$. Nodes 0 and 11 are outside the observer's view.]
  #pause
  #v(16pt)
  - Views are equivalent up to reflection; robots do not share an orientation.
  - Each correct robot executes Look–Compute–Move in every round.
  - Moves are atomic: stay or traverse one edge. Robots have no persistent memory.
]

#talk-slide(7, "suig-goal", "Stand-up indulgent gathering", animated: true)[
  #text(size: 17pt)[
```lean
task Gathering (C : Config) : Verdict :=
  let robots := C.agents.filter present
  if robots.all fun a => robots.all fun b => a.pos = b.pos
  then .success else .inProgress
```
  ]
  #v(12pt)
  #run(4, duration: 0.8)
  #grid(columns: (1fr, 1fr), gutter: 40pt,
    [*No crash:* gather at an arbitrary node.\
      #context trace-view("h3-clean", a("t"), width: 505)],
    [*One crash location:* gather at that node.\
      #context trace-view("h3-border-crash", a("t"), width: 505)],
  )
  #v(13pt)
  #small[Crashes are permanent and undetectable. Gathering must be stable. Coordinates, multiplicities and crash marks in the figures are not robot observations.]
]

#talk-slide(8, "parameters", "Parameters of the initial configuration")[
  #line-view((0, 0, 2, 5, 8), low: -1, high: 9, highlight: (2, 5), width: 1090)
  #pause
  #v(15pt)
  #table(
    columns: (185pt, 1fr, 130pt), inset: (x: 12pt, y: 12pt), stroke: none,
    [$H_"init"$], [Maximum distance between consecutive occupied nodes.], [$3$],
    [$O_"init"$], [Number of occupied nodes; different from $n$.], [$4$],
    [$M_"init"$], [Number of nodes in the hull, including its borders.], [$9$],
  )
  #pause
  #v(14pt)
  $D_0 = M_"init" - 1.$ The robots do not know $H_"init"$, $O_"init"$, $M_"init"$ or $n$.
]

#talk-slide(9, "naive-trap", "A border-only strategy fails", animated: true)[
  Move only the two extreme occupied nodes towards the interior.
  #run(12, duration: 0.42, stops: (5, 10, 12), loop: true)
  #context {
    trace-view("naive-border", a("t"), width: 1090)
    v(16pt)
    if a("t") < 5 {
      remark[Initially $O_0 = 5$. One-sided merges can change its parity.]
    } else if a("t") < 10 {
      remark[Only two occupied nodes remain; they keep approaching.]
    } else {
      remark[At adjacent nodes, synchronous moves exchange the two populations.]
    }
  }
  #v(15pt)
  The occupied configuration is unchanged by the exchange.
  #v(12pt)
  #small[Edge crossings are not meetings: moves are atomic. This is the naive strategy, not either gathering algorithm.]
]

#talk-slide(10, "results", "Two oblivious gathering algorithms")[
  #table(
    columns: (155pt, 1.2fr, 1fr), inset: (x: 15pt, y: 22pt),
    stroke: (x: none, y: 0.5pt + black),
    table.header([*Algorithm*], [*Visibility*], [*Initial configurations*]),
    [1], [$phi >= max(4, H_"init" + 3)$], [$O_"init"$ odd or $M_"init"$ odd],
    [2], [$phi >= max(4, H_"init" + 1)$], [$O_"init"$ odd],
  )
  #pause
  #v(24pt)
  Both algorithms use the same oblivious FSYNC model and tolerate crashes at one location.
  #pause
  #v(15pt)
  Algorithm 2 reduces visibility by changing the local rules and restricting the initial domain.
]

#talk-slide(11, "h3-mechanisms", "Algorithm 1: border structures", animated: true)[
  #run(4, duration: 0.85, stops: (1, 2, 4))
  #context trace-view("h3-convoy", a("t"), width: 1090)
  #v(20pt)
  #context round-caption("h3-convoy", a("t"), (
    [A border and its two neighbors form a three-node structure.],
    [The three robots move together. Five occupied nodes remain.],
    [A controlled three-node merge changes the occupied count from $5$ to $3$.],
    [The remaining border structures contract.],
    [The final merge changes the occupied count from $3$ to $1$.],
  ))
  #v(20pt)
  The visibility margin supports border inferences. Rules for small symmetric configurations have higher priority.
]

#talk-slide(12, "h3-execution", "Algorithm 1: an execution", animated: true)[
  #run(13, duration: 0.5, stops: (3, 7, 10, 13))
  #context trace-view("h3-paper", a("t"), width: 1090)
  #v(20pt)
  #context {
    let s = state-at("h3-paper", a("t"))
    remark([Round #s.round: $O_t = #s.occupied$, $D_t = #s.diameter$.])
  }
  #v(14pt)
  - Border moves contract the occupied hull.
  - Controlled merges remove occupied nodes in pairs.
  - This fault-free execution gathers at node 17 in 13 rounds.
]

#talk-slide(13, "crash-rescue", "Partial crashes", animated: true)[
  #run(2, duration: 1.1)
  #context trace-view("h3-partial-crash", a("t"), width: 1090)
  #v(17pt)
  #context round-caption("h3-partial-crash", a("t"), (
    [Two robots are initially at node 0. One crashes; the other can still move.],
    [Only the crashed robot remains at 0. Occupancy changes from $3$ to $2$.],
    [All correct robots reach the crash node.],
  ))
  #v(20pt)
  The robots cannot distinguish a crashed robot from an idle one.
  #v(13pt)
  A correctness argument must cover lost parity and partial crashes.
]

#talk-slide(14, "h1-strategy", "Algorithm 2: reduced visibility")[
  For $phi >= max(4, H_"init" + 1)$, a robot may mistake an interior node for a border.
  #line-view((3, 7, 8, 9, 11, 12, 14, 15, 17), low: 2, high: 18, observer: 9, radius: 5, width: 1090)
  #small[At node 9, the robot cannot see node 3 and may treat node 7 as a border.]
  #pause
  #v(20pt)
  Three changes to Algorithm 1:
  - Waiting rules for border robots.
  - Different reductions of blocks of four or more occupied nodes.
  - Compensation for false-border merges.
]

#talk-slide(15, "h1-four-block", "Algorithm 2: four-node blocks", animated: true)[
  #run(4, duration: 0.9, stops: (1, 2, 4))
  #context trace-view("h1-four-block", a("t"), width: 1090)
  #v(17pt)
  #context round-caption("h1-four-block", a("t"), (
    [A four-node block is at the left border; another occupied node is at 7.],
    [The inner pair moves outwards. Globally, the occupied count changes from $5$ to $3$.],
    [The border can move again. Three occupied nodes remain.],
    [Contraction continues.],
    [Gathering at node 3.],
  ))
  #v(20pt)
  `border-idle` and `4-merge` take priority over the ordinary border rule.
]

#talk-slide(16, "h1-false-border", "Algorithm 2: false borders", animated: true)[
  #run(1, duration: 1.5)
  #context {
    let t = a("t")
    line-view(recordings.at("h1-paper").positions, low: 2, high: 18, observer: if t < 0.5 { 9 } else { 8 }, radius: 5, arrows: ((8, 9), (9, 8)), width: 1090)
  }
  #v(20pt)
  #grid(columns: (1fr, 1fr), gutter: 45pt,
    [*At node 9:* the window starts at 4. The robot misses node 3 and attempts a merge towards 8.],
    [*At node 8:* the robot sees node 3 at distance 5 and moves towards 9.],
  )
  #v(25pt)
  The robots exchange nodes. No merge occurs and $O_t = 9$ is preserved.
]

#talk-slide(17, "h1-execution", "Algorithm 2: an execution", animated: true)[
  #run(8, duration: 0.65, stops: (1, 4, 6, 8))
  #context trace-view("h1-paper", a("t"), width: 1090)
  #v(20pt)
  #context {
    let round = state-at("h1-paper", a("t")).round
    if round < 4 {
      remark[False-border compensation, contraction and block reductions.]
    } else if round < 6 {
      remark[At round 4, the occupied nodes are 6, 9, 11, 12, 13.]
    } else if round < 8 {
      remark[Terminal phase: $D = 3$. A subsequent configuration has even occupancy.]
    } else {
      remark[All nine robots gather at node 9 after eight rounds.]
    }
  }
  #v(18pt)
  #small[This execution follows the formal rules. The fourth successor differs from the manuscript's illustration.]
]

#talk-slide(18, "proof-structure", "Correctness arguments")[
  *Fault-free executions*
  1. Bound gaps and justify the local inferences.
  2. Control occupied parity during contraction.
  3. Establish progress and handle the terminal configurations.
  #pause
  #v(22pt)
  *Executions with crashes at one node*
  1. Crashed robots remain visible and immobile.
  2. Partial crashes may change occupied parity.
  3. Prove convergence to the crash location and closure of gathering.
  #pause
  #v(18pt)
  #small[Fault semantics and their lemmas belong to the reusable model; the progress and terminal-case arguments depend on the algorithm.]
]

#talk-slide(19, "takeaways", "Results and discussion")[
  #table(
    columns: (155pt, 1.2fr, 1fr), inset: (x: 15pt, y: 20pt),
    stroke: (x: none, y: 0.5pt + black),
    table.header([*Algorithm*], [*Visibility*], [*Initial configurations*]),
    [1], [$phi >= max(4, H_"init" + 3)$], [$O_"init"$ odd or $M_"init"$ odd],
    [2], [$phi >= max(4, H_"init" + 1)$], [$O_"init"$ odd],
  )
  #pause
  #v(22pt)
  The reduction in visibility requires different block reductions and false-border compensation.
  #pause
  #v(18pt)
  Simulant separates the model, algorithm and task. The same definitions support simulation, comparison and formal proof obligations.
  #v(20pt)
  #link("https://bramas.github.io/simulant/")[bramas.github.io/simulant/]
]

#talk-slide("B1", "backup-odd-span", "Even occupied count, odd inclusive span", animated: true)[
  #run(2, duration: 1.0)
  #context trace-view("h3-even-occupied", a("t"), width: 1090)
  #v(20pt)
  Initially $O_"init" = 4$ and $M_"init" = 5$. Algorithm 1 applies.
  #v(16pt)
  Algorithm 2's initial-domain assumption does not cover this configuration.
]

#talk-slide("B2", "backup-terminal", "Parity in the terminal configurations", animated: true)[
  #run(4, duration: 0.85)
  #context trace-view("h1-five-block", a("t"), width: 1090)
  #v(20pt)
  Occupied counts: $5 -> 3 -> 3 -> 2 -> 1$.
  #v(16pt)
  The even-occupancy configuration has diameter $D = 2$.
  #v(16pt)
  #small[Odd occupancy is not an invariant of every fault-free round of these implemented rules. The argument must distinguish contraction and endgames.]
]

#talk-slide("B3", "backup-crash", "Algorithm 2 with a partial crash", animated: true)[
  #run(2, duration: 1.0)
  #context trace-view("h1-partial-crash", a("t"), width: 1090)
  #v(20pt)
  A crash prevents one move; correct robots at the same node may still leave.
  #v(16pt)
  All crashes occur at one node, but may happen at different rounds.
]

#talk-slide("B4", "references", "References")[
  *Q. Bramas, H. Kakugawa, S. Kamei, A. Lamani, F. Ooshita, M. Shibata, S. Tixeuil.*

  _A Visibility vs. Memory Trade-Off for Stand-Up Indulgent Gathering on Lines._
  SIROCCO 2025, LNCS 15671, pp. 159–175.

  #link("https://doi.org/10.1007/978-3-031-91736-3_10")[doi:10.1007/978-3-031-91736-3_10]
  #v(18pt)
  Algorithm versions: the subsequent journal manuscript and its public Simulant translation.
  #v(18pt)
  #small[All algorithm traces are exported from the simulator. Finite checks and generated Lean models are not a machine-checked general SUIG theorem.]
]
