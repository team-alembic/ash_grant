if Code.ensure_loaded?(Clarity) do
  defmodule AshGrant.Clarity.Introspector.ResourceTest do
    @moduledoc """
    Verifies that the resource introspector emits scope, grant, and field
    group vertices for an AshGrant-enabled resource and remains a no-op for
    resources without the extension.
    """
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Introspector.Resource, as: ResourceIntrospector
    alias AshGrant.Clarity.Vertex.FieldGroup, as: FieldGroupVertex
    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex

    test "source_vertex_types lists Ash.Resource" do
      assert ResourceIntrospector.source_vertex_types() == [ResourceVertex]
    end

    test "emits a Scope vertex per declared scope with an ash_grant_scope edge" do
      vertex = %ResourceVertex{resource: AshGrant.Test.IdLoadablePost}

      assert {:ok, entries} = ResourceIntrospector.introspect_vertex(vertex, :unused_graph)

      scope_entries = Enum.filter(entries, &match?({:vertex, %ScopeVertex{}}, &1))
      edge_labels = for {:edge, _, _, label} <- entries, label == :ash_grant_scope, do: label

      assert length(scope_entries) == 2
      assert length(edge_labels) == 2

      scope_names =
        for {:vertex, %ScopeVertex{scope: scope}} <- scope_entries, do: scope.name

      assert :always in scope_names
      assert :own in scope_names
    end

    test "emits Grant vertices for resources that declare grants" do
      vertex = %ResourceVertex{resource: AshGrant.Test.GrantsPost}

      assert {:ok, entries} = ResourceIntrospector.introspect_vertex(vertex, :unused_graph)

      grant_vertices =
        for {:vertex, %GrantVertex{} = gv} <- entries, do: gv

      assert grant_vertices != []
      Enum.each(grant_vertices, fn gv -> assert gv.owner_kind in [:resource, :domain] end)
    end

    test "emits FieldGroup vertices for resources that declare field_groups" do
      vertex = %ResourceVertex{resource: AshGrant.Test.SensitiveRecord}

      assert {:ok, entries} = ResourceIntrospector.introspect_vertex(vertex, :unused_graph)

      field_groups =
        for {:vertex, %FieldGroupVertex{} = fg} <- entries, do: fg

      assert field_groups != []
    end

    test "returns {:ok, []} for resources without AshGrant" do
      vertex = %ResourceVertex{resource: String}

      assert {:ok, []} =
               ResourceIntrospector.introspect_vertex(vertex, :unused_graph)
    end
  end
end
