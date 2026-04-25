with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Content.DomainOverview do
    @moduledoc """
    Static markdown tab on `Clarity.Vertex.Ash.Domain` that summarizes the
    domain-level AshGrant configuration (resolver, scopes, and grants) that
    is inherited by every resource in the domain.
    """

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Domain, as: DomainVertex

    @impl Clarity.Content
    def name, do: "AshGrant Permissions"

    @impl Clarity.Content
    def description, do: "Domain-level resolver, scopes, and grants"

    @impl Clarity.Content
    def sort_priority, do: -50

    @impl Clarity.Content
    def applies?(%DomainVertex{domain: domain}, _lens),
      do: AshGrant.Domain.Info.configured?(domain)

    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%DomainVertex{domain: domain}, _lens) do
      {:markdown, fn _props -> render(domain) end}
    end

    defp render(domain) do
      [
        "# AshGrant Domain Configuration\n\n",
        resolver_section(domain),
        scopes_section(domain),
        grants_section(domain)
      ]
    end

    defp resolver_section(domain) do
      [
        "## Resolver\n\n",
        case AshGrant.Domain.Info.resolver(domain) do
          nil ->
            "*No domain-level resolver — resources provide their own, or grants synthesize one.*\n\n"

          mod when is_atom(mod) ->
            ["`", inspect(mod), "`\n\n"]

          fun when is_function(fun) ->
            ["Anonymous 2-arity function: `", inspect(fun), "`\n\n"]
        end
      ]
    end

    defp scopes_section(domain) do
      case AshGrant.Domain.Info.scopes(domain) do
        [] ->
          []

        scopes ->
          [
            "## Scopes (inherited)\n\n",
            "| Name | Description | Filter |\n",
            "| --- | --- | --- |\n",
            Enum.map(scopes, fn scope ->
              [
                "| `:", Atom.to_string(scope.name), "` | ",
                escape_cell(scope.description || ""), " | `",
                escape_cell(ScopeVertex.render_filter(scope.filter)), "` |\n"
              ]
            end),
            "\n"
          ]
      end
    end

    defp grants_section(domain) do
      case AshGrant.Domain.Info.grants(domain) do
        [] ->
          []

        grants ->
          [
            "## Grants (inherited)\n\n",
            Enum.map(grants, fn grant ->
              [
                "### `:", Atom.to_string(grant.name), "`\n\n",
                case grant.description do
                  desc when is_binary(desc) and desc != "" -> [desc, "\n\n"]
                  _ -> []
                end,
                "**Predicate:** `",
                escape_cell(ScopeVertex.render_filter(grant.predicate)),
                "`\n\n",
                permissions_table(grant.permissions || [])
              ]
            end)
          ]
      end
    end

    defp permissions_table([]), do: "*No permissions declared.*\n\n"

    defp permissions_table(permissions) do
      [
        "| Name | Target | Action | Scope | Deny? |\n",
        "| --- | --- | --- | --- | --- |\n",
        Enum.map(permissions, fn perm ->
          [
            "| `:", Atom.to_string(perm.name), "` | `",
            inspect(perm.on), "` | `",
            perm_atom_or_wild(perm.action), "` | `",
            perm_scope(perm.scope), "` | ",
            if(perm.deny, do: "yes", else: ""), " |\n"
          ]
        end),
        "\n"
      ]
    end

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
