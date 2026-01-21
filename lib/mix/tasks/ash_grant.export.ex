defmodule Mix.Tasks.AshGrant.Export do
  @moduledoc """
  Exports policy configuration to various formats.

  ## Usage

      # Export to YAML
      mix ash_grant.export MyApp.Document --format=yaml

      # Export to Mermaid diagram
      mix ash_grant.export MyApp.Document --format=mermaid

      # Export to Markdown documentation
      mix ash_grant.export MyApp.Document --format=markdown

      # Export to file
      mix ash_grant.export MyApp.Document --format=markdown --output=docs/document.md

  ## Formats

    * `yaml` - YAML policy test format
    * `mermaid` - Mermaid flowchart diagram
    * `markdown` - Human-readable documentation

  ## Options

    * `--format` - Output format (required): yaml, mermaid, markdown
    * `--output` - Write to file instead of stdout
  """

  use Mix.Task

  @shortdoc "Export policy configuration to various formats"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} = OptionParser.parse(args, switches: [format: :string, output: :string])

    case args do
      [resource_name | _] ->
        format = Keyword.get(opts, :format, "yaml")
        output = Keyword.get(opts, :output)

        export_resource(resource_name, format, output)

      [] ->
        Mix.shell().error(
          "Usage: mix ash_grant.export MyApp.Resource --format=yaml|mermaid|markdown"
        )
    end
  end

  defp export_resource(resource_name, format, output) do
    resource = String.to_existing_atom("Elixir." <> resource_name)

    if not AshGrant.Info.configured?(resource) do
      Mix.shell().error("Resource #{resource_name} does not have AshGrant configured")
    else
      content =
        case format do
          "yaml" ->
            export_yaml(resource)

          "mermaid" ->
            AshGrant.PolicyExport.to_mermaid(resource)

          "markdown" ->
            AshGrant.PolicyExport.to_markdown(resource)

          other ->
            Mix.shell().error("Unknown format: #{other}")
            Mix.shell().error("Supported formats: yaml, mermaid, markdown")
            nil
        end

      if content do
        if output do
          File.write!(output, content)
          Mix.shell().info("Exported to #{output}")
        else
          Mix.shell().info(content)
        end
      end
    end
  rescue
    ArgumentError ->
      Mix.shell().error("Resource not found: #{resource_name}")
      Mix.shell().error("Make sure the resource module is compiled and available.")
  end

  defp export_yaml(resource) do
    resource_name = AshGrant.Info.resource_name(resource)
    scopes = AshGrant.Info.scopes(resource)
    actions = Ash.Resource.Info.actions(resource)
    permissions = AshGrant.Introspect.available_permissions(resource)

    """
    # Policy configuration for #{resource_name |> Macro.camelize()}
    resource: #{resource |> Atom.to_string() |> String.replace_prefix("Elixir.", "")}

    # Available scopes
    scopes:
    #{format_scopes_yaml(scopes)}

    # Available actions
    actions:
    #{format_actions_yaml(actions)}

    # Example permission strings
    permissions:
    #{format_permissions_yaml(permissions)}
    """
  end

  defp format_scopes_yaml(scopes) do
    scopes
    |> Enum.map(fn scope ->
      desc = if scope.description, do: " # #{scope.description}", else: ""
      "  - #{scope.name}#{desc}"
    end)
    |> Enum.join("\n")
  end

  defp format_actions_yaml(actions) do
    actions
    |> Enum.map(fn action ->
      "  - name: #{action.name}\n    type: #{action.type}"
    end)
    |> Enum.join("\n")
  end

  defp format_permissions_yaml(permissions) do
    permissions
    |> Enum.take(10)
    |> Enum.map(fn perm ->
      "  - #{perm.permission_string}"
    end)
    |> Enum.join("\n")
  end
end
