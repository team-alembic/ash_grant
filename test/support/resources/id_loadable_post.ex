defmodule AshGrant.Test.IdLoadablePost do
  @moduledoc """
  Test resource whose permission resolver is a module (not an anonymous
  function) and implements the optional `load_actor/1` callback.

  Used to exercise `AshGrant.Introspect.explain_by_identifier/1` and
  related identifier-based entry points.
  """
  use Ash.Resource,
    domain: AshGrant.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resolver(AshGrant.Test.IdLoadableResolver)
    resource_name("id_loadable_post")

    scope(:always, true)
    scope(:own, expr(author_id == ^actor(:id)))
  end

  policies do
    policy action_type(:read) do
      authorize_if(AshGrant.filter_check())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(AshGrant.check())
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)
    attribute(:author_id, :string, public?: true)
  end

  actions do
    defaults([:read, :destroy, :create, :update])
  end
end

defmodule AshGrant.Test.NoLoadActorPost do
  @moduledoc """
  Test resource whose permission resolver is a module but does NOT
  implement the optional `load_actor/1` callback.

  Used to verify identifier-based introspection returns
  `{:error, :actor_loader_not_implemented}` when the resolver can't load
  actors by ID.
  """
  use Ash.Resource,
    domain: AshGrant.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resolver(AshGrant.Test.NoLoadActorResolver)
    resource_name("no_load_actor_post")

    scope(:always, true)
  end

  policies do
    policy action_type(:read) do
      authorize_if(AshGrant.filter_check())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(AshGrant.check())
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, :create, :update])
  end
end
