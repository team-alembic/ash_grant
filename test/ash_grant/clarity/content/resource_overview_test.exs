if Code.ensure_loaded?(Clarity) do
  defmodule AshGrant.Clarity.Content.ResourceOverviewTest do
    @moduledoc """
    Static markdown generation for the AshGrant Resource Overview content
    provider. Covers the `applies?/2` guard and the presence of the key
    sections (resolver, scopes, available permissions).
    """
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Content.ResourceOverview
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex

    test "applies? is true for AshGrant-enabled resources" do
      vertex = %ResourceVertex{resource: AshGrant.Test.IdLoadablePost}

      assert ResourceOverview.applies?(vertex, fake_lens())
    end

    test "applies? is false for resources without the extension" do
      vertex = %ResourceVertex{resource: String}

      refute ResourceOverview.applies?(vertex, fake_lens())
    end

    test "renders a markdown document with resolver and scopes sections" do
      vertex = %ResourceVertex{resource: AshGrant.Test.IdLoadablePost}

      {:markdown, fun} = ResourceOverview.render_static(vertex, fake_lens())
      assert is_function(fun, 1)

      markdown =
        %{theme: :light, zoom_subgraph: nil, zoom_level: {1, 1}, shown_vertex_types: [], available_vertex_types: []}
        |> fun.()
        |> IO.iodata_to_binary()

      assert markdown =~ "# AshGrant Configuration"
      assert markdown =~ "## Resolver"
      assert markdown =~ "AshGrant.Test.IdLoadableResolver"
      assert markdown =~ "## Scopes"
      assert markdown =~ ":own"
      assert markdown =~ ":always"
      assert markdown =~ "## Available Permission Strings"
      assert markdown =~ "id_loadable_post:*:read:always"
    end

    defp fake_lens do
      %{id: "test", content_sorter: fn _, _ -> true end}
    end
  end
end
