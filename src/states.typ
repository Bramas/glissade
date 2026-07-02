#import "utils.typ": get_default_dict

// The active slide is contextual: animation primitives use it to select their
// slide-local state without requiring an explicit context argument.
#let active-slide = state("kino.active-slide", "__kino-none__")
#let slide-counter = counter("kino.slide")

#let _key(id, name) = "kino." + id + "." + name

#let begin(id) = state(_key(id, "begin"), false)
#let cut-blocks(id) = state(_key(id, "cut-blocks"), ())
#let loop-blocks(id) = state(_key(id, "loop-blocks"), ())
#let time-block(id) = state(_key(id, "time-block"), 1)
#let time(id) = state(_key(id, "time"), 0)
#let max-block(id) = state(_key(id, "max-block"), 1)
#let current-block(id) = state(_key(id, "current-block"), 1)
#let timeline(id) = state(_key(id, "timeline"), (
  "builtin_pause_counter": get_default_dict(),
))
#let rewind-location(id) = state(_key(id, "rewind-location"), none)
#let frozen-values(id) = state(_key(id, "frozen-values"), ())

#let slide-scope(id) = metadata(("kino_slide_scope": id))

#let current-slide() = {
  let scopes = query(selector(metadata).before(here())).filter(element => (
    type(element.value) == dictionary and "kino_slide_scope" in element.value
  ))
  if scopes.len() > 0 {
    scopes.last().value.kino_slide_scope
  } else {
    active-slide.get()
  }
}
