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
    field_groups = get_field_groups(resource)

    lines = [
      "flowchart TD",
      "  #{resource_name}[#{resource_name}]",
      "",
      "  %% Actions",
      generate_action_connections(resource_name, actions),
      "",
      "  %% Action-Scope connections",
      generate_action_scope_connections(actions, scopes),
      if(field_groups != [],
        do: [
          "",
          "  %% Field Groups",
          generate_field_group_connections(resource_name, field_groups)
        ],
        else: []
      )
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

  defp get_field_groups(resource) do
    AshGrant.Info.field_groups(resource)
    |> Enum.map(fn fg ->
      %{name: fg.name, fields: fg.fields, inherits: fg.inherits || []}
    end)
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

  defp generate_field_group_connections(resource_name, field_groups) do
    # Create field group nodes and inheritance connections
    group_nodes =
      field_groups
      |> Enum.map(fn fg ->
        fg_id = "fg_#{sanitize_id(fg.name)}"
        fields_str = fg.fields |> Enum.map(&to_string/1) |> Enum.join(", ")
        "  #{resource_name} -.-> #{fg_id}{{\"#{fg.name}: #{fields_str}\"}}"
      end)

    inheritance_connections =
      field_groups
      |> Enum.flat_map(fn fg ->
        Enum.map(fg.inherits, fn parent ->
          child_id = "fg_#{sanitize_id(fg.name)}"
          parent_id = "fg_#{sanitize_id(parent)}"
          "  #{parent_id} --> #{child_id}"
        end)
      end)

    group_nodes ++ inheritance_connections
  end

  defp sanitize_id(name) when is_atom(name), do: sanitize_id(Atom.to_string(name))

  defp sanitize_id(name) when is_binary(name) do
    name
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end
end
