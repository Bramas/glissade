#import "../../lib.typ": *
#import "@preview/cetz:0.5.1"


#import "theme.typ": *
#set page(width: 128mm, height: 96mm)

#show: animation

#show: theme

#animate(x: 1.0)
#cut()
#animate(x: 2)

#context {
  cetz.canvas({
  import cetz.draw: *
    circle((0, 0))
    line((a("x"), 0), (1, 1))
  })
}

#finish()

