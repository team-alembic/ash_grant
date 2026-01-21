defmodule AshGrant.PolicyExport.Mermaid do
  @moduledoc """
  Generates Mermaid flowchart diagrams for policy visualization.

  Mermaid diagrams can be rendered in:
  - GitHub markdown
  - GitLab markdown
  - Documentation tools
  - Online editors (mermaid.live)

  ## Example Output

      flowchart TD
        Document[Document]
        Document --> read
        Document --> create
        Document --> update
        Document --> destroy

        read --> all
        read --> draft
        read --> approved
        update --> draft
        update --> pending_review
  """

  @doc """
  Generates a Mermaid flowchart for a resource's policy.
  """
  @spec generate(module()) :: String.t()
  def generate(resource) do
    resource_name = get_resource_name(resource)
    actions = get_actions(resource)
    scopes = get_scopes(resource)

    lines = [
      "flowchart TD",
      "  #{resource_name}[#{resource_name}]",
      "",
      "  %% Actions",
      generate_action_connections(resource_name, actions),
      "",
      "  %% Action-Scope connections",
      generate_action_scope_connections(actions, scopes)
    ]

    lines
    |> List.flatten()
    |> Enum.join("\n")
  end

  # Private functions

  defp get_resource_name(resource) do
    AshGrant.Info.resource_name(resource)
    |> Macro.camelize()
  end

  defp get_actions(resource) do
    Ash.Resource.Info.actions(resource)
    |> Enum.map(fn action -> %{name: action.name, type: action.type} end)
  end

  defp get_scopes(resource) do
    AshGrant.Info.scopes(resource)
    |> Enum.map(fn scope -> %{name: scope.name, description: scope.description} end)
  end

  defp generate_action_connections(resource_name, actions) do
    actions
    |> Enum.map(fn action ->
      action_id = sanitize_id(action.name)
      "  #{resource_name} --> #{action_id}[#{action.name}]"
    end)
  end

  defp generate_action_scope_connections(actions, scopes) do
    # Create connections based on action types
    # Read actions connect to all scopes
    # Write actions connect to relevant scopes

    read_actions = Enum.filter(actions, &(&1.type == :read))
    write_actions = Enum.filter(actions, &(&1.type in [:create, :update, :destroy]))

    read_connections =
      for action <- read_actions,
          scope <- scopes do
        action_id = sanitize_id(action.name)
        scope_id = sanitize_id(scope.name)
        "  #{action_id} --> #{scope_id}((#{scope.name}))"
      end

    write_connections =
      for action <- write_actions,
          scope <- scopes do
        action_id = sanitize_id(action.name)
        scope_id = "#{action_id}_#{sanitize_id(scope.name)}"
        "  #{action_id} -.-> #{scope_id}((#{scope.name}))"
      end

    read_connections ++ write_connections
  end

  defp sanitize_id(name) when is_atom(name), do: sanitize_id(Atom.to_string(name))

  defp sanitize_id(name) when is_binary(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end
end
