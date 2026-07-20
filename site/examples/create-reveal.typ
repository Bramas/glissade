#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 12)

#slide(id: "create-reveal", title: "Create content", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Introduce content from nothing]
  #v(30pt)

  #create(card: [
    #rect(width: 230pt, height: 92pt, radius: 8pt, fill: rgb("#d8e9df"), stroke: 1pt + rgb("#246b61"))[
      #align(center + horizon)[
        #text(size: 18pt, weight: "bold", fill: rgb("#246b61"))[New idea]
      ]
    ]
  ], duration: 1.5)
  #wait(duration: .45)
  #cut(loop: true)

  #align(center)[
    #context [#glissade-morph("card")]
  ]

]
