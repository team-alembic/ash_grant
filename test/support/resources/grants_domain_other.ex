defmodule AshGrant.Test.GrantsDomainOther do
  @moduledoc """
  Secondary resource in `AshGrant.Test.GrantsOnlyDomain`. Exists so a
  domain-level grant can declare a permission whose `on:` targets a
  *different* resource than the one being checked, proving that a single
  domain grant can cover multiple resources.
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
