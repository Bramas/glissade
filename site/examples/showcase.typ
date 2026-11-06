#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 24)

#let blue = rgb("#2f5e9e")
#let teal = rgb("#246b61")

// A 3-4-5 right triangle with its side labels.
#let triangle = box(width: 120pt, height: 110pt)[
  #place(polygon(
    fill: rgb("#d8e9df"),
    stroke: 1.4pt + teal,
    (0pt, 0pt), (0pt, 90pt), (120pt, 90pt),
  ))
  #place(dy: 78pt, rect(width: 12pt, height: 12pt, stroke: .8pt + teal))
  #place(dx: -14pt, dy: 36pt, text(fill: blue, $a$))
  #place(dx: 56pt, dy: 93pt, text(fill: blue, $b$))
  #place(dx: 64pt, dy: 24pt, text(fill: blue, $c$))
]

#slide(id: "showcase", title: "Pythagoras", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Solve for the hypotenuse]
  #v(22pt)

  // `part(a^2)` keeps the exponent with its letter. A shared key lets the
  // `c` of `c^2` glide into the final `c`.
  #init(trace: 0%, eq: formula($part(a^2) part(+) part(b^2) part(=) part(c^2, key: "c")$))

  // 1. Draw the triangle, then trace its hypotenuse.
  #create(tri: triangle, duration: 1.2)
  #animate(trace: 100%, duration: .7)

  // 2. Rearrange the formula: matching parts glide to their new places.
  #animate(eq: formula($part(c^2, key: "c") part(=) part(a^2) part(+) part(b^2)$), duration: 1)
  #animate(eq: formula($part(c^2, key: "c") part(=) 3^2 part(+) 4^2$), duration: .9)
  #animate(eq: formula($part(c, key: "c/base") part(=) 5$), duration: .9)

  // 3. Hold the result while the trace fades, then loop.
  #animate(trace: 0%, duration: 1.6)
  #cut(loop: true)

  #grid(
    columns: (140pt, 1fr),
    align: horizon,
    pad(left: 18pt, top: 6pt, box(width: 120pt, height: 110pt)[
      #place(context glissade-morph("tri"))
      #context {
        let t = a("trace") / 100%
        place(line(start: (0pt, 0pt), end: (120pt * t, 90pt * t), stroke: 3pt + blue.transparentize(15%)))
      }
    ]),
    align(center, text(size: 22pt, context glissade-morph("eq"))),
  )
]
