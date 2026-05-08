defmodule AshGrant.Test.GrantsDomainPost do
  @moduledoc """
  Inherits all grants and scopes from `AshGrant.Test.GrantsOnlyDomain`.
  Declares no grants/resolver/scopes of its own — the policy machinery
  should use the domain-synthesized `GrantsResolver` and see the domain's
  grants at runtime via `AshGrant.Info.grants/1`.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_post")
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

    update :update do
      accept([:title, :status])
    end
  end
end
