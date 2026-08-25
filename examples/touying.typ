#import "@preview/touying:0.7.3": *
#import themes.simple: *
#import "../lib.typ" as glissade

#show: simple-theme.with(aspect-ratio: "16-9")

#let glissade-animation = glissade.touying(
  touying-fn-wrapper,
  fps: 2,
)

== Touying integration

This slide is rendered and themed by Touying.

#pause

#glissade-animation(id: "moving-circle")[
  #glissade.init(x: 0pt)
  #glissade.animate(duration: 1, x: 180pt)

  #context {
    move(dx: glissade.a("x"), circle(radius: 12pt, fill: blue))
  }
]

#pause

The final reveal is another native Touying subslide.

== Ordinary Touying slide

#uncover("2-")[Glissade exports native `uncover` steps as presenter cuts.]


== Ordinary Touying slide with `#slide`

#slide[
  Another touying slide with a native Touying subslide.

  #glissade-animation(id: "morphing")[
    #glissade.create(f: $glissade.part(a) = o = glissade.part(a, key: "a_2") = glissade.part(b)$, duration: 2)
    #glissade.animate(f: $1 / glissade.part(a) = o = glissade.part(a, key: "a_2") = glissade.part(b) / (1+c)$, duration: 0.5)
  
    #align(center, context [
      #glissade.glissade-morph("f")
    ])
  ]
]