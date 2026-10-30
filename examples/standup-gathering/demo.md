# Simulant demo — 90 seconds

Open the [stand-up gathering page](https://bramas.github.io/simulant/standup-gathering/)
before the talk. The local alternative is the public project's development page:

```sh
# In the Simulant checkout, before going on stage:
pnpm --filter @bramas/simulant-project-standup-gathering dev
```

Use its printed URL. Keep the presentation and simulator in separate tabs.
No part of the presentation depends on a running server or an internet connection.

| Time | Action | What to say |
| --- | --- | --- |
| 0–15 s | Select `standup-gathering-h-plus-one`; load **Left-border crash · round 1**. | “The model, algorithm and initial parameters are explicit. This preset also records the adversary's choices.” |
| 15–40 s | Step through the first rounds, then to gathering. | “The left robot stops. Others cannot sense its crashed status, but eventually join its node.” |
| 40–60 s | Inspect one correct robot's Look and the enabled algorithm branch. | “The explanation uses exactly the permitted local occupancy view; the red cross belongs to the viewer, not to the sensor.” |
| 60–80 s | Open the model/source view and its Lean tab. | “The same line, view, scheduler and crash components are translated into a formal model. Their semantic facts can be established once and reused.” |
| 80–90 s | Return to the presentation. | “This exposes proof obligations; it does not replace the algorithm's correctness proof. Let us now look at its local mechanisms.” |

## Rehearsal checks

- Load the exact preset first. Round 0 is the initial state. It has five rounds
  to gathering at coordinate 0.
- Check the source/highlighting and Lean tabs on the installed simulator version.
  Do not wait for a Lean build during the presentation. Showing generated
  definitions does not assert a checked correctness theorem.
- If an interface item is hard to locate, show the `.sim` composition instead;
  do not spend the talk searching a menu.
- Optional extension, only if time permits: lower phi to 3 and show the
  assumption warning. Say that simulation outside the theorem's domain is not
  a counterexample to the stated theorem.
- Do not run `check-all` live. It is an exhaustive *finite* check and can take
  much longer than a recorded run.

## Offline fallback

Stay on slide 5. Its two reveal points replay the same crash scenario at rounds
2 and 5 from the exported engine trace. Then refer back to slides 3 and 4 for
source composition and Lean proof obligations. This takes the same 90 seconds
without any website.
