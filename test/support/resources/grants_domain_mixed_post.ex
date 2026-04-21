defmodule AshGrant.Test.GrantsDomainMixedPost do
  @moduledoc """
  Declares its own `grants` block with *different* grant names than the
  domain. After merge, `AshGrant.Info.grants/1` should return both the
  resource's grant and the domain's grants.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_mixed_post")
    default_policies(true)

    grants do
      grant :editor, expr(^actor(:role) == :editor) do
        permission(:read_any, :read, :always)
        permission(:update_own, :update, :own)
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
