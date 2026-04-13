defmodule AshGrant.Test.IdLoadableResolver do
  @moduledoc false
  @behaviour AshGrant.PermissionResolver

  @users %{
    "user_1" => %{
      id: "user_1",
      role: :editor,
      permissions: ["id_loadable_post:*:read:always"]
    },
    "user_2" => %{
      id: "user_2",
      role: :editor,
      permissions: ["id_loadable_post:*:update:own", "id_loadable_post:*:read:always"]
    }
  }

  @impl true
  def resolve(actor, _context) do
    case actor do
      nil -> []
      %{permissions: perms} -> perms
      _ -> []
    end
  end

  @impl true
  def load_actor(id) do
    case Map.fetch(@users, id) do
      {:ok, actor} -> {:ok, actor}
      :error -> :error
    end
  end
end

defmodule AshGrant.Test.NoLoadActorResolver do
  @moduledoc false
  @behaviour AshGrant.PermissionResolver

  @impl true
  def resolve(actor, _context) do
    case actor do
      nil -> []
      %{permissions: perms} -> perms
      _ -> []
    end
  end
end
