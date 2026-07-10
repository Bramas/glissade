#import "../../lib.typ": *

#set page(width: 360pt, height: 270pt, margin: 24pt)
#set text(font: "New Computer Modern", size: 16pt)
#show: deck.with(fps: 12)

#let accent = rgb("#2f5e9e")

#slide(id: "then-wait-cut", title: "Sequence and cuts", autoplay: true)[
  #text(size: 22pt, weight: "bold")[Build a readable sequence]
  #v(18pt)

  #init(step: 0)
  #animate(step: 1, duration: .45)
  #then(step: 2, duration: .45)
  #wait(duration: .35)
  #then(step: 3, duration: .45)
  #wait(duration: .55)
  #cut(loop: true)

  #context [
    #grid(
      columns: (1fr, 1fr, 1fr),
      gutter: 9pt,
      ..range(1, 4).map(i => {
        let active = a("step") >= i
        [
          #rect(
            width: 88pt,
            height: 58pt,
            radius: 6pt,
            fill: if active { accent } else { rgb("#dfe6e3") },
          )[
            #align(center + horizon)[
              #text(fill: if active { white } else { rgb("#46514e") })[#i]
            ]
          ]
        ]
      }),
    )
  ]

  #finish()
]
