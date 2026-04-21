defmodule AshGrant.Domain do
  @moduledoc """
  Domain-level extension for AshGrant.

  Add this extension to an Ash domain to define shared `resolver`, `scope`,
  and `grants` configurations that are automatically inherited by all
  resources in the domain that use the `AshGrant` extension.

  Resource and domain grants are complementary: both can be declared, and
  both contribute to a resource's effective permissions. Resources can also
  override an individual domain setting by declaring their own.

  ## Example

      defmodule MyApp.Blog do
        use Ash.Domain,
          extensions: [AshGrant.Domain]

        ash_grant do
          scope :always, true
          scope :own, expr(author_id == ^actor(:id))

          grants do
            grant :admin, expr(^actor(:role) == :admin) do
              permission :manage_posts, MyApp.Blog.Post, :*, :always
              permission :manage_comments, MyApp.Blog.Comment, :*, :always
            end
          end
        end

        resources do
          resource MyApp.Blog.Post
          resource MyApp.Blog.Comment
        end
      end

  ## Inheritance Rules

  | Config | Resource has it | Domain has it | Result |
  |--------|----------------|---------------|--------|
  | resolver | Yes | Yes | Resource wins |
  | resolver | No | Yes | Domain's resolver used |
  | scope (same name) | Yes | Yes | Resource wins (override) |
  | scope | No | Yes | Domain scope inherited |
  | grants (different names) | Yes | Yes | Both contribute |
  | grants (same name) | Yes | Yes | Resource wins (override) |
  | grants | No | Yes | Domain grants used |

  ### Interaction with an explicit `resolver`

  Declaring `grants` on the domain and an explicit `resolver` on the *same*
  domain is a compile error — grants synthesize the resolver, so they are
  mutually exclusive at a given level.

  A resource that defines its own `resolver` fully overrides the domain's
  resolver, which means domain-level `grants` will **not** run for that
  resource. Remove the resource resolver (or switch to a resource `grants`
  block) if you want domain grants to apply.
  """

  use Spark.Dsl.Extension,
    sections: AshGrant.Domain.Dsl.sections(),
    transformers: [
      AshGrant.Domain.Transformers.SynthesizeGrantsResolver
    ],
    verifiers: [
      AshGrant.Domain.Verifiers.ValidateGrantReferences
    ]
end
