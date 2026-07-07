// The active slide is contextual: animation primitives use it to select their
// slide-local state without requiring an explicit context argument.
#let active-slide = state("kino.active-slide", "__kino-none__")
#let slide-scope(id) = metadata(("kino_slide_scope": id))
