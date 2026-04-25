defmodule AshGrant.Test.GrantsDomainResolverPost do
  @moduledoc """
  Sits in a domain that has `grants` declared but defines its **own**
  explicit `resolver`. The resource's resolver fully overrides the domain
  resolver, so the domain's grants should **not** run for this resource.
  Pins the documented interaction so the shadowing stays intentional.
  """
  use Ash.Resource,
    domain: AshGrant.Test.GrantsOnlyDomain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resource_name("grants_domain_resolver_post")
    default_policies(true)

    resolver(fn actor, _context ->
      case actor do
        %{role: :custom_resolver_actor} -> ["grants_domain_resolver_post:*:*:always"]
        _ -> []
      end
    end)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)
    attribute(:author_id, :uuid, public?: true)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :author_id])
    end
  end
end
