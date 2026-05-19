with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Introspector.Domain do
    @moduledoc """
    Emits AshGrant scope and grant vertices beneath every
    `Clarity.Vertex.Ash.Domain` that uses the `AshGrant.Domain` extension.
    """

    @behaviour Clarity.Introspector

    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Domain, as: DomainVertex

    @impl Clarity.Introspector
    def source_vertex_types, do: [DomainVertex]

    @impl Clarity.Introspector
    def introspect_vertex(%DomainVertex{domain: domain} = domain_vertex, _graph) do
      if AshGrant.Domain.Info.configured?(domain) do
        {:ok, scope_entries(domain, domain_vertex) ++ grant_entries(domain, domain_vertex)}
      else
        {:ok, []}
      end
    rescue
      UndefinedFunctionError -> {:ok, []}
    end

    defp scope_entries(domain, domain_vertex) do
      domain
      |> AshGrant.Domain.Info.scopes()
      |> Enum.flat_map(fn scope ->
        vertex = %ScopeVertex{owner: domain, owner_kind: :domain, scope: scope}
        [{:vertex, vertex}, {:edge, domain_vertex, vertex, :ash_grant_scope}]
      end)
    end

    defp grant_entries(domain, domain_vertex) do
      domain
      |> AshGrant.Domain.Info.grants()
      |> Enum.flat_map(fn grant ->
        vertex = %GrantVertex{owner: domain, owner_kind: :domain, grant: grant}
        [{:vertex, vertex}, {:edge, domain_vertex, vertex, :ash_grant_grant}]
      end)
    end
  end
end
