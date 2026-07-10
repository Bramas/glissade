#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 12)

#let accent = rgb("#246b61")

#slide(id: "meanwhile", title: "Coordinate variables", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Move and fade together]
  #v(22pt)

  #init(x: 20pt, opacity: 20%)
  #animate(x: 210pt, duration: 1.2)
  #meanwhile(opacity: 100%, duration: 1.2)
  #wait(duration: .45)
  #cut(loop: true)

  #context [
    #place(dx: a("x"), dy: 32pt)[
      #circle(radius: 23pt, fill: accent.transparentize(100% - a("opacity")))
    ]
  ]

  #finish()
]
