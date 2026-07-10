#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 18pt)
#show: deck.with(fps: 12)

#slide(id: "formula-morph", title: "Formula morphing", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Track formula parts]
  #v(34pt)

  #init(eq: formula($part(a) part(=) part(b)$))
  #animate(eq: formula($part(a) / part(c) part(=) part(b) / part(c)$), duration: 1.1)
  #wait(duration: .45)
  #cut(loop: true)

  #align(center)[
    #context [
      #text(size: 34pt)[#glissade-morph("eq")]
    ]
  ]

  #finish()
]
