// The active slide is contextual: animation primitives use it to select their
// slide-local state without requiring an explicit context argument.
#let active-slide = state("glissade.active-slide", "__glissade-none__")
#let slide-scope(id) = metadata(("glissade_slide_scope": id))
