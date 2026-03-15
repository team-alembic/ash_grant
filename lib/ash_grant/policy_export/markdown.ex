defmodule AshGrant.PolicyExport.Markdown do
  @moduledoc """
  Generates Markdown documentation for policy configuration.

  The generated documentation includes:
  - Resource overview
  - Actions table with types
  - Scopes table with descriptions
  - Available permissions list
  """

  @doc """
  Generates Markdown documentation for a resource's policy.
  """
  @spec generate(module()) :: String.t()
  def generate(resource) do
    resource_name = get_resource_name(resource)
    actions = get_actions(resource)
    scopes = get_scopes(resource)
    field_groups = get_field_groups(resource)
    permissions = get_available_permissions(resource)

    sections = [
      "# #{resource_name}",
      "",
      "Policy configuration for the #{resource_name} resource.",
      "",
      "## Actions",
      "",
      "| Action | Type |",
      "|--------|------|",
      generate_actions_table(actions),
      "",
      "## Scopes",
      "",
      "| Scope | Description |",
      "|-------|-------------|",
      generate_scopes_table(scopes),
      if(field_groups != [], do: generate_field_groups_section(field_groups), else: nil),
      "",
      "## Permissions",
      "",
      "Available permission strings for this resource:",
      "",
      generate_permissions_list(permissions)
    ]

    sections
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> String.trim()
  end

  # Private functions

  defp get_resource_name(resource) do
    AshGrant.Info.resource_name(resource)
    |> Macro.camelize()
  end

  defp get_actions(resource) do
    Ash.Resource.Info.actions(resource)
    |> Enum.map(fn action ->
      %{name: action.name, type: action.type}
    end)
  end

  defp get_scopes(resource) do
    AshGrant.Info.scopes(resource)
    |> Enum.map(fn scope ->
      %{name: scope.name, description: scope.description || "-"}
    end)
  end

  defp get_field_groups(resource) do
    AshGrant.Info.field_groups(resource)
    |> Enum.map(fn fg ->
      inherits =
        if fg.inherits && fg.inherits != [],
          do: Enum.map_join(fg.inherits, ", ", &to_string/1),
          else: "-"

      masking =
        if fg.mask && fg.mask != [],
          do: Enum.map_join(fg.mask, ", ", &to_string/1),
          else: "-"

      %{
        name: fg.name,
        fields: Enum.map_join(fg.fields, ", ", &to_string/1),
        inherits: inherits,
        masking: masking
      }
    end)
  end

  defp get_available_permissions(resource) do
    AshGrant.Introspect.available_permissions(resource)
  end

  defp generate_actions_table(actions) do
    Enum.map_join(actions, "\n", fn action ->
      "| #{action.name} | #{action.type} |"
    end)
  end

  defp generate_scopes_table(scopes) do
    Enum.map_join(scopes, "\n", fn scope ->
      description = scope.description || "-"
      "| #{scope.name} | #{description} |"
    end)
  end

  defp generate_field_groups_section(field_groups) do
    rows =
      Enum.map_join(field_groups, "\n", fn fg ->
        "| #{fg.name} | #{fg.fields} | #{fg.inherits} | #{fg.masking} |"
      end)

    [
      "",
      "## Field Groups",
      "",
      "| Group | Fields | Inherits | Masking |",
      "|-------|--------|----------|---------|",
      rows
    ]
  end

  defp generate_permissions_list(permissions) do
    permissions
    |> Enum.group_by(& &1.action)
    |> Enum.map_join("\n\n", fn {action, perms} ->
      perm_strings =
        Enum.map_join(perms, "\n", fn p -> "  - `#{p.permission_string}`" end)

      "### #{action}\n\n#{perm_strings}"
    end)
  end
end
