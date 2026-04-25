with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Lensmaker do
    @moduledoc """
    Clarity lensmaker that contributes a dedicated "Permissions" lens and
    teaches the built-in "security" lens about AshGrant vertex types.

    The Permissions lens filters the graph down to Ash domains, resources,
    actions, and the AshGrant DSL vertices contributed by this integration
    (scopes, grants, field groups).
    """

    @behaviour Clarity.Perspective.Lensmaker

    import Phoenix.Component

    alias AshGrant.Clarity.Vertex.FieldGroup, as: FieldGroupVertex
    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Perspective.Lens
    alias Clarity.Vertex

    @impl Clarity.Perspective.Lensmaker
    def make_lens do
      %Lens{
        id: "permissions",
        name: "Permissions",
        description: "AshGrant scopes, grants, and field groups across domains and resources",
        icon: fn ->
          assigns = %{}
          ~H"🔐"
        end,
        filter: true,
        show_vertex_types: &show_permissions_vertex_types/1
      }
    end

    @impl Clarity.Perspective.Lensmaker
    def update_lens(%Lens{id: "security"} = lens) do
      base = lens.show_vertex_types

      %Lens{
        lens
        | show_vertex_types: fn available ->
            admitted = base.(available)
            extras = Enum.filter(available, &(&1 in ash_grant_vertex_types()))
            Enum.uniq(admitted ++ extras)
          end
      }
    end

    def update_lens(lens), do: lens

    defp show_permissions_vertex_types(available) do
      allowlist =
        [
          Vertex.Application,
          Vertex.Ash.Domain,
          Vertex.Ash.Resource,
          Vertex.Ash.Action
        ] ++ ash_grant_vertex_types()

      Enum.filter(available, &(&1 in allowlist))
    end

    defp ash_grant_vertex_types do
      [ScopeVertex, GrantVertex, FieldGroupVertex]
    end
  end
end
