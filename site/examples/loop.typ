#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 12)

#slide(id: "loop", title: "Loop a segment", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Loop until the presenter advances]
  #v(22pt)

  #init(width: 48pt)
  #animate(width: 230pt, duration: .9)
  #animate(width: 48pt, duration: .9)
  #wait(duration: .35)
  #cut(loop: true)

  #context [
    #rect(width: a("width"), height: 40pt, radius: 20pt, fill: rgb("#19a974"))
  ]

]
