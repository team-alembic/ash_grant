defmodule AshGrant.Test.GrantsOnlyDomain do
  @moduledoc """
  Test domain exercising the declarative `grants` DSL at the **domain**
  level. Resources in this domain inherit these grants (and the shared
  scopes) unless they declare their own.

  Covers:
  - Broadcast permissions (no `on:`) applied to every resource in the domain
  - Resource-scoped domain permissions (`on: SpecificResource`)
  - Resource-level grants merging with domain-level grants
  """
  use Ash.Domain,
    extensions: [AshGrant.Domain],
    validate_config_inclusion?: false

  ash_grant do
    scope(:always, true)
    scope(:own, expr(author_id == ^actor(:id)))
    scope(:published, expr(status == :published))

    grants do
      grant :admin, expr(^actor(:role) == :admin) do
        description("Full administrative access — broadcast across the domain")
        # Broadcast: applies to every resource in the domain. The resolver
        # substitutes the resource being authorized at runtime.
        permission(:manage_all, :*, :always)
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        description("Viewers see published rows on every resource")
        permission(:read_published, :read, :published)
      end

      grant :auditor, expr(^actor(:role) == :auditor) do
        description("Auditor's read access scoped to a single resource")
        # Resource-scoped: the keyword `on:` narrows this permission to one
        # resource in the domain (Ash's `policy resource_is/1` analog).
        permission(:audit_post, :read, :always, on: AshGrant.Test.GrantsDomainPost)
      end
    end
  end

  resources do
    resource(AshGrant.Test.GrantsDomainPost)
    resource(AshGrant.Test.GrantsDomainMixedPost)
    resource(AshGrant.Test.GrantsDomainOverridePost)
    resource(AshGrant.Test.GrantsDomainOther)
    resource(AshGrant.Test.GrantsDomainResolverPost)
  end
end
