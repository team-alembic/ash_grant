defmodule AshGrant.Domain do
  @moduledoc """
  Domain-level extension for AshGrant.

  Add this extension to an Ash domain to define shared `resolver`, `scope`,
  and `grants` configurations that are automatically inherited by all
  resources in the domain that use the `AshGrant` extension.

  ## Domain grants are always broadcasts

  A domain-level `permission :name, :action, :scope` applies to **every
  resource** in the domain. This mirrors how `Ash.Policy.Authorizer`
  treats domain-level policies (they cover every resource/action unless
  narrowed). The `AshGrant.GrantsResolver` substitutes the resource being
  authorized at runtime, so a single domain permission lights up all of
  them.

  To grant a permission on one specific resource, declare it on **that
  resource's** `grants` block. There is no per-permission target keyword
  — the location of the grant is what scopes it.

  Resource and domain grants are complementary: both can be declared and
  both contribute to a resource's effective permissions. Resources can
  also override an individual domain grant by declaring one with the same
  `:name`.

  ## Example

      defmodule MyApp.Blog do
        use Ash.Domain,
          extensions: [AshGrant.Domain]

        ash_grant do
          scope :always, true
          scope :own, expr(author_id == ^actor(:id))

          grants do
            # Broadcast — every resource in the domain
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

      # Resource-specific grant lives on the resource:
      defmodule MyApp.Blog.Post do
        use Ash.Resource, domain: MyApp.Blog, extensions: [AshGrant]

        ash_grant do
          grants do
            grant :auditor, expr(^actor(:role) == :auditor) do
              permission :audit_posts, :read
            end
          end
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

  ### `grants` and `resolver` are additive, not mutually exclusive

  You can declare both `grants` and an explicit `resolver` on the same
  resource *and* the same domain. At runtime the synthesized
  `AshGrant.GrantsResolver`:

  1. Evaluates declared grants (resource + domain merged) and emits
     permission strings for every matching grant.
  2. Calls the user-declared resolver (resource first, domain fallback)
     and concatenates *its* permission strings onto the list.
  3. The combined list flows through `AshGrant.Evaluator.has_access?/3`
     exactly as before — deny from either source still wins.

  This lets grants handle the static RBAC + ABAC while a resolver covers
  dynamic per-row permissions (e.g. DB-backed sharing). Pair them freely.
  """

  use Spark.Dsl.Extension,
    sections: AshGrant.Domain.Dsl.sections(),
    transformers: [],
    verifiers: [
      AshGrant.Domain.Verifiers.ValidateGrantReferences
    ]
end
