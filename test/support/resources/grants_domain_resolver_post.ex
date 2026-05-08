defmodule AshGrant.Test.GrantsDomainResolverPost do
  @moduledoc """
  Sits in a domain that has `grants` declared and *also* defines its own
  explicit `resolver`. Both contribute additively: domain grants apply to
  every resource in the domain (broadcasts), and the resource's resolver
  runs on top of that. The combined permission list flows through the
  same `Evaluator` — deny-wins still holds across both sources.
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
        # An :admin actor also matches the domain's :admin broadcast, so this
        # row exercises the additive merge: domain grant + resource resolver
        # both contribute permissions for the same actor.
        %{role: :admin} -> ["grants_domain_resolver_post:*:audit:always"]
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
