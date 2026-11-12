# Simulant and myopic stand-up indulgent gathering

A conference talk (16:9, about twenty minutes) built with Touying and Glissade.
It follows a talk that presents stand-up indulgent gathering (SUIG) in the usual
way, with the two-color algorithm and the oblivious $H + 3$ algorithm. This one:

1. introduces [Simulant](https://bramas.github.io/simulant/) and builds a model
   one assumption at a time: each row of the usual list (topology, visibility,
   orientation, sensors, memory, synchrony, faults) shows the
   standard library definitions it can be, and the chosen one becomes a
   `field := value` line. Three variants then change a few fields, and two
   library tasks (dispersion, exploration) show verdicts and goals;
2. writes the SUIG setting with myopic robots as the same seven fields, its
   task (the library's `Gathering`: crashed robots stay present), the
   experiment, whose parameter domains are the theorem's hypotheses and within
   which the adversary chooses, and the algorithm's only needs (the sensors it
   `uses`, no memory; the compiler checks them against the model);
3. presents the oblivious algorithm for $\varphi \ge \max(4, H_{init} + 1)$:
   why merging three occupied nodes into one is dangerous for myopic robots,
   and the three small rules that repair it, each shown *without* and *with*.
   After the second rule, one slide compares when borders wait: with
   $\varphi \ge H + 3$ only on the final configuration, which they see whole;
   with $\varphi = H + 1$ the wait is a local rule that also fires during the
   main stage, which changes the parity of the span (so $O_{init}$ must be odd).
   A slide before the third rule shows why the $H + 3$ border merge cannot
   be used in longer blocks with $\varphi = H + 1$: a false merge inside a
   block of four, which the first rule cannot catch (found by replaying the
   $H + 1$ table with that rule relaxed in the CEGIS checker); hence the border
   of a long block waits, and the block is split instead;
4. ends with the open problems: the map as the paper left it, then two
   results obtained since (with a SAT solver and a search for failing
   executions; proofs under review, mentioned in one line only): $H = 2$ with $\varphi = 3$ is impossible, and
   $\varphi = H$ rules out gathering itself, not only SUIG, for
   $H \in \{2, 3\}$. A second map then shows the wider class $O_{init}$ or
   $M_{init}$ odd: two colors are optimal ($\varphi \ge H$), oblivious robots
   need $\varphi \ge H + 3$ and everything below is open apart from the
   impossibilities inherited from $O_{init}$ odd. What remains is $\varphi = H$ for $H \ge 4$, for SUIG
   and for gathering: the intuition behind the conjecture, and a plan with its
   missing lemma. A last open problem is the general class of the journal
   version ($O_{init}$ or $M_{init}$ odd, the robots do not know which): two
   colors need $\varphi \ge H$, oblivious robots $\varphi \ge H + 3$.

The theme (`theme.typ`) is written from scratch on top of Touying: white page,
Lato with New Computer Modern math, short titles, the section name in the footer
corner, a thin progress line, and one meaning per color (blue robots, teal views
and moves, red crashes and failures, amber open questions). Section dividers
show the plan of the talk with the current part marked. `.sim` code is
highlighted with `sim.sublime-syntax` and `sim.tmTheme`.

The executions are the point of the talk, so they are drawn for the back of the
room: the line spans the slide, and everything is placed with plain Typst
shapes, which keeps a frame cheap to compile.

- A round starts and stops gently (`ease-in-out`), so rounds can be counted.
- The rule a robot applies is written under its node. The label fades in as the
  previous round ends, is readable at the stop, and stays on the node as the
  robot leaves.
- Two robots that exchange their order pass above and below the line instead of
  through each other, and a ring opens where robots merge.
- On the failing execution, the number of occupied nodes at each past round
  stays under the line, colored by parity.
- On slides with two executions, they play one after the other, never at the
  same time. A failing execution ends in a cycle of two rounds, which repeats
  (`cut(loop: 2)`) until you continue.

## Build

From the Glissade repository root:

```sh
# Animated, self-contained presentation (about half a minute).
python3 bin/glissade.py --root . --timeout 600 \
  examples/standup-gathering/talk.typ html --fps 24 \
  --title 'Simulant and myopic stand-up indulgent gathering'

# One static page per slide, with the final state of each animation.
typst compile --root . examples/standup-gathering/talk.typ \
  examples/standup-gathering/handout.pdf --input handout=true
```

Open `talk.html` in a browser. Right or Page Down continues to the next stop,
Left goes back, O opens the overview and F toggles fullscreen. The failing
executions loop on their last two rounds until you continue.

The deck needs Typst 0.14, Touying 0.7.3 and the Lato font. `--fps 12` halves
the export time and the number of frames; the motion is then visibly less
smooth.

## Files

- `talk.typ`: the slides.
- `theme.typ`: the Touying theme, the model builder, the drawings of robots on
  a line, the rule pictograms and the map of solved and open cases.
- `models.sim`: the five models shown on the slides, in `field := value` form.
  They compile against the public Simulant standard library.
- `traces.json`: the executions drawn in the talk, recorded by the simulator.
- `export-traces.mjs`: regenerates or checks `traces.json`.
- `sim.sublime-syntax`, `sim.tmTheme`: highlighting for `.sim` code.

## Reproduce the executions

Every animation is a recorded run of the public Simulant engine on the public
project `projects/standup-gathering`:

```sh
node examples/standup-gathering/export-traces.mjs /path/to/simulant
node examples/standup-gathering/export-traces.mjs /path/to/simulant --check
```

Use a Simulant checkout with Node 24 or later and its dependencies installed
(`pnpm install`). The traces were recorded from commit `bf63fcc`.

The “without” executions run a copy of `h-plus-one.sim` with exactly one rule
removed (`neig, false-merge`, `border-idle,1`, or both `4-merge` rules). The
copies are written to a temporary directory; the checkout is not modified. The
exporter fails unless each complete algorithm gathers (at the crash node when
there is a crash) and each variant enters a cycle.

| Execution | Initial nodes | $\varphi$ | Result |
| --- | --- | --- | --- |
| `false-border` | 0 4 8 9 10 12 15 | 5 | gathers in 12 rounds |
| `false-border-without` | same | 5 | ends on two adjacent nodes, forever |
| `border-wait` | 0 3 5 6 7 | 4 | gathers in 4 rounds |
| `border-wait-without` | same | 4 | ends on two adjacent nodes, forever |
| `long-block` | 0 2 3 4 5 | 4 | gathers in 4 rounds |
| `long-block-without` | same | 4 | the block never moves |

Coordinates, multiplicities, crash marks and rule labels in the drawings are
for the audience; robots observe only occupancy within radius $\varphi$.

## Scientific scope

- The algorithm, its rules and the theorem are those of the authors' journal
  version of *A Visibility vs. Memory Trade-Off for Stand-Up Indulgent
  Gathering on Lines* (SIROCCO 2025), as translated in the public Simulant
  project. The variants are deliberately incomplete and are labelled as such.
- In fault-free runs, merges remove occupied nodes in pairs while the
  configuration is large; the last rounds may have an even number of occupied
  nodes (for example `5 3 3 2 1`). The talk does not claim that parity is
  invariant in every round.
- The map of results is for oblivious robots with $O_{init}$ odd. The
  impossibility of $\varphi = H$ for SUIG is proved by hand for
  $H \in \{2, 3\}$. The newer results (no SUIG for $H = 2$, $\varphi = 3$; no
  gathering for $\varphi = H \in \{2, 3\}$) come from a computer search and
  are under review; the slides say so. $\varphi = H$ for $H \ge 4$ is a
  conjecture, and the plan on the last slide is a sketch whose key lemma is
  not proved.
- The standard library definitions on the option cards are excerpts: `…`
  marks omitted lines or parameters, and the display labels of `choose` are
  left out.
- Simulant's exploration follows every adversary choice up to a bound, and its
  Lean export gives definitions. Neither is presented as a machine-checked proof
  of the theorem.

## References and attribution

Quentin Bramas, Hirotsugu Kakugawa, Sayaka Kamei, Anissa Lamani, Fukuhito
Ooshita, Masahiro Shibata, Sébastien Tixeuil. *A Visibility vs. Memory
Trade-Off for Stand-Up Indulgent Gathering on Lines.* SIROCCO 2025, LNCS 15671,
pp. 159–175. [doi:10.1007/978-3-031-91736-3_10](https://doi.org/10.1007/978-3-031-91736-3_10)

The `.sim` excerpts on the slides come from the public Simulant project
([`bf63fcc`](https://github.com/bramas/simulant/tree/bf63fcc2784a23bbf8e1d15ed811743f0a72fea2)),
licensed CeCILL-B; its sources are not vendored here. `models.sim`, the
drawings and the execution data are original to this example.
