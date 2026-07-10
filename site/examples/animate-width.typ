#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 12)

#let accent = rgb("#2563eb")

#slide(id: "animate-width", title: "Animate a value", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Animate one variable]
  #v(18pt)

  #init(width: 42pt)
  #animate(width: 220pt, duration: 1.1)
  #wait(duration: .45)
  #cut(loop: true)

  #context [
    #rect(width: a("width"), height: 34pt, radius: 5pt, fill: accent)
    #v(12pt)
    #text(size: 12pt, fill: rgb("#526064"))[
      width = #calc.round(a("width").pt()) pt
    ]
  ]

  #finish()
]
