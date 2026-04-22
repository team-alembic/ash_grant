# Used by "mix format"
locals_without_parens = [
  # AshGrant DSL entities
  can_perform: 1,
  can_perform: 2,
  resolver: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
