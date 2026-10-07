defmodule AshGrant.Test.GrantsDomainDenyPost do
  @moduledoc """
  Sits in `AshGrant.Test.GrantsOnlyDomain`, which broadcasts an admin
  allow for every action on every resource (`:admin → :*:*:always`).
  This resource adds a *resource-level deny* on `:destroy` for the same
  admin actor — exercising deny-wins across the domain/resource
  boundary: domain allow + resource deny → deny wins.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_deny_post")
    default_policies(true)

    grants do
      grant :admin_no_destroy, expr(^actor(:role) == :admin) do
        description("Resource-level deny: admins cannot destroy on this resource")
        permission(:no_destroy, :destroy, deny: true)
      end
    end
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
