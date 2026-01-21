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
    permissions = get_available_permissions(resource)

    """
    # #{resource_name}

    Policy configuration for the #{resource_name} resource.

    ## Actions

    | Action | Type |
    |--------|------|
    #{generate_actions_table(actions)}

    ## Scopes

    | Scope | Description |
    |-------|-------------|
    #{generate_scopes_table(scopes)}

    ## Permissions

    Available permission strings for this resource:

    #{generate_permissions_list(permissions)}
    """
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

  defp get_available_permissions(resource) do
    AshGrant.Introspect.available_permissions(resource)
  end

  defp generate_actions_table(actions) do
    actions
    |> Enum.map(fn action ->
      "| #{action.name} | #{action.type} |"
    end)
    |> Enum.join("\n")
  end

  defp generate_scopes_table(scopes) do
    scopes
    |> Enum.map(fn scope ->
      description = scope.description || "-"
      "| #{scope.name} | #{description} |"
    end)
    |> Enum.join("\n")
  end

  defp generate_permissions_list(permissions) do
    permissions
    |> Enum.group_by(& &1.action)
    |> Enum.map(fn {action, perms} ->
      perm_strings =
        perms
        |> Enum.map(& &1.permission_string)
        |> Enum.map(&"  - `#{&1}`")
        |> Enum.join("\n")

      "### #{action}\n\n#{perm_strings}"
    end)
    |> Enum.join("\n\n")
  end
end
