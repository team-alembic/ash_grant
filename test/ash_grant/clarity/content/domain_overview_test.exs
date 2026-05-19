if Code.ensure_loaded?(Clarity) do
  defmodule AshGrant.Clarity.Content.DomainOverviewTest do
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Content.DomainOverview
    alias Clarity.Vertex.Ash.Domain, as: DomainVertex

    test "applies? only for AshGrant.Domain-enabled domains" do
      assert DomainOverview.applies?(
               %DomainVertex{domain: AshGrant.Test.GrantsOnlyDomain},
               fake_lens()
             )

      refute DomainOverview.applies?(
               %DomainVertex{domain: AshGrant.Test.Domain},
               fake_lens()
             )
    end

    test "renders grants and scopes sections" do
      vertex = %DomainVertex{domain: AshGrant.Test.GrantsOnlyDomain}

      {:markdown, fun} = DomainOverview.render_static(vertex, fake_lens())

      markdown =
        %{theme: :light, zoom_subgraph: nil, zoom_level: {1, 1}, shown_vertex_types: [], available_vertex_types: []}
        |> fun.()
        |> IO.iodata_to_binary()

      assert markdown =~ "# AshGrant Domain Configuration"
      assert markdown =~ "## Scopes (inherited)"
      assert markdown =~ "## Grants (inherited)"
      assert markdown =~ ":admin"
      assert markdown =~ ":viewer"
    end

    defp fake_lens, do: %{id: "test", content_sorter: fn _, _ -> true end}
  end
end
