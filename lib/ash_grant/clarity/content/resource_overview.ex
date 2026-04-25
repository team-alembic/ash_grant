with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Content.ResourceOverview do
    @moduledoc """
    Static markdown tab on `Clarity.Vertex.Ash.Resource` that summarizes the
    AshGrant configuration for a resource: resolver, scopes, grants, field
    groups, and the flat list of permission strings an admin UI could offer.
    """

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex

    @impl Clarity.Content
    def name, do: "AshGrant Permissions"

    @impl Clarity.Content
    def description, do: "Scopes, grants, field groups, and available permissions"

    @impl Clarity.Content
    def sort_priority, do: -50

    @impl Clarity.Content
    def applies?(%ResourceVertex{resource: resource}, _lens), do: uses_ash_grant?(resource)
    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%ResourceVertex{resource: resource}, _lens) do
      {:markdown, fn _props -> render(resource) end}
    end

    defp uses_ash_grant?(resource) do
      AshGrant in Spark.extensions(resource)
    rescue
      _ -> false
    end

    defp render(resource) do
      [
        header(resource),
        resolver_section(resource),
        scopes_section(resource),
        grants_section(resource),
        field_groups_section(resource),
        available_permissions_section(resource)
      ]
    end

    defp header(resource) do
      [
        "# AshGrant Configuration\n\n",
        "| Property | Value |\n",
        "| --- | --- |\n",
        "| **Resource** | `", inspect(resource), "` |\n",
        "| **Resource name** | `", AshGrant.Info.resource_name(resource), "` |\n",
        "| **Instance key** | `", inspect(AshGrant.Info.instance_key(resource)), "` |\n",
        "| **Default policies** | `", inspect(AshGrant.Info.default_policies(resource)), "` |\n",
        "| **Default field policies** | `", inspect(AshGrant.Info.default_field_policies(resource)), "` |\n\n"
      ]
    end

    defp resolver_section(resource) do
      resolver = AshGrant.Info.resolver(resource)

      [
        "## Resolver\n\n",
        case resolver do
          nil -> "*No resolver configured.*\n\n"
          mod when is_atom(mod) -> ["`", inspect(mod), "`\n\n"]
          fun when is_function(fun) -> ["Anonymous 2-arity function: `", inspect(fun), "`\n\n"]
        end
      ]
    end

    defp scopes_section(resource) do
      case AshGrant.Info.scopes(resource) do
        [] ->
          []

        scopes ->
          [
            "## Scopes\n\n",
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

    defp grants_section(resource) do
      case AshGrant.Info.grants(resource) do
        [] ->
          []

        grants ->
          [
            "## Grants\n\n",
            Enum.map(grants, fn grant ->
              [
                "### `:", Atom.to_string(grant.name), "`\n\n",
                case grant.description do
                  desc when is_binary(desc) and desc != "" -> [desc, "\n\n"]
                  _ -> []
                end,
                "**Predicate:** `", escape_cell(ScopeVertex.render_filter(grant.predicate)), "`\n\n",
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
            perm_target(perm.on), "` | `",
            perm_atom_or_wild(perm.action), "` | `",
            perm_scope(perm.scope), "` | ",
            if(perm.deny, do: "yes", else: ""), " |\n"
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

    defp field_groups_section(resource) do
      case AshGrant.Info.field_groups(resource) do
        [] ->
          []

        groups ->
          [
            "## Field Groups\n\n",
            "| Name | Fields | Inherits | Description |\n",
            "| --- | --- | --- | --- |\n",
            Enum.map(groups, fn fg ->
              [
                "| `:", Atom.to_string(fg.name), "` | ",
                format_fields(fg), " | ",
                format_inherits(fg.inherits), " | ",
                escape_cell(fg.description || ""), " |\n"
              ]
            end),
            "\n"
          ]
      end
    end

    defp format_fields(%{fields: :all, except: except}) when is_list(except) and except != [] do
      [":all except ", Enum.map_join(except, ", ", &("`:" <> Atom.to_string(&1) <> "`"))]
    end

    defp format_fields(%{fields: :all}), do: ":all"

    defp format_fields(%{fields: fields}) when is_list(fields) do
      Enum.map_join(fields, ", ", &("`:" <> Atom.to_string(&1) <> "`"))
    end

    defp format_fields(_), do: ""

    defp format_inherits(nil), do: ""
    defp format_inherits([]), do: ""

    defp format_inherits(list) when is_list(list) do
      Enum.map_join(list, ", ", &("`:" <> Atom.to_string(&1) <> "`"))
    end

    defp available_permissions_section(resource) do
      permissions = AshGrant.Introspect.available_permissions(resource)

      case permissions do
        [] ->
          []

        perms ->
          [
            "## Available Permission Strings\n\n",
            "These are all permission strings that a resolver could grant for this resource.\n\n",
            Enum.map(perms, fn p -> ["- `", p.permission_string, "`\n"] end),
            "\n"
          ]
      end
    end

    defp escape_cell(value) when is_binary(value) do
      value
      |> String.replace("|", "\\|")
      |> String.replace("\n", " ")
    end

    defp escape_cell(value), do: escape_cell(to_string(value))
  end
end
