defmodule AshGrant.Test.GrantsOnlyDomain do
  @moduledoc """
  Test domain exercising the declarative `grants` DSL at the **domain**
  level. Resources in this domain inherit these grants (and the shared
  scopes) unless they declare their own.

  Covers the four interaction cases described in `AshGrant.Domain`:
  - Resource has no grants → inherits domain grants
  - Resource has grants with different names → both contribute
  - Resource has grants with the same name → resource wins
  - A domain-level grant whose `on:` targets a different resource
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
        description("Full administrative access across the domain")
        permission(:manage_main, :*, :always, on: AshGrant.Test.GrantsDomainPost)
        permission(:manage_other, :*, :always, on: AshGrant.Test.GrantsDomainOther)
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        description("Viewers see published posts")
        permission(:read_published, :read, :published, on: AshGrant.Test.GrantsDomainPost)
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
