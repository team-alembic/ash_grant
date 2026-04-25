defmodule AshGrant.Domain.Dsl do
  @moduledoc """
  DSL definition for the AshGrant domain-level extension.

  Adds an `ash_grant` block to an `Ash.Domain`. Supported configuration:

  - `resolver` — a permission resolver inherited by resources that don't
    define their own.
  - `scope` entities — row-level filters (`expr(...)`) inherited by every
    resource in the domain. Resource-level scopes with the same name win.
  - `grants do ... end` — declarative grants that apply to **every**
    resource in the domain. Mirrors how `Ash.Policy.Authorizer` treats
    domain-level policies (cover every resource/action). To grant a
    permission on a specific resource, declare it on that resource's
    `grants` block.

  Resource-specific options like `resource_name`, `default_policies`, and
  `field_group` must be configured on each resource.

  ## Example

      defmodule MyApp.Blog do
        use Ash.Domain, extensions: [AshGrant.Domain]

        ash_grant do
          scope :always, true
          scope :own, expr(author_id == ^actor(:id))

          grants do
            # Applies to every resource in the domain
            grant :admin, expr(^actor(:role) == :admin) do
              permission :manage_all, :*, :always
            end

            grant :editor, expr(^actor(:role) == :editor) do
              permission :read_all,   :read
              permission :update_own, :update, :own
            end
          end
        end

        resources do
          resource MyApp.Blog.Post
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
    sections: [AshGrant.Dsl.grants_section()],
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
        scope :own, expr(author_id == ^actor(:id))

        grants do
          # Broadcasts — apply to every resource in the domain
          grant :admin, expr(^actor(:role) == :admin) do
            permission :manage_all, :*, :always
          end

          grant :editor, expr(^actor(:role) == :editor) do
            permission :read_all,   :read
            permission :update_own, :update, :own
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

        Combines additively with `grants`: when both are declared on the
        same domain, `AshGrant.GrantsResolver` evaluates the grants and
        then calls this resolver, concatenating both permission lists.
        """
      ]
    ]
  }

  @sections [@ash_grant]

  def sections, do: @sections
end
