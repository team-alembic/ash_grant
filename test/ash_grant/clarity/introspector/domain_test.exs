if Code.ensure_loaded?(Clarity) do
  defmodule AshGrant.Clarity.Introspector.DomainTest do
    @moduledoc """
    Verifies that the domain introspector emits scope and grant vertices only
    for domains that use the `AshGrant.Domain` extension.
    """
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Introspector.Domain, as: DomainIntrospector
    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Domain, as: DomainVertex

    test "source_vertex_types lists Ash.Domain" do
      assert DomainIntrospector.source_vertex_types() == [DomainVertex]
    end

    test "emits Scope vertices for domain-level scopes" do
      vertex = %DomainVertex{domain: AshGrant.Test.ScopesOnlyDomain}

      assert {:ok, entries} = DomainIntrospector.introspect_vertex(vertex, :unused_graph)

      scope_vertices =
        for {:vertex, %ScopeVertex{} = sv} <- entries, do: sv

      assert scope_vertices != []
      Enum.each(scope_vertices, fn sv -> assert sv.owner_kind == :domain end)
    end

    test "emits Grant vertices for domains with grants" do
      vertex = %DomainVertex{domain: AshGrant.Test.GrantsOnlyDomain}

      assert {:ok, entries} = DomainIntrospector.introspect_vertex(vertex, :unused_graph)

      grants =
        for {:vertex, %GrantVertex{} = gv} <- entries, do: gv

      assert grants != []
      Enum.each(grants, fn gv -> assert gv.owner_kind == :domain end)
    end

    test "returns {:ok, []} for domains without AshGrant.Domain" do
      vertex = %DomainVertex{domain: AshGrant.Test.Domain}

      assert {:ok, []} = DomainIntrospector.introspect_vertex(vertex, :unused_graph)
    end
  end
end
