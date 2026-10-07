defmodule AshGrant.Test.GrantsDomainOther do
  @moduledoc """
  Secondary resource in `AshGrant.Test.GrantsOnlyDomain`. Lets us prove
  that a single domain-level grant covers multiple resources at once
  (broadcast): the resolver substitutes whichever resource is being
  authorized, so the same domain permission lights up `GrantsDomainPost`
  and this resource alike.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_other")
    default_policies(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)
    attribute(:author_id, :uuid, public?: true)

    attribute :status, :atom do
      constraints(one_of: [:draft, :published])
      default(:draft)
      public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :author_id, :status])
    end
  end
end
