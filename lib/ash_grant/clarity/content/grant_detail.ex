with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Content.GrantDetail do
    @moduledoc """
    Static markdown detail page for an `AshGrant.Clarity.Vertex.Grant`,
    listing the grant's predicate and every declared permission.
    """

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.Grant, as: GrantVertex
    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex

    @impl Clarity.Content
    def name, do: "Grant Detail"

    @impl Clarity.Content
    def description, do: "Details of this AshGrant grant"

    @impl Clarity.Content
    def sort_priority, do: -100

    @impl Clarity.Content
    def applies?(%GrantVertex{}, _lens), do: true
    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%GrantVertex{} = vertex, _lens) do
      {:markdown, fn _props -> render(vertex) end}
    end

    defp render(%GrantVertex{owner: owner, owner_kind: kind, grant: grant}) do
      [
        "# Grant `:", Atom.to_string(grant.name), "`\n\n",
        "| Property | Value |\n",
        "| --- | --- |\n",
        "| **Defined on** | ", owner_label(kind), " `", inspect(owner), "` |\n",
        "| **Description** | ", escape_cell(grant.description || ""), " |\n",
        "| **Predicate** | `",
        escape_cell(ScopeVertex.render_filter(grant.predicate)),
        "` |\n\n",
        "## Permissions\n\n",
        permissions_table(grant.permissions || [])
      ]
    end

    defp owner_label(:resource), do: "Resource"
    defp owner_label(:domain), do: "Domain"

    defp permissions_table([]), do: "*No permissions declared.*\n"

    defp permissions_table(permissions) do
      [
        "| Name | Target | Action | Scope | Deny? | Description |\n",
        "| --- | --- | --- | --- | --- | --- |\n",
        Enum.map(permissions, fn perm ->
          [
            "| `:", Atom.to_string(perm.name), "` | `",
            perm_target(perm.on), "` | `",
            perm_atom_or_wild(perm.action), "` | `",
            perm_scope(perm.scope), "` | ",
            if(perm.deny, do: "yes", else: ""), " | ",
            escape_cell(perm.description || ""), " |\n"
          ]
        end),
        "\n"
      ]
    end

    defp perm_target(nil), do: "<self>"
    defp perm_target(module), do: inspect(module)

    defp perm_atom_or_wild(:*), do: "*"
    defp perm_atom_or_wild(atom) when is_atom(atom), do: Atom.to_string(atom)

    defp perm_scope(nil), do: "(unrestricted)"
    defp perm_scope(atom), do: Atom.to_string(atom)

    defp escape_cell(value) when is_binary(value) do
      value
      |> String.replace("|", "\\|")
      |> String.replace("\n", " ")
    end

    defp escape_cell(value), do: escape_cell(to_string(value))
  end
end
