[
  import_deps: [:phoenix, :ecto, :typed_ecto_schema],
  locals_without_parens: [
    field: :*,
    belongs_to: :*,
    has_one: :*,
    has_many: :*,
    many_to_many: :*,
    embeds_one: :*,
    embeds_many: :*,
    polymorphic_embeds_one: :*,
    polymorphic_embeds_many: :*
  ],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
