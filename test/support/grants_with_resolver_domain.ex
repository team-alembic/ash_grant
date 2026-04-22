defmodule AshGrant.Test.GrantsWithResolverDomain do
  @moduledoc """
  Test domain that declares **both** `resolver` and `grants`.

  Exists specifically to cover the regression where
  `AshGrant.Info.raw_resolver/1` must surface the user's resolver
  module (for `load_actor/1`) while `AshGrant.Info.resolver/1` hands
  back the synthesized `AshGrant.GrantsResolver` so grants still drive
  permission emission.
  """
  use Ash.Domain,
    extensions: [AshGrant.Domain],
    validate_config_inclusion?: false

  ash_grant do
    resolver(AshGrant.Test.GrantsWithResolverLoader)

    grants do
      grant :admin, expr(^actor(:role) == :admin) do
        permission(:manage_post, AshGrant.Test.GrantsWithResolverPost, :*)
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        permission(:read_post, AshGrant.Test.GrantsWithResolverPost, :read)
      end
    end
  end

  resources do
    resource(AshGrant.Test.GrantsWithResolverPost)
  end
end
