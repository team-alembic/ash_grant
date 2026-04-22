defmodule AshGrant.Test.GrantsWithResolverLoader do
  @moduledoc """
  Test resolver that supplies `load_actor/1` only.

  Mirrors the real-world pattern where a project declares `grants` on a
  domain and *also* declares a `resolver` module purely so identifier-
  based introspection (Actor Explorer, `explain_by_identifier/1`) can
  hydrate actors from an id. `resolve/2` returns an empty list because
  grants drive permission emission.
  """

  @behaviour AshGrant.PermissionResolver

  @users %{
    "admin" => %{id: "admin", role: :admin},
    "viewer" => %{id: "viewer", role: :viewer}
  }

  @impl AshGrant.PermissionResolver
  def resolve(_actor, _context), do: []

  @impl AshGrant.PermissionResolver
  def load_actor(id) do
    case Map.fetch(@users, id) do
      {:ok, actor} -> {:ok, actor}
      :error -> :error
    end
  end
end
