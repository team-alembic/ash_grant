defmodule AshGrant.Test.GrantsWithResolverPost do
  @moduledoc """
  Resource whose domain declares both `resolver` and `grants`. The
  resource itself adds nothing — it relies on domain inheritance for
  every AshGrant setting. See `AshGrant.Test.GrantsWithResolverDomain`.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsWithResolverDomain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_with_resolver_post")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, :create, :update])
  end
end
