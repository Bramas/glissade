#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 8)

#slide(id: "overview-title", title: "Overview title", autoplay: true, fps: 16)[
  #text(size: 22pt, weight: "bold")[Slide metadata]
  #v(18pt)

  #init(width: 70pt)
  #animate(width: 210pt, duration: .9)
  #wait(duration: .45)
  #cut(loop: true)

  #context [
    #align(center)[
      #rect(width: a("width"), height: 38pt, radius: 19pt, fill: rgb(240, 192, 74))
      #v(12pt)
      #text(size: 12pt, fill: rgb("#526064"))[
        slide #slide-number()
      ]
    ]
  ]

]
