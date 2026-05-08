defmodule AshGrant.Test.GrantsDomainOverridePost do
  @moduledoc """
  Declares its own `:admin` grant with a different predicate than the
  domain's `:admin` grant. Because grant-name conflicts resolve with
  resource-wins (same policy as `scope` inheritance), the resource's
  definition should be the one that runs.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_override_post")
    default_policies(true)

    grants do
      grant :admin, expr(^actor(:role) == :super_admin) do
        description("Resource-level override: only :super_admin matches here")
        permission(:manage_all, :*, :always)
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

    update :update do
      accept([:title, :status])
    end
  end
end
