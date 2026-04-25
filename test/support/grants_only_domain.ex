defmodule AshGrant.Test.GrantsOnlyDomain do
  @moduledoc """
  Test domain exercising the declarative `grants` DSL at the **domain**
  level. Resources in this domain inherit these grants (and the shared
  scopes) unless they declare their own.

  Domain grants are always broadcasts — they apply to every resource in
  the domain. To grant a permission on a specific resource only, declare
  it on that resource's `grants` block.
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
        permission(:manage_all, :*, :always)
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        description("Viewers see published rows on every resource")
        permission(:read_published, :read, :published)
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
