# Speaker notes — 20-minute conference version

Audience: researchers in mobile robots and mobile agents. Language: English.
There are 27 main slides and five optional backups. Plan for **18:45 of content,
including a 90-second simulator demo**, leaving 1:15 for transitions, a question
or a slow demo. Do not present the backup slides by default.

This version keeps the 20-minute slot with a broader model introduction and a
faster algorithm section. Slides 2–10 are a guided overview, not a line-by-line
code tutorial. Reach the live demo at 7:00 and finish it at 8:30. The two main
algorithm mechanisms retain about a minute each; the long execution traces are
30-second illustrations. Detailed qualifications below are rehearsal material,
not extra spoken paragraphs.

The source labels below identify the logical slides and animation segments.
Touying numbers the exported logical slides. Right/Page Down runs to the next
Touying pause or Glissade cut;
O opens the overview. The long traces have a few grouped reveal points rather
than one click per round. The deliberately incorrect border-only algorithm
loops at the end: press Right once to leave its loop.

## 1. title — 0:15 (0:15)

“Today I will use stand-up indulgent gathering to make two points: local
visibility changes the algorithmic problem, and making the model executable
helps us compare, explain and eventually prove algorithms.”

Credit all seven coauthors. Do not imply that this conference version introduces
new research results. The public reference is the SIROCCO 2025 paper; the
numbered algorithms used here are the versions in the later local manuscript
and its public Simulant translation.

## 2. simulant-intro — 0:25 (0:40)

Start with the authoring idea, before naming any robot taxonomy. In `.sim`,
the model declares the world and permitted capabilities, the algorithm uses
those capabilities, and the experiment connects them to a task and initial
conditions. The same description supports the interactive simulation, finite
exploration and generated Lean definitions. Do not read every table cell.

The reveal separates the workflow from its proof status: simulation is an
execution; finite exploration covers the specified explored graph; generated
Lean definitions and obligations still need proofs.

## 3. model-composition — 0:35 (1:15)

Read the ring model vertically as a list of assumptions: finite cycle,
full graph observation, disoriented frames, Boolean occupancy, SSYNC. The
`obliviousRobots` family supplies no private algorithm memory and one-edge moves.
The example is original and lives in `models.sim`, rather than being attributed
to a particular paper algorithm.

Keep the distinction between physical state and observations. A component can
store information without making it readable by an algorithm. The model does
not select a task or an algorithm.

## 4. model-choices — 0:35 (1:50)

Show the infinite line definition. Integer vertices are semantic positions;
the algorithm receives local locations, not those physical coordinates.
Cycles, stars and dynamic graphs change the space. On a line or a ring,
`Frames.identity` keeps the given ports, while `Frames.isomorphisms` allows
admissible local symmetries at every Look, removing common left/right agreement.

The classical literature also studies point robots in the Euclidean plane.
The standard `.sim` interpreter currently executes graphs. Its planar interface
does not implement continuous geometry, coordinate similarities or non-rigid
motion. Do not describe a ring instance of a capability model as an execution
of the original planar paper.

## 5. sensors — 0:40 (2:30)

Use the two sensor definitions to distinguish “someone is there” from
“there are exactly k robots there”. Visibility determines which locations can
be inspected; sensors determine which facts can be learned. `Observe.full`
means the full finite space; do not apply it to the infinite line.

`localMultiplicity` returns a capped count at the observer's node, distinguishing
one from at least two there; elsewhere it reports only occupancy. It returns
zero on empty locations. The display can show IDs, counts and crash crosses
without granting those observations to the robots.

## 6. robot-taxonomy — 0:40 (3:10)

Introduce the four familiar capability classes without discussing their
computational-power hierarchy. OBLOT is oblivious and silent. FSTA keeps a
finite private state. FCOM has a persistent external light that the owner cannot
read. LUMI can read its own and others' finite lights. Lights are updated at
Compute and persist between cycles.

The source is Flocchini, Santoro and Wada, OPODIS 2019, §2. That paper's model
is planar; here the table explains the capability taxonomy and the next slide
instantiates those capabilities on graphs. Scheduler, geometry, visibility,
multiplicity and orientation remain separate assumptions. Do not infer that a
theorem transfers between those settings.

## 7. light-capabilities — 0:50 (4:00)

The important point is storage plus access, not four special engine modes.
All examples use the oblivious algorithm family. A two-color component keeps
state; the sensor list controls who can read it. For the four robot constructions,
leave the algorithm's `Pub` and `Mem` at `Unit`: the light is the only persistent
state. The oblivious memory policy rejects private `Mem` but does not itself
prohibit additional public algorithm state. `agentsWithMemory` is not the
FSTA encoding: its general program counter and local values are not a fixed
finite light palette.

The original `otherColors` sensor excludes only the observing robot. Other
robots co-located with it must remain visible. Do not reuse `colors` unchanged
for FCOM: that would expose the owner's own light. `ownLight` is absent from
FCOM and present in FSTA and LUMI. The color-set sensors expose no exact
multiplicity. All four compositions are provided in `models.sim`; two colors
are an illustrative palette, not a universal bound for every algorithm.

## 8. schedulers — 0:40 (4:40)

Point to whole cycles versus separate events. FSYNC activates all eligible
robots each round. SSYNC chooses a nonempty subset for an atomic cycle.
ASYNC separates Look, Compute and Move, so a robot may move using an older view.
SSYNC and ASYNC admit activation-fair executions; a permanently crashed robot
is no longer required to act.

The default asynchronous event partition is `[[.look], [.compute], [.move]]`.
LC-atomic and CM-atomic variants can be expressed by grouping adjacent events.
Graph Move remains an instantaneous edge traversal; this is not continuous
planar movement observed in transit. No computational-power equivalence with a
planar ASYNC variant is asserted. Sources: OPODIS 2019 §2.3, OPODIS 2023 §2,
and Simulant `schedulers.sim`.

## 9. assumption-layers — 0:35 (5:15)

Use this as a comparison checklist rather than a syntax lecture. Different
hypotheses belong to the space, frame, memory policy, components, sensors and
experiment's domain. An unknown space size means no `spaceSize` sensor; the
analyst may still select a concrete size to run or check.

The parameter examples show different domain forms: `in` enumerates a finite
set; `where` states a predicate and need not make the domain finite. These are
not default values or sensors. The SUIG-specific gap and parity constraints
come later. Simulator warnings are advisory, so an execution outside the domain
does not refute a theorem inside it. The main literature also varies opacity,
collision tolerance, handedness, shared scale and rigid/non-rigid movement;
those require explicit semantics rather than being inferred from graph ports.

## 10. mobile-agents — 0:35 (5:50)

Give a second research tradition: persistent mobile agents searching for a
black hole on a ring. The predefined `blackHoleSearch` family fixes persistent
memory, oriented ports, a radius-1 neighborhood, co-located public-state
communication and a destructive hazard. `.unknown` omits the space-size sensor.

The second definition changes only the space to a ring where up to one edge
can be missing per round. It illustrates reusable model composition; it is not
a claim that the same algorithm solves black-hole search on both spaces.
The algorithm, task and admissible initial states remain separate declarations.

## 11. simulant-syntax — 0:30 (6:20)

Read `lineModel` as a composition of explicit assumptions: graph, radius view,
local frames, occupancy and fixed-node crashes. The first pause reveals the
capabilities and the defaults from the `obliviousRobots` family: no persistent
memory, moves along edges and FSYNC. The sensor list is a capability boundary;
crash status and physical coordinates are not available to the algorithm.

The second pause recalls `agentsWithMemory`: it changes the memory discipline
to `.persistent` while retaining explicit arguments for space, observation,
faults and scheduling. This recalls the introductory comparison; do not repeat the taxonomy.

## 12. formal-components — 0:40 (7:00)

Use one sentence per point: the component fixes one crash site, a permanent
visible body and the lost ability to move. The detailed qualifications below
are for rehearsal and questions.

Use the `.sim` crash component as a concrete formal-verification example.
The line, radius view, FSYNC scheduler and crash component have reusable semantic
definitions. A small component gives a smaller, explicit object to check and a
place to attach lemmas. Its state ownership and hook behavior make the
composition visible.

Concrete example: the fixed-node crash component owns one crash position;
robots can acquire a permanent crashed flag only there, remain present and stop
acting. This supports reusable statements about immobility, visibility and the
single crash location. An algorithm proof can use these facts without
redefining what a crash means. The first pause reveals two mathematical
properties: a crashed robot cannot move, and crashed robots share their location.
The second pause introduces the generated proof obligations. The displayed
code omits the viewer’s choice labels, which do not change the semantics.

Distinguish three claims:

- A finite explorer checks all admissible branches of an explored state graph.
- Lean generation translates the semantic definitions and emits `Statement`
  and `NonVacuity` obligations. Compilation checks the generated definitions.
- A general correctness theorem still needs an actual proof, as does the desired
  relationship between frontend/interpreter behavior and Lean semantics.

Do not say every component is already verified, or that composing components
proves gathering automatically. The existing library has selected invariants,
proof checks and bounded conformance/differential tests; the unbounded theorem
for these two SUIG algorithms is not claimed here.

## 13. simulator-demo — 1:30 (8:30)

Use the [90-second rehearsal script](demo.md). Have the correct page and preset
open before starting. Do not install anything, compile the site, edit long code
or run a large exhaustive check on stage. If anything takes more than ten
seconds, use the recorded animation on the slide and continue.

End with: “The same declarations drive the execution, the explanation, the
finite checks and the generated formal model. Now let us use this to examine
the two oblivious algorithms.”

## 14. line-model — 0:30 (9:00)

The occupancy-sequence formula is visible first. Reveal the local-view drawing
with one pause, then the symmetry and activation assumptions with another.
The line is infinite; robots move one edge or stay.
FSYNC means atomic synchronous rounds for the analysis here. Robots observe a
radius-phi occupancy sequence up to reflection. They have no multiplicity
sensor, no private memory, no lights, no IDs and no global orientation. They do
not know the population or the initial global parameters.

The shaded view is a model illustration with phi = 3, not an input advertised
as satisfying either algorithm's visibility bound. The global coordinates and
annotation colors are presentation devices.

## 15. suig-goal — 0:30 (9:30)

The `.sim` task states co-location of present robots. Its eventual goal is
combined with closure of the gathered configurations to obtain stable gathering.
Advance the paired examples. Without crashes the destination is not known in
advance. If crashes occur, all of them occur at the same node and correct robots
must join that node, including the crashed robots in the gathered configuration.
More than one robot may crash, at different rounds, but only at that location.
The robot does not know where that location is and cannot detect a crash.

The animation's crosses and multiplicity badges are for the audience only.
The recorded final configurations are also checked to be closed under all next
moves, so the examples illustrate stable gathering, not just a fleeting meeting.

## 16. parameters — 0:30 (10:00)

Emphasize the distinction between number of robots and number of occupied
nodes. This configuration has five robots but only four occupied nodes.
H_init is an **edge distance**, not the number of empty vertices in a gap.
M_init includes both hull borders; D_0 = M_init - 1. The example has H = 3,
O = 4 and M = 9, so it belongs to Algorithm 1's larger domain.

The robots are not supplied with H, O or M. These constrain the initial
configuration and the common visibility radius in the theorem.

## 17. naive-trap — 0:45 (10:45)

This is intentionally not a paper-algorithm execution. Grant the naive strategy
knowledge of the *true* borders: it still fails. Initially occupied nodes are
0, 2, 5, 12, 17. Moving only the extremes eventually merges them into the
interior nodes one at a time, leaving two occupied nodes. They approach and
reach adjacent nodes 8 and 9. Every synchronous round swaps the two populations.
Their occupied-node view is unchanged, since they cannot detect multiplicity.

The last reveal loops the swap. Exit with Right. The point is not simply
“move inward”: contractions must avoid creating a bad symmetry.

## 18. results — 0:25 (11:10)

Algorithm 1: phi >= max(4, H_init + 3), with O_init odd **or** M_init odd,
without knowing which. Algorithm 2: phi >= max(4, H_init + 1), with O_init odd.
Both are oblivious. Do not compare the visibility budgets without also stating
their different initial domains.

Do not claim Algorithm 2 is visibility-optimal for every H. The local manuscript
states tightness at H_init = 3; other parameter regimes require more qualified
statements. The two-color algorithm is outside today's scope.

## 19. h3-mechanisms — 1:10 (12:20)

First reveal: the left three-node structure 0,1,2 moves as a convoy while the
other border moves inward. All five occupied nodes remain distinct.
Second reveal: the triple at 1,2,3 merges at 2, removing two occupied nodes.
Last reveal: reshaping and a final merge gather at 4.

Use this as the core idea, not a complete listing of Algorithm 1. There are
priority rules for waiting, symmetric short configurations and small visibility.
The H+3 margin supports the border inferences used by nearby robots. Do not say
that every neighbor can always identify every true border: the small-view
exceptions are precisely part of the complete algorithm.

## 20. h3-execution — 0:30 (12:50)

Show the grouped reveal points without narrating every round. In 30 seconds,
point to contraction, two-at-a-time merges and the final node.


Use the grouped cuts at rounds 3,7,10,13. The initial positions are the manuscript
example, with H_init = 4, phi = 7 and eleven occupied nodes. Point to the
contraction, then the count changes 11,9,7,5,3,1. All eleven robots end at 17.

The trace comes from the actual engine with an empty crash choice at every
round. No algorithm is reimplemented in Typst; Typst only interpolates its
recorded positions between synchronous endpoints.

## 21. crash-rescue — 0:35 (13:25)

Four physical robots start on occupied nodes 0,1,2, with two robots at 0.
At the first round exactly one robot at 0 crashes; the other one can still move.
O drops from 3 to 2. At the next round the correct robots move to 0.

This invalidates any proof that relies only on preserving odd occupancy.
A stopped border supplies an immobile endpoint, but robots never acquire a
crash detector. If asked about an interior crash, the data also include
`h3-interior-crash` from 0,3,6, crashing at 3 in round 2.

## 22. h1-strategy — 0:30 (13:55)

The lower margin means less certainty about a robot at distance two or three
being a true border. Preserve the useful convoy/merge mechanisms, but add:
waiting borders, a different reduction for four-node blocks, and compensation
when a robot falsely believes it is adjacent to a border structure.

The radius-five view centered at 9 misses the robot at 3. This is the precise
local ambiguity to explain in slide 24, not an arbitrary adversarial trick.

## 23. h1-four-block — 1:10 (15:05)

Initially occupied: 0,1,2,3,7. The border at 0 waits by `border-idle,2`.
The inner robots at 1 and 2 move outwards to 0 and 3. The occupied four-block
becomes a two-block structure: globally the count drops from 5 to 3.
The rightmost robot also moves from 7 to 6. Keep that simultaneous move visible.

Advance the next reveal: the left border is now allowed to move. This is a
priority-rule story. Applying the generic border motion first would give a
different transition. The rest of the run gathers at 3.

## 24. h1-false-border — 1:20 (16:25)

Both columns describe the same **initial** configuration. The only animation on
this slide changes the highlighted viewpoint; the arrows show the two local
decisions. Full simultaneous motion appears on the next slide.

At 9, the window is [4,14]. It sees 7,8,9 but not 3, so it applies
`2neig, merge` and moves 9 -> 8.
At 8, the window is [3,13]. It sees the extra robot at 3, at the very edge of
its view. Its `neig, false-merge` guard detects the false-border situation and
moves 8 -> 9. The robots swap places instead of merging. There is no memory,
communication or special signal in that correction: the extra local observation
is sufficient. The occupied count stays nine.

## 25. h1-execution — 0:30 (16:55)

Show one transition and the endpoint in 30 seconds; keep the manuscript
discrepancy and terminal-parity details for a question.


Eight rounds from 3,7,8,9,11,12,14,15,17 at phi = 5. Reveal points:
rounds 1,4,6,8. At round 4, the occupied coordinates are 6,9,11,12,13.
The engine follows `border-idle,2` and `4-merge,1` here. An existing figure in the
local manuscript instead moves coordinate 6 to 7. The simulator's known-issues
file explicitly records that discrepancy; do not silently reproduce the figure.

Near the end the occupancy counts are 3 -> 2 -> 1 while D is 3 -> 2 -> 0.
Present the small endgame separately from the bulk parity argument.

## 26. proof-structure — 1:10 (18:05)

The proof architecture has two levels: establish local inferences and progress
under suitable gap/parity conditions, then discharge small terminal cases.
With crashes, parity may be lost and partial crashes matter. Gathering also
needs closure: once all robots meet, they must remain together.

Reconnect to Simulant. Reusable crash and observation definitions isolate model
semantics; the algorithm-specific invariant and endgame reasoning remain the
researcher's work. Finite exploration can find mistakes and validate examples;
it is not an unbounded theorem. A generated Lean statement is a starting point
for a formal proof, not a certification badge.

## 27. takeaways — 0:40 (18:45)

Restate the two initial domains and visibility bounds, then connect back to
the opening: explicit spaces, observations, sensors, state and scheduling make
comparisons inspectable. Simulant separates the model, algorithm and task.
Invite questions.

The nominal timings total 18:45 including the 90-second demo. Reserve 1:15 for
transitions or a question. If behind schedule, summarize slides 20 and 25 at
their final states; retain the false-border explanation and partial-crash
qualification. Backups are for questions, not part of the timed route.

## Backups

- **B1, backup-odd-span:** 0,1,3,4 has O = 4 but M = 5; Algorithm 1 gathers
  at 2. Algorithm 2's initial domain does not cover it.
- **B2, backup-terminal:** Algorithm 2 from a five-node block at phi = 4 has
  occupied counts 5,3,3,2,1 and diameters 4,4,3,2,0. This concrete execution
  prevents overstating the parity invariant.
- **B3, backup-crash:** repeat the partial-crash story with Algorithm 2.
- **B4, references:** source attribution and precise formal-status statement.

- **B5, model-references:** the model taxonomy, scheduling references and pinned
  public Simulant source. The original graph compositions in `models.sim` are
  checked separately from the unchanged SUIG trace recordings.

## Sources for the expanded opening

- [Flocchini, Santoro & Wada, OPODIS 2019, §2](https://doi.org/10.4230/LIPIcs.OPODIS.2019.25):
  OBLOT/FSTA/FCOM/LUMI and the synchronous/asynchronous scheduling distinction.
- [Flocchini, Santoro, Sudo & Wada, OPODIS 2023, §2](https://doi.org/10.4230/LIPIcs.OPODIS.2023.28):
  asynchronous phase atomicity and explicit model assumptions.
- [Feletti, Mambretti, Mereghetti & Palano, SAND 2024](https://doi.org/10.4230/LIPIcs.SAND.2024.13):
  opacity and collision intolerance as additional model choices.
- [Pinned Simulant standard library](https://github.com/bramas/simulant/tree/bf63fcc2784a23bbf8e1d15ed811743f0a72fea2/packages/stdlib/sim)
  and [language reference](https://github.com/bramas/simulant/blob/bf63fcc2784a23bbf8e1d15ed811743f0a72fea2/docs/sim-language.md).
  Definitions, sensor contracts, parameter domains and scheduler events were
  checked at that revision. The [planar status](https://github.com/bramas/simulant/blob/bf63fcc2784a23bbf8e1d15ed811743f0a72fea2/docs/planar-robots.md)
  explains why the graph examples must not be advertised as planar executions.
