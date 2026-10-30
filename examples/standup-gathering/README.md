# Stand-Up Indulgent Gathering on Lines

A 20-minute English conference example for an audience working on mobile robots
and mobile agents. It uses a 16:9 layout, 19 main slides and four optional backup
slides, using Touying’s simple theme, native `pause` overlays and embedded Glissade
animations. The layout uses white paper, black serif text and unboxed definitions.

The talk introduces explicit computational models and Simulant, reserves 90
seconds for a live demo, explains why reusable model components help formal
verification, then focuses on the first two **oblivious** SUIG algorithms.
The two-color algorithm is intentionally outside its scope.

## Build and present

From the Glissade repository root:

```sh
# Animated, self-contained presentation. Typst and Python 3.10+ are required.
python3 bin/glissade.py --root . --timeout 300 \
  examples/standup-gathering/talk.typ html --fps 12 \
  --no-optimize-frames --title 'Stand-Up Indulgent Gathering'

# One static final state per slide, including the backups.
typst compile examples/standup-gathering/talk.typ \
  examples/standup-gathering/handout.pdf --root . \
  --input handout=true

# Optional live editor.
python3 bin/glissade.py --root . --timeout 300 \
  examples/standup-gathering/talk.typ dev --fps 12
```

Open `talk.html` directly in a modern browser. Right/Page Down runs to the next
speaker cut; Left goes back; O opens the overview; F toggles fullscreen.
The incorrect border-only strategy on slide 9 loops; Right exits its loop.
Intermediate robot positions are visual interpolation between atomic synchronous
moves. The `handout=true` mode keeps Touying’s last overlay, removes the animation
operations and retains one page per logical slide. Static explanations use
Touying `#pause`; continuous robot motion uses `glissade.touying`.

A full 12-fps build lays out several hundred Touying subslides; the timeout
allows for this. Use `--fps 2` for a faster draft while editing.

This content has many outlined text glyphs. `--no-optimize-frames` is deliberate:
gzip-compressed full SVG frames are smaller here than the current uncompressed
JSON delta representation. Generated HTML/PDF outputs follow the repository's
normal ignore rules; the sources and trace data are the reproducible example.

The diagrams use CeTZ 0.5.1. Typst downloads it on the first build if necessary;
the resulting presentation has no remote assets. Libertinus Serif and DejaVu Sans Mono
are the intended fonts. Other fonts may change line wrapping, so rebuild and
review the PDF after changing them.

## Files

- `talk.typ`: Touying slides, pauses and the named animation segments.
- `theme.typ`: Touying configuration, Glissade wrapper and line drawings.
- `traces.json`: recorded executions, chosen rules and public-source hashes.
- `export-traces.mjs`: reproducibly reads the external public Simulant project.
- `speaker-notes.md`: English narration, timing and technical qualifications.
- `demo.md`: the 90-second demo and offline alternative.

## Reproduce the traces

The example builds from its committed JSON without needing Simulant. To refresh
or check the recordings against the external checkout:

```sh
node examples/standup-gathering/export-traces.mjs /path/to/simulant
node examples/standup-gathering/export-traces.mjs /path/to/simulant --check
```

Use a prepared Simulant checkout with Node 24+, its workspace dependencies and
its `.sim` loader. The exporter reads only the public `projects/standup-gathering`
project. It does not read or copy private projects or modify the simulator.

It executes the actual engine with fixed physical tracks for drawing, chooses
the specified crash branch, records the invoked rule, checks one-edge moves,
checks the final gathering node and checks closure of the final configuration.
Source hashes identify the three public `.sim` files. Track IDs, coordinates,
multiplicity badges and crash marks are not observable by the robots.

The intentionally incorrect border-only counterexample is separately generated
and labelled. It is not attributed to either paper algorithm.

## Scientific scope

Algorithm numbering follows the local journal manuscript translated by the
public Simulant project:

| | Visibility | Initial condition |
| --- | --- | --- |
| Algorithm 1, oblivious | phi >= max(4, H_init + 3) | O_init odd or M_init odd |
| Algorithm 2, oblivious | phi >= max(4, H_init + 1) | O_init odd |

H_init is the maximum **edge distance** between consecutive occupied nodes;
O_init counts distinct occupied nodes; M_init counts hull nodes including both
borders. The robots do not know these parameters. Every crash is permanent and
occurs at one common node, but crashes can occur at different times. A crash
prevents that robot's movement; correct robots at the same node may still move.

Two distinctions matter when presenting these examples:

1. The Algorithm 2 figure's fourth successor differs from its formal rules.
   From initial coordinates `[3,7,8,9,11,12,14,15,17]`, phi = 5, the rules give
   occupied coordinates `[6,9,11,12,13]` at round 4. The simulator's documented
   known issue identifies this discrepancy; these animations follow the rules.
2. Do not claim odd occupied parity in every fault-free round of Algorithm 2.
   Its actual five-node-block run has counts `5,3,3,2,1`; its terminal even state
   has diameter 2. The main proof slide separates bulk arguments and endgames,
   and backup B2 makes this explicit. This observation qualifies the
   presentation's reasoning; it does not itself prove a universal bulk invariant.

The formal-verification message is about factoring semantics and reusing
component lemmas. Finite exploration, conformance tests and Lean generation are
useful, distinct tools. Neither the code examples nor these recordings claim a
machine-checked general correctness theorem for these two algorithms.

## References and attribution

Quentin Bramas, Hirotsugu Kakugawa, Sayaka Kamei, Anissa Lamani, Fukuhito Ooshita,
Masahiro Shibata, Sébastien Tixeuil. *A Visibility vs. Memory Trade-Off for Stand-Up
Indulgent Gathering on Lines.* SIROCCO 2025, LNCS 15671, pp. 159–175.
[Publisher / DOI](https://doi.org/10.1007/978-3-031-91736-3_10).
The detailed rules were checked against the author's later local journal
manuscript; no claim is made here about its publication status.

[Simulant](https://bramas.github.io/simulant/) and its
[public stand-up gathering artifact](https://bramas.github.io/simulant/standup-gathering/)
provide the executable source of the recordings. The `.sim` definition excerpts are
attributed to that public CeCILL-B project. Its sources are not vendored here;
this example adds original drawings, narration and execution data.
