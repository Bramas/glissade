#import "@preview/touying:0.7.3": pause, config-page, config-common, config-colors
#import "../../lib.typ": a
#import "theme.typ": *

#set text(font: "Libertinus Serif", size: 27pt, fill: black)
#set par(leading: 0.5em, spacing: 0.65em)
#set list(indent: 18pt, body-indent: 12pt, spacing: 10pt)
#set enum(indent: 20pt, body-indent: 12pt, spacing: 10pt)
#show raw: set text(font: "DejaVu Sans Mono", size: 0.8em, fill: ink)
#show raw.where(block: true): set text(size: 19pt)
#show link: set text(fill: blue)
#show: simple-theme.with(
  header: none,
  header-right: none,
  footer: text(size: 16pt, fill: muted)[Quentin Bramas · Stand-Up Indulgent Gathering],
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
  config-colors(neutral-light: muted, primary: blue),
)

#talk-slide(1, "title", "Stand-Up Indulgent Gathering", opening: true)[
  #v(12pt)
  #text(size: 64pt, weight: "bold")[Stand-Up Indulgent\ Gathering]
  #v(12pt)
  #text(size: 32pt, fill: blue)[Myopic oblivious robots on a line]
  #v(24pt)
  #text(size: 28pt)[Quentin Bramas]
  #v(18pt)
  #small[Joint work with Hirotsugu Kakugawa, Sayaka Kamei, Anissa Lamani,\ Fukuhito Ooshita, Masahiro Shibata and Sébastien Tixeuil.]
  #v(30pt)
  #line-view((0, 3, 5, 8, 11), low: -1, high: 12, crashed: (false, false, true, false, false), width: 1090)
]

#talk-slide(2, "simulant-intro", "Simulant: make the model explicit")[
  Describe mobile entities and their permitted observations in `.sim`.
  #v(20pt)
  #table(
    columns: (210pt, 1fr), inset: (x: 14pt, y: 15pt),
    stroke: (x: none, y: 0.6pt + rule),
    [*Model*], [Space, observations, local frames, state, faults and scheduler.],
    [*Algorithm*], [Decisions using only the model's permitted sensors and actions.],
    [*Experiment*], [Model + algorithm + task + parameter domains + initial positions.],
  )
  #pause
  #v(25pt)
  #text(size: 31pt, fill: blue)[Define → simulate → explore → generate Lean]
  #v(18pt)
  #small[One explicit description connects execution and proof obligations. Finite exploration and generated definitions still need to be distinguished from a general theorem.]
]

#talk-slide(3, "model-composition", "A model is a composition of assumptions")[
  #grid(columns: (1.1fr, 1fr), gutter: 45pt,
    [
```lean
def ringRobots : Model :=
  obliviousRobots
    (Graphs.Cycle (param N))
    Observe.full
    Frames.isomorphisms
    [occupied]
    (scheduler := Schedulers.SSync)
```
    ],
    [
      *Space:* the cycle $C_N$.\
      *Observation:* the whole finite graph.\
      *Frames:* no common port orientation.\
      *Sensor:* occupied or empty.\
      *Scheduler:* semi-synchronous rounds.
    ],
  )
  #pause
  #v(24pt)
  The family `obliviousRobots` fixes no private memory and one-edge moves by default.
  #v(15pt)
  Components add lights, pebbles, faults or hazards. A model does not select the algorithm or the task.
  #v(18pt)
  #small[Original graph example: `models.sim`. Named families expose the assumptions; they do not make all papers use the same model.]
]

#talk-slide(4, "model-choices", "Space and local frames")[
  #grid(columns: (1.05fr, 1fr), gutter: 50pt,
    [
```lean
def Graphs.Line : Space where
  Vertex := Int
  neighbors v := [v + 1, v - 1]
  automorphisms :=
    .translationsAndReflection
```
      #v(12pt)
      #small[Integers name physical vertices. An algorithm receives local locations, not global coordinates.]
    ],
    [
      *Other graph spaces*\
      `Graphs.Cycle N`\
      `Graphs.Star k`\
      `Graphs.Dynamic base 1`
      #v(20pt)
      *Orientation on a line or ring*\
      `Frames.identity`: keep the ports.\
      `Frames.isomorphisms`: a fresh admissible local symmetry at each Look.
    ],
  )
  #pause
  #v(24pt)
  Geometry, topology and orientation are separate assumptions.
  #v(15pt)
  #small[The literature also studies Euclidean point robots. `Euclidean.Plane` is currently an interface, not an executable space in the standard `.sim` engine. Graph examples here do not implement planar geometry.]
]

#talk-slide(5, "sensors", "What can a robot actually observe?")[
```lean
sensor occupied (L : Look) (l : Loc) : Bool :=
  (L.occupants l).any present

sensor count (L : Look) (l : Loc) : Nat :=
  (L.occupants l).count present
```
  #v(16pt)
  #grid(columns: (1fr, 1fr), gutter: 50pt,
    [
      *Visibility selects the domain*\
      `Observe.full`: the whole finite space.\
      `Observe.radius r`: an $r$-hop view.
    ],
    [
      *Sensors select the information*\
      `occupied`: empty or occupied.\
      `count`: exact multiplicity.\
      `localMultiplicity`: 1 vs. ≥2 only here.
    ],
  )
  #pause
  #v(24pt)
  #text(fill: blue)[Seeing a location does not grant every fact about its occupants.]
  #v(15pt)
  #small[Only declared sensors are available to an algorithm. The viewer's IDs, crash crosses and multiplicity labels need not be observable.]
]

#talk-slide(6, "robot-taxonomy", "Four standard robot models")[
  #table(
    columns: (170pt, 1fr, 1fr, 1.1fr), inset: (x: 14pt, y: 20pt),
    stroke: (x: none, y: 0.6pt + rule),
    table.header([*Model*], [*Finite memory*], [*Visible finite state*], [*Readable light*]),
    [*OBLOT*], [No], [No], [None],
    [*FSTA*], [Yes], [No], [Own only],
    [*FCOM*], [No], [Yes], [Others only],
    [*LUMI*], [Yes], [Yes], [Own and others'],
  )
  #pause
  #v(23pt)
  A light has finitely many colors and persists between cycles. Its accessibility separates memory from communication.
  #v(18pt)
  #small[Capability taxonomy: Flocchini, Santoro & Wada, OPODIS 2019, §2. Scheduling, geometry, visibility and multiplicity are additional choices. The following Simulant examples instantiate these capabilities on a graph.]
]

#talk-slide(7, "light-capabilities", "Storage and access define the capability")[
  #small[All four examples use `obliviousRobots` on the same ring. Lights live in a component.]
  #v(12pt)
  #table(
    columns: (145pt, 1.45fr, 1fr), inset: (x: 14pt, y: 15pt),
    stroke: (x: none, y: 0.6pt + rule),
    table.header([*Model*], [*Sensor list*], [*Component list*]),
    [OBLOT], [`[occupied]`], [`[]`],
    [FSTA], [`[occupied, ownLight]`], [`[Storage.Lights 2]`],
    [FCOM], [`[occupied, otherColors]`], [`[Storage.Lights 2]`],
    [LUMI], [`[colors, ownLight]`], [`[Storage.Lights 2]`],
  )
  #pause
  #v(15pt)
  #small[`otherColors` is an original sensor defined in `models.sim`, not a built-in alias:]
```lean
sensor otherColors (L : Look) (l : Loc) : List Nat :=
  (range L.world.colorCount).filter fun c =>
    (L.occupants l).any fun a =>
      present a ∧ a ≠ L.me ∧ a.light = c
```
  #v(12pt)
  #small[The observer is excluded; other robots at its node are still visible. Two colors illustrate the construction, not every finite-state algorithm.]
]

#talk-slide(8, "schedulers", "When do Look, Compute and Move occur?")[
  #table(
    columns: (150pt, 1.15fr, 1.3fr), inset: (x: 14pt, y: 22pt),
    stroke: (x: none, y: 0.6pt + rule),
    table.header([*Literature*], [*Activation and timing*], [*Simulant scheduler*]),
    [*FSYNC*], [All eligible robots; whole LCM cycles.], [`Schedulers.FSync`],
    [*SSYNC*], [An adversarial nonempty subset; whole cycles.], [`Schedulers.SSync`],
    [*ASYNC*], [Separate Look, Compute and Move events; stale views.], [`Schedulers.Async`],
  )
  #pause
  #v(20pt)
  `Schedulers.Async` defaults to `[[.look], [.compute], [.move]]`.
  #v(15pt)
  SSYNC and ASYNC use activation fairness: every continuously acting agent gets infinitely many events.
  #v(15pt)
  #small[Standard graph movement remains an atomic edge move. Splitting LCM does not implement continuous motion or the non-rigid planar adversary. See OPODIS 2019, §2.3, and the Simulant scheduler definitions.]
]

#talk-slide(9, "assumption-layers", "Where do the other hypotheses belong?")[
  #table(
    columns: (215pt, 1.15fr, 1.4fr), inset: (x: 14pt, y: 15pt),
    stroke: (x: none, y: 0.6pt + rule),
    table.header([*Hypothesis*], [*Choice in the literature*], [*Simulant declaration*]),
    [Topology], [Static / changing edges], [`Graphs.Dynamic base 1`],
    [Orientation], [Agreement / disorientation], [`Frames.identity` / `isomorphisms`],
    [State], [Oblivious / persistent], [`obliviousRobots` / `agentsWithMemory`],
    [Faults], [Bounded crashes / one crash site], [`Faults.CrashStop f` / `CrashAt`],
    [Knowledge], [Space size known / unknown], [Include / omit `spaceSize`],
    [Initial domain], [Parity, size, visibility bounds], [Experiment parameters: `in`, `where`],
  )
  #pause
  #v(20pt)
```lean
param N : Nat in [5, 7, 9]
param phi : Nat where phi ≥ 4
```
  #v(12pt)
  #small[Domain constraints are not sensors. Persistent agent memory is more general than FSTA's fixed finite state. Opaque visibility, planar chirality and non-rigid motion need their own semantics; graph ports are not a substitute.]
]

#talk-slide(10, "mobile-agents", "Mobile agents: another familiar setting")[
  #grid(columns: (1.1fr, 1fr), gutter: 45pt,
    [
```lean
def ringAgents : Model :=
  blackHoleSearch
    (Graphs.Cycle (param N))
    .initiallyPresent .unknown
```
      #v(20pt)
```lean
def dynamicRingAgents : Model :=
  blackHoleSearch
    (Graphs.Dynamic
      (Graphs.Cycle (param N)) 1)
    .initiallyPresent .unknown
```
    ],
    [
      *The predefined family combines*
      - Persistent program state.
      - Agreed ring port orientation.
      - Radius-1 movement neighborhood.
      - Public states at the current node.
      - A destructive black-hole component.
      #v(12pt)
      `.unknown` omits the space-size sensor; it does not hide the experiment's parameters from the analyst.
    ],
  )
  #pause
  #v(18pt)
  #small[Changing the space reuses the family. The algorithm, task and initial conditions remain explicit; reuse does not transfer an algorithm's theorem to a dynamic ring.]
]

#talk-slide(11, "simulant-syntax", "The oblivious robot model")[
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

#talk-slide(12, "formal-components", "Fault components and proof obligations")[
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

#talk-slide(13, "simulator-demo", "Simulant: a short demonstration", animated: true)[
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

#talk-slide(14, "line-model", "Local views on the line")[
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

#talk-slide(15, "suig-goal", "Stand-up indulgent gathering", animated: true)[
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

#talk-slide(16, "parameters", "Parameters of the initial configuration")[
  #line-view((0, 0, 2, 5, 8), low: -1, high: 9, highlight: (2, 5), width: 1090)
  #pause
  #v(15pt)
  #table(
    columns: (155pt, 1fr, 100pt), inset: (x: 16pt, y: 16pt),
    stroke: (x: none, y: 0.6pt + rule),
    [$H_"init"$], [Maximum distance between consecutive occupied nodes.], [#text(fill: blue, weight: "bold")[3]],
    [$O_"init"$], [Number of occupied nodes; different from $n$.], [#text(fill: blue, weight: "bold")[4]],
    [$M_"init"$], [Number of nodes in the hull, including its borders.], [#text(fill: blue, weight: "bold")[9]],
  )
  #pause
  #v(14pt)
  $D_0 = M_"init" - 1.$ The robots do not know $H_"init"$, $O_"init"$, $M_"init"$ or $n$.
]

#talk-slide(17, "naive-trap", "A border-only strategy fails", animated: true)[
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

#talk-slide(18, "results", "Two oblivious gathering algorithms")[
  #results-table()
  #pause
  #v(24pt)
  Both algorithms use the same oblivious FSYNC model and tolerate crashes at one location.
  #pause
  #v(15pt)
  Algorithm 2 reduces visibility by changing the local rules and restricting the initial domain.
]

#talk-slide(19, "h3-mechanisms", "Algorithm 1: border structures", animated: true)[
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

#talk-slide(20, "h3-execution", "Algorithm 1: an execution", animated: true)[
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

#talk-slide(21, "crash-rescue", "Partial crashes", animated: true)[
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

#talk-slide(22, "h1-strategy", "Algorithm 2: reduced visibility")[
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

#talk-slide(23, "h1-four-block", "Algorithm 2: four-node blocks", animated: true)[
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

#talk-slide(24, "h1-false-border", "Algorithm 2: false borders", animated: true)[
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

#talk-slide(25, "h1-execution", "Algorithm 2: an execution", animated: true)[
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

#talk-slide(26, "proof-structure", "Correctness arguments")[
  #grid(columns: (1fr, 1fr), gutter: 60pt,
    [
      #text(fill: blue, weight: "bold")[Fault-free executions]
      #v(12pt)
      1. Bound gaps and justify the local inferences.
      2. Control occupied parity during contraction.
      3. Establish progress and handle the terminal configurations.
    ],
    [
      #pause
      #text(fill: blue, weight: "bold")[Executions with crashes at one node]
      #v(12pt)
      1. Crashed robots remain visible and immobile.
      2. Partial crashes may change occupied parity.
      3. Prove convergence to the crash location and closure of gathering.
    ],
  )
  #pause
  #v(30pt)
  #small[Fault semantics and their lemmas belong to the reusable model; the progress and terminal-case arguments depend on the algorithm.]
]

#talk-slide(27, "takeaways", "Results and discussion")[
  #results-table()
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

#talk-slide("B5", "model-references", "Model literature and executable sources")[
  *P. Flocchini, N. Santoro & K. Wada.*\
  _On Memory, Communication, and Synchronous Schedulers When Moving and Computing._ OPODIS 2019, §2.
  #small[#link("https://doi.org/10.4230/LIPIcs.OPODIS.2019.25")[doi:10.4230/LIPIcs.OPODIS.2019.25]]
  #v(17pt)
  *P. Flocchini, N. Santoro, Y. Sudo & K. Wada.*\
  _On Asynchrony, Memory, and Communication: Separations and Landscapes._ OPODIS 2023, §2.
  #small[#link("https://doi.org/10.4230/LIPIcs.OPODIS.2023.28")[doi:10.4230/LIPIcs.OPODIS.2023.28]]
  #v(17pt)
  *Simulant standard library and language reference.*\
  `families.sim`, `spaces.sim`, `sensors.sim`, `schedulers.sim`, `components.sim`, `predefined.sim`.
  #small[#link("https://github.com/bramas/simulant/tree/bf63fcc2784a23bbf8e1d15ed811743f0a72fea2/packages/stdlib/sim")[Pinned public source · bf63fcc] · Original compositions: `models.sim` in this example.]
]
