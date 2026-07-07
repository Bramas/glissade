#import "../lib.typ": *
#import "@preview/cetz:0.5.1"
#import "@preview/theorion:0.6.0": *
#import cosmos.clouds: *
#show: show-theorion



#set page(width: 1024pt, height: 768pt, margin: 50pt)
#set text(size: 24pt)

// Ordinary definitions are shared by every slide.
#let accent = rgb("#2563eb")
#let slide-heading(title) = text(size: 36pt, weight: "bold", fill: accent, title)

// Apply the deck after global page/text configuration and shared definitions.
#show: deck.with(fps: 1)

#slide(
  id: "moving-line",
  title: "A global theorem counter",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[One document, isolated animations]

  #theorem(title: "Animated geometry")[
    The theorem number is frozen while Kino renders every frame of this slide.
  ]

  #init(x: 2.0)
  #animate(x: 10.0)

  #context {
    align(center, line(length: a("x") * 8mm, stroke: 3pt + accent))
  }
  #finish()
]

#slide(
  id: "shrinking-circle",
  title: "Shared definitions",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[Global code remains available]

  #theorem(title: "A second theorem")[
    This theorem follows the first one even though the previous slide contains
    multiple animation frames.
  ]

  #init(radius: 80%)
  #animate(radius: 0%)

  #context {
    align(center + horizon, circle(radius: 50pt * a("radius"), fill: accent))
  }
  #finish()
]






#slide(
  id: "shrinking-circle-2",
  title: "Shared definitions 2",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[Cetz animations]

  #theorem(title: "A third theorem")[
    Here is a Cetz animation.
  ]



  #init(n: 4.0)
  #animate(n: 10.0, duration:2)

  #context {
    cetz.canvas({
      import cetz.draw: *

      let n = float(a("n"))
      let n_i = calc.ceil(n)

      circle((0,0), radius: 110pt, stroke: 3pt + white)
      circle((0,0), radius: 100pt, stroke: 3pt + accent)

      content((130pt, 40pt), [$n = #n_i$], anchor: "west")

      for i in range(0, n_i) {
        let angle = 2 * 3.14 * i / n
        let x = 100pt * calc.cos(angle)
        let y = 100pt * calc.sin(angle)
        circle((x, y), radius: 10pt, fill: accent)
      }
    })
  }
  #finish()
]

#import "@preview/mannot:0.4.0": *

#slide(
  id: "matching-formula",
  title: "Matching formula parts",
)[
  #slide-heading[Formula parts move into place]

  #init(formula-state: $a = part(a, key: "a") = part(b, key: "b")$)
  #animate(formula-state: $b = part(a, key: "a") = part(b, key: "b") / (1+c)$)
 
  #context [
    #kino-morph(a("formula-state"), id: "main-formula")
  ]
  #finish()
]

#slide(
  id: "shape-morph",
  title: "Morph arbitrary shapes",
)[
  #slide-heading[Circle to square]

  #init(shape-state: [
    #cetz.canvas({
      import cetz.draw: *
      circle((0pt, 0pt), radius: 65pt, fill: blue)
    })
  ])
  #animate(shape-state: [
    #cetz.canvas({
      import cetz.draw: *
      rect((-65pt, -65pt), (65pt, 65pt), fill: red)
    })
  ])

  #context {
    align(center, kino-morph(a("shape-state"), id: "shape-morph"))
  }
  #finish()
]

#slide(
  id: "shape-create",
  title: "Draw shapes into view",
)[
  #slide-heading[Draw border then fill]

  #init(draw-state: [])
  #init(draw-state2: [])
  #animate(draw-state: [
    #cetz.canvas({
      import cetz.draw: *
      circle((0pt, 0pt), radius: 70pt, fill: green, stroke: 3pt + green.darken(70%))
    })
  ])
  #meanwhile(draw-state2: [
    #cetz.canvas({
      import cetz.draw: *
      content((0pt, 40pt), text(stroke:red.darken(70%), red)[*HELLO*],)
    })
  ])

  #context {
    align(center, kino-morph(a("draw-state"), id: "circle-create", effect: "draw-border-then-fill"))
    align(center, kino-morph(a("draw-state2"), id: "text-create", effect: "draw-border-then-fill"))
  }
  #finish()
]
