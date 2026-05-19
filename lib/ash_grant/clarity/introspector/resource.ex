with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Introspector.Resource do
    @moduledoc """
    Emits AshGrant DSL vertices (scopes, grants, field groups) beneath every
    `Clarity.Vertex.Ash.Resource` that uses the `AshGrant` extension.
    """

    @behaviour Clarity.Introspector

    alias AshGrant.Clarity.Vertex.FieldGroup, as: FieldGroupVertex
    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex

    @impl Clarity.Introspector
    def source_vertex_types, do: [ResourceVertex]

    @impl Clarity.Introspector
    def introspect_vertex(%ResourceVertex{resource: resource} = resource_vertex, _graph) do
      if uses_ash_grant?(resource) do
        {:ok,
         scope_entries(resource, resource_vertex) ++
           grant_entries(resource, resource_vertex) ++
           field_group_entries(resource, resource_vertex)}
      else
        {:ok, []}
      end
    rescue
      UndefinedFunctionError -> {:ok, []}
    end

    defp uses_ash_grant?(resource) do
      AshGrant in Spark.extensions(resource)
    rescue
      _ -> false
    end

    defp scope_entries(resource, resource_vertex) do
      resource
      |> AshGrant.Info.scopes()
      |> Enum.flat_map(fn scope ->
        owner_kind = scope_owner_kind(resource, scope)
        owner = if owner_kind == :domain, do: Ash.Resource.Info.domain(resource), else: resource

        vertex = %ScopeVertex{owner: owner, owner_kind: owner_kind, scope: scope}
        [{:vertex, vertex}, {:edge, resource_vertex, vertex, :ash_grant_scope}]
      end)
    end

    defp scope_owner_kind(resource, scope) do
      resource_entities =
        resource
        |> Spark.Dsl.Extension.get_entities([:ash_grant])
        |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))

      if Enum.any?(resource_entities, &(&1.name == scope.name)) do
        :resource
      else
        :domain
      end
    end

    defp grant_entries(resource, resource_vertex) do
      resource_grant_names =
        resource
        |> Spark.Dsl.Extension.get_entities([:ash_grant, :grants])
        |> MapSet.new(& &1.name)

      resource
      |> AshGrant.Info.grants()
      |> Enum.flat_map(fn grant ->
        owner_kind = if MapSet.member?(resource_grant_names, grant.name), do: :resource, else: :domain
        owner = if owner_kind == :domain, do: Ash.Resource.Info.domain(resource), else: resource

        vertex = %GrantVertex{owner: owner, owner_kind: owner_kind, grant: grant}
        [{:vertex, vertex}, {:edge, resource_vertex, vertex, :ash_grant_grant}]
      end)
    end

    defp field_group_entries(resource, resource_vertex) do
      resource
      |> AshGrant.Info.field_groups()
      |> Enum.flat_map(fn fg ->
        vertex = %FieldGroupVertex{resource: resource, field_group: fg}
        [{:vertex, vertex}, {:edge, resource_vertex, vertex, :ash_grant_field_group}]
      end)
    end
  end
end
