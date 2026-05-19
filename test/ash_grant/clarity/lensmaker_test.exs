if Code.ensure_loaded?(Clarity) do
  defmodule AshGrant.Clarity.LensmakerTest do
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Lensmaker
    alias AshGrant.Clarity.Vertex.FieldGroup, as: FieldGroupVertex
    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Perspective.Lens
    alias Clarity.Vertex

    test "make_lens returns a Permissions lens" do
      assert %Lens{id: "permissions", name: "Permissions"} = Lensmaker.make_lens()
    end

    test "permissions lens show_vertex_types admits AshGrant + core Ash vertex types" do
      %Lens{show_vertex_types: fun} = Lensmaker.make_lens()

      available = [
        Vertex.Application,
        Vertex.Ash.Resource,
        Vertex.Ash.Domain,
        Vertex.Ash.Action,
        Vertex.Ash.Attribute,
        ScopeVertex,
        GrantVertex,
        FieldGroupVertex
      ]

      admitted = fun.(available)

      assert Vertex.Ash.Resource in admitted
      assert ScopeVertex in admitted
      assert GrantVertex in admitted
      assert FieldGroupVertex in admitted
      refute Vertex.Ash.Attribute in admitted
    end

    test "update_lens enhances the security lens to include AshGrant vertex types" do
      security_lens = %Lens{
        id: "security",
        name: "Security",
        icon: fn -> nil end,
        filter: true,
        show_vertex_types: fn available ->
          Enum.filter(available, &(&1 in [Vertex.Application, Vertex.Ash.Resource]))
        end
      }

      %Lens{show_vertex_types: enhanced} = Lensmaker.update_lens(security_lens)

      available = [
        Vertex.Application,
        Vertex.Ash.Resource,
        Vertex.Ash.Attribute,
        ScopeVertex,
        GrantVertex
      ]

      admitted = enhanced.(available)

      assert Vertex.Application in admitted
      assert Vertex.Ash.Resource in admitted
      assert ScopeVertex in admitted
      assert GrantVertex in admitted
      refute Vertex.Ash.Attribute in admitted
    end

    test "update_lens leaves unrelated lenses unchanged" do
      other = %Lens{
        id: "custom",
        name: "Custom",
        icon: fn -> nil end,
        filter: true,
        show_vertex_types: &Function.identity/1
      }

      assert Lensmaker.update_lens(other) == other
    end
  end
end
