with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Content.ScopeDetail do
    @moduledoc """
    Static markdown detail page for an `AshGrant.Clarity.Vertex.Scope`.
    """

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex

    @impl Clarity.Content
    def name, do: "Scope Detail"

    @impl Clarity.Content
    def description, do: "Details of this AshGrant scope"

    @impl Clarity.Content
    def sort_priority, do: -100

    @impl Clarity.Content
    def applies?(%ScopeVertex{}, _lens), do: true
    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%ScopeVertex{} = vertex, _lens) do
      {:markdown, fn _props -> render(vertex) end}
    end

    defp render(%ScopeVertex{owner: owner, owner_kind: kind, scope: scope}) do
      [
        "# Scope `:", Atom.to_string(scope.name), "`\n\n",
        "| Property | Value |\n",
        "| --- | --- |\n",
        "| **Defined on** | ", owner_label(kind), " `", inspect(owner), "` |\n",
        "| **Description** | ", escape_cell(scope.description || ""), " |\n",
        "| **Filter** | `", escape_cell(ScopeVertex.render_filter(scope.filter)), "` |\n",
        write_row(scope),
        "\n"
      ]
    end

    defp owner_label(:resource), do: "Resource"
    defp owner_label(:domain), do: "Domain"

    defp write_row(%{write: nil}), do: []

    defp write_row(%{write: write}) do
      [
        "| **Write (deprecated)** | `",
        escape_cell(ScopeVertex.render_filter(write)),
        "` |\n"
      ]
    end

    defp escape_cell(value) when is_binary(value) do
      value
      |> String.replace("|", "\\|")
      |> String.replace("\n", " ")
    end

    defp escape_cell(value), do: escape_cell(to_string(value))
  end
end
