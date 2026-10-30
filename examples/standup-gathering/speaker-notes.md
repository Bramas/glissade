# Speaker notes — 20-minute conference version

Audience: researchers in mobile robots and mobile agents. Language: English.
There are 19 main slides and four optional backups. Plan for **18:45 of content,
including a 90-second simulator demo**, leaving 1:15 for transitions, a question
or a slow demo. Do not present the backup slides by default.

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

## 2. model-choices — 0:45 (1:00)

Start with the actual `.sim` definition of the infinite line. The integers are
semantic vertices; the algorithm receives local locations, not those global
coordinates. The automorphism declaration expresses translation and reflection.

Use the first Touying pause to reveal `occupied`. It is a Boolean existential
observation, close to its mathematical definition. Multiple robots at a node
still produce one positive observation. This sensor is the important distinction
from strong multiplicity detection.

## 3. simulant-syntax — 0:55 (1:55)

Read `lineModel` as a composition of explicit assumptions: graph, radius view,
local frames, occupancy and fixed-node crashes. The first pause reveals the
capabilities and the defaults from the `obliviousRobots` family: no persistent
memory, moves along edges and FSYNC. The sensor list is a capability boundary;
crash status and physical coordinates are not available to the algorithm.

The second pause introduces `agentsWithMemory`: it changes the memory discipline
to `.persistent` while retaining explicit arguments for space, observation,
faults and scheduling. Keep this short; the talk concerns the oblivious case.

## 4. formal-components — 1:15 (3:10)

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

## 5. simulator-demo — 1:30 (4:40)

Use the [90-second rehearsal script](demo.md). Have the correct page and preset
open before starting. Do not install anything, compile the site, edit long code
or run a large exhaustive check on stage. If anything takes more than ten
seconds, use the recorded animation on the slide and continue.

End with: “The same declarations drive the execution, the explanation, the
finite checks and the generated formal model. Now let us use this to examine
the two oblivious algorithms.”

## 6. line-model — 0:45 (5:25)

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

## 7. suig-goal — 0:45 (6:10)

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

## 8. parameters — 0:45 (6:55)

Emphasize the distinction between number of robots and number of occupied
nodes. This configuration has five robots but only four occupied nodes.
H_init is an **edge distance**, not the number of empty vertices in a gap.
M_init includes both hull borders; D_0 = M_init - 1. The example has H = 3,
O = 4 and M = 9, so it belongs to Algorithm 1's larger domain.

The robots are not supplied with H, O or M. These constrain the initial
configuration and the common visibility radius in the theorem.

## 9. naive-trap — 1:00 (7:55)

This is intentionally not a paper-algorithm execution. Grant the naive strategy
knowledge of the *true* borders: it still fails. Initially occupied nodes are
0, 2, 5, 12, 17. Moving only the extremes eventually merges them into the
interior nodes one at a time, leaving two occupied nodes. They approach and
reach adjacent nodes 8 and 9. Every synchronous round swaps the two populations.
Their occupied-node view is unchanged, since they cannot detect multiplicity.

The last reveal loops the swap. Exit with Right. The point is not simply
“move inward”: contractions must avoid creating a bad symmetry.

## 10. results — 0:35 (8:30)

Algorithm 1: phi >= max(4, H_init + 3), with O_init odd **or** M_init odd,
without knowing which. Algorithm 2: phi >= max(4, H_init + 1), with O_init odd.
Both are oblivious. Do not compare the visibility budgets without also stating
their different initial domains.

Do not claim Algorithm 2 is visibility-optimal for every H. The local manuscript
states tightness at H_init = 3; other parameter regimes require more qualified
statements. The two-color algorithm is outside today's scope.

## 11. h3-mechanisms — 1:30 (10:00)

First reveal: the left three-node structure 0,1,2 moves as a convoy while the
other border moves inward. All five occupied nodes remain distinct.
Second reveal: the triple at 1,2,3 merges at 2, removing two occupied nodes.
Last reveal: reshaping and a final merge gather at 4.

Use this as the core idea, not a complete listing of Algorithm 1. There are
priority rules for waiting, symmetric short configurations and small visibility.
The H+3 margin supports the border inferences used by nearby robots. Do not say
that every neighbor can always identify every true border: the small-view
exceptions are precisely part of the complete algorithm.

## 12. h3-execution — 0:55 (10:55)

Use the grouped cuts at rounds 3,7,10,13. The initial positions are the manuscript
example, with H_init = 4, phi = 7 and eleven occupied nodes. Point to the
contraction, then the count changes 11,9,7,5,3,1. All eleven robots end at 17.

The trace comes from the actual engine with an empty crash choice at every
round. No algorithm is reimplemented in Typst; Typst only interpolates its
recorded positions between synchronous endpoints.

## 13. crash-rescue — 0:50 (11:45)

Four physical robots start on occupied nodes 0,1,2, with two robots at 0.
At the first round exactly one robot at 0 crashes; the other one can still move.
O drops from 3 to 2. At the next round the correct robots move to 0.

This invalidates any proof that relies only on preserving odd occupancy.
A stopped border supplies an immobile endpoint, but robots never acquire a
crash detector. If asked about an interior crash, the data also include
`h3-interior-crash` from 0,3,6, crashing at 3 in round 2.

## 14. h1-strategy — 0:45 (12:30)

The lower margin means less certainty about a robot at distance two or three
being a true border. Preserve the useful convoy/merge mechanisms, but add:
waiting borders, a different reduction for four-node blocks, and compensation
when a robot falsely believes it is adjacent to a border structure.

The radius-five view centered at 9 misses the robot at 3. This is the precise
local ambiguity to explain in slide 16, not an arbitrary adversarial trick.

## 15. h1-four-block — 1:30 (14:00)

Initially occupied: 0,1,2,3,7. The border at 0 waits by `border-idle,2`.
The inner robots at 1 and 2 move outwards to 0 and 3. The occupied four-block
becomes a two-block structure: globally the count drops from 5 to 3.
The rightmost robot also moves from 7 to 6. Keep that simultaneous move visible.

Advance the next reveal: the left border is now allowed to move. This is a
priority-rule story. Applying the generic border motion first would give a
different transition. The rest of the run gathers at 3.

## 16. h1-false-border — 1:50 (15:50)

Both cards describe the same **initial** configuration. The only animation on
this slide changes the highlighted viewpoint; the arrows show the two local
decisions. Full simultaneous motion appears on the next slide.

At 9, the window is [4,14]. It sees 7,8,9 but not 3, so it applies
`2neig, merge` and moves 9 -> 8.
At 8, the window is [3,13]. It sees the extra robot at 3, at the very edge of
its view. Its `neig, false-merge` guard detects the false-border situation and
moves 8 -> 9. The robots swap places instead of merging. There is no memory,
communication or special signal in that correction: the extra local observation
is sufficient. The occupied count stays nine.

## 17. h1-execution — 0:55 (16:45)

Eight rounds from 3,7,8,9,11,12,14,15,17 at phi = 5. Reveal points:
rounds 1,4,6,8. At round 4, the occupied coordinates are 6,9,11,12,13.
The engine follows `border-idle,2` and `4-merge,1` here. An existing figure in the
local manuscript instead moves coordinate 6 to 7. The simulator's known-issues
file explicitly records that discrepancy; do not silently reproduce the figure.

Near the end the occupancy counts are 3 -> 2 -> 1 while D is 3 -> 2 -> 0.
Present the small endgame separately from the bulk parity argument.

## 18. proof-structure — 1:15 (18:00)

The proof architecture has two levels: establish local inferences and progress
under suitable gap/parity conditions, then discharge small terminal cases.
With crashes, parity may be lost and partial crashes matter. Gathering also
needs closure: once all robots meet, they must remain together.

Reconnect to Simulant. Reusable crash and observation definitions isolate model
semantics; the algorithm-specific invariant and endgame reasoning remain the
researcher's work. Finite exploration can find mistakes and validate examples;
it is not an unbounded theorem. A generated Lean statement is a starting point
for a formal proof, not a certification badge.

## 19. takeaways — 0:45 (18:45)

Restate the two domains and visibility bounds, then the three messages. Invite
questions. The nominal slide timings total 18:45, including the demo. Reserve
1:15 to slow the two main mechanisms, answer a question, or extend the demo;
do not use all the backup slides to fill that reserve.

## Backups

- **B1, backup-odd-span:** 0,1,3,4 has O = 4 but M = 5; Algorithm 1 gathers
  at 2. Algorithm 2's initial domain does not cover it.
- **B2, backup-terminal:** Algorithm 2 from a five-node block at phi = 4 has
  occupied counts 5,3,3,2,1 and diameters 4,4,3,2,0. This concrete execution
  prevents overstating the parity invariant.
- **B3, backup-crash:** repeat the partial-crash story with Algorithm 2.
- **B4, references:** source attribution and precise formal-status statement.
