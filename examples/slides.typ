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
  title: "A global theorem counter",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[Typst Slides]

  This is a standard typst document to show slides. You can use you favorite package, for instance theorion to create the following theorem:

  #theorem[
    This is a theorem. Its number stays the same during the animation.
  ]

]

#slide(
  title: "Shared definitions",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[You can animate variables]

  You can define variables and animate them. For instance:
  ```typst

  #init(x: 2.0)
  #animate(x: 10.0, duration: 2)
  #context {
    [
      value of x: #a("x")
    ]
    align(center, line(length: a("x") * 8mm, stroke: 3pt + accent))
  }
  #finish()
```

You can decide the number of frame per second this wil generate, by default it is 1 fps, with at least one frame at the begining and end of each slide (if different).

  #init(x: 2.0)
  #animate(x: 10.0, duration: 2)

  #context {
    [
      value of x: #a("x")
    ]
    align(center, line(length: a("x") * 8mm, stroke: 3pt + accent))
  }
  #finish()
]


#slide(
  title: "Cetz animations",
  frozen-counters: (theorem-counter,),
)[
  #slide-heading[Cetz animations]

Your variables can be used in any package, including ctez. For instance:

#text(15pt)[
```typst
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
```]

  #init(n: 4.0)
  #animate(n: 10.0, duration:2)

  #place(dx:500pt, dy: -300pt)[
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
  ]

  #finish()
]

#import "@preview/mannot:0.4.0": *

#slide(
  title: "Matching formula parts",
)[
  #slide-heading[Formula parts move into place]

  We can write formulas indicating where are specific parts of the formula. Then, the formula can be animated and the parts will move into place:

  ```typst
#create(f: $part(a) = o = part(a, key: "a_2") = part(b)$, duration: 2)
#animate(f: $1 / part(a) = o = part(a, key: "a_2") = part(b) / (1+c)$)
 
#align(center, context [
  #kino-morph("f")
])
  ```

  #create(f: $part(a) = o = part(a, key: "a_2") = part(b)$, duration: 2)
  #animate(f: $1 / part(a) = o = part(a, key: "a_2") = part(b) / (1+c)$)
 
  #align(center, context [
    #kino-morph("f")
  ])

  Creation and morphing of formulas (and other objects) is done by using `#kino-morph("f")` to show the object. Morphing animation are performed only in the custom export of the presentation. In pdf, objects are simply replaced by the new one.

  In the formula above, "= o =" is not a marked part so it will fade out and in during the animation. $a$ and $b$ are marked parts so they will move into place. $a$ appears two time so we gave a key to the second one so it will no collide with the first one.
  #finish()
]

#slide(
  title: "Draw border then fill",
)[
  #slide-heading[Draw border then fill]

  You can draw a full cetz canvas in a state and animate its creation with kino-morph. The default morph-effect is "draw-border-then-fill" which will draw the border of the shapes and then fill them.

  This also work with normal text.

  #create(draw-state: [
    #cetz.canvas({
      import cetz.draw: *
      circle((0pt, 0pt), radius: 70pt, fill: green, stroke: 3pt + green.darken(70%))
    })
  ], block:1, morph-effect: "draw-border-then-fill")

  #create(draw-state2: text(stroke:red.darken(70%), red, 64pt)[*HELLO !*], 
  block:2, duration:2, morph-effect: "draw-border-then-fill")

  #grid(
    columns: 2,
    [
#set text(16pt)
```typst
  #create(draw-state: [
    #cetz.canvas({
      import cetz.draw: *
      circle((0pt, 0pt), radius: 70pt, fill: green, stroke: 3pt + green.darken(70%))
    })
  ], block:1, morph-effect: "draw-border-then-fill")

  #create(draw-state2: text(stroke:red.darken(70%), red, 64pt)[*HELLO !*], 
  block:2, duration:2, morph-effect: "draw-border-then-fill")

  #context {
    align(center, kino-morph("draw-state"))
    align(center, kino-morph("draw-state2"))
  }
  
#finish()
```
    ],[
  #context {
    align(center, kino-morph("draw-state"))
    align(center, kino-morph("draw-state2"))
  }
  ])
  #finish()
]


#slide(
  title: "Morph arbitrary shapes",
)[
  #slide-heading[We can also morph arbitrary shapes]

  Here we used a utililty function `cetz-shape`, but you can put an arbitrary cetz canvas or other object, kino-morph will try to morph it into the new one.

  #init(shape-state: cetz-shape(
    cetz.draw.circle((0pt, 0pt), radius: 65pt, fill: blue, stroke: 3pt + blue.darken(70%)),
  ))
  #animate(shape-state: cetz-shape(
    cetz.draw.rect((-65pt, -65pt), (65pt, 65pt), fill: red, stroke: 3pt + red.darken(70%)),
  ))
  #init(x: 0.0)
  #animate(x: 4, duration: 2)
  #init(sc: 1.0)
  #animate(sc: 2.0, duration: 2, block: 2)


  #grid(
    columns: 2,
    [
#set text(12pt)

```typst
  #init(shape-state: cetz-shape(
    cetz.draw.circle((0pt, 0pt), radius: 65pt, 
      fill: blue, stroke: 3pt + blue.darken(70%)),
  ))
  #animate(shape-state: cetz-shape(
    cetz.draw.rect((-65pt, -65pt), (65pt, 65pt), 
      fill: red, stroke: 3pt + red.darken(70%)),
  ))
  #init(x: 0.0)
  #animate(x: 4, duration: 2)
  #init(sc: 1.0)
  #animate(sc: 2.0, duration: 2, block: 2)

#context {
  cetz.canvas({
    import cetz.draw: *

    content(kino-morph("shape-state", cetz: content)

    if a("x") > 0 {
      group({
        scale(a("sc"))
        translate((a("x"), -a("x")))
        rect((-65pt, -65pt), (65pt, 65pt), fill: red, stroke: 3pt + red.darken(70%))
      })
    }
  })
}
#finish()

```
], [
  #context {
    cetz.canvas({
      import cetz.draw: *

      kino-morph("shape-state", cetz: content)

      if a("x") > 0 {
        group({
          scale(a("sc"))
          translate((a("x"), -a("x")))
          rect((-65pt, -65pt), (65pt, 65pt), fill: red, stroke: 3pt + red.darken(70%))
        })
      }
    })
  }
  #finish()

    ]
  )
]
