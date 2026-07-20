#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 15pt)
#show: deck.with(fps: 16)

#let row(label, y, x, color) = [
  #place(dx: 8pt, dy: y)[#text(size: 11pt, fill: rgb("#526064"))[#label]]
  #place(dx: 78pt, dy: y + 5pt)[
    #line(length: 210pt, stroke: 1pt + rgb(213, 221, 218))
  ]
  #place(dx: 78pt + x, dy: y)[#circle(radius: 8pt, fill: color)]
]

#slide(id: "transitions", title: "Transition functions", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Choose the interpolation curve]
  #v(16pt)

  #init(linear-x: 0pt, smooth-x: 0pt, sin-x: 0pt)
  #animate(linear-x: 200pt, duration: 1.2, transition: linear)
  #meanwhile(smooth-x: 200pt, duration: 1.2, transition: smooth)
  #meanwhile(sin-x: 200pt, duration: 1.2, transition: sin)
  #wait(duration: .45)
  #cut(loop: true)

  #context [
    #row("linear", 28pt, a("linear-x"), rgb("#2f5e9e"))
    #row("smooth", 78pt, a("smooth-x"), rgb("#246b61"))
    #row("sin", 128pt, a("sin-x"), rgb("#b24a7b"))
  ]

]
