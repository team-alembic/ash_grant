defmodule AshGrant.Domain.Dsl do
  @moduledoc """
  DSL definition for the AshGrant domain-level extension.

  This module defines the `ash_grant` DSL section that can be added to
  Ash domains to configure shared permission settings inherited by resources.

  Supported at the domain level: `resolver`, `scope`, and `grants`.
  Resource-specific options like `resource_name`, `default_policies`, and
  `field_group` must be configured on each resource.

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
          resource MyApp.Blog.Post    # inherits domain grants + scopes
          resource MyApp.Blog.Comment
        end
      end

  Resources may still declare their own `grants` block — both levels
  contribute, with the resource winning on grant-name conflicts.
  """

  @ash_grant %Spark.Dsl.Section{
    name: :ash_grant,
    top_level?: false,
    imports: [Ash.Expr],
    sections: [AshGrant.Dsl.domain_grants_section()],
    describe: """
    Shared AshGrant configuration inherited by resources in this domain.

    Resources using the `AshGrant` extension inherit the `resolver`, `scope`
    definitions, and `grants` from their domain. Resources can add their own
    `grants` and `scope` entries on top — both levels contribute.
    """,
    examples: [
      """
      ash_grant do
        resolver MyApp.PermissionResolver

        scope :always, true
        scope :own, expr(author_id == ^actor(:id))
      end
      """,
      """
      ash_grant do
        scope :always, true

        grants do
          grant :admin, expr(^actor(:role) == :admin) do
            permission :manage_posts, MyApp.Blog.Post, :*, :always
          end
        end
      end
      """
    ],
    entities: [AshGrant.Dsl.scope_entity()],
    schema: [
      resolver: [
        type: {:or, [{:behaviour, AshGrant.PermissionResolver}, {:fun, 2}]},
        required: false,
        doc: """
        Module implementing `AshGrant.PermissionResolver` behaviour,
        or a 2-arity function `(actor, context) -> permissions`.

        This resolver is inherited by all resources in the domain that
        use the `AshGrant` extension and don't define their own resolver.

        Mutually exclusive with a `grants` block on the same domain — if
        grants are declared, the extension synthesizes the resolver for you.
        """
      ]
    ]
  }

  @sections [@ash_grant]

  def sections, do: @sections
end
