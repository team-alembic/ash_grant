defmodule AshGrant.Test.ResolverOnlyDomain do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshGrant.Domain],
    validate_config_inclusion?: false

  ash_grant do
    resolver(fn actor, _context ->
      case actor do
        nil -> []
        %{permissions: perms} -> perms
        _ -> []
      end
    end)
  end

  resources do
    resource(AshGrant.Test.ResolverOnlyPost)
  end
end
