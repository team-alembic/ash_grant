defmodule Mix.Tasks.AshGrant.Import do
  @moduledoc """
  Imports YAML policy tests and generates Elixir DSL code.

  ## Usage

      # Generate DSL from YAML (output to stdout)
      mix ash_grant.import priv/policy_tests/document.yaml

      # Generate and write to file
      mix ash_grant.import priv/policy_tests/document.yaml --output=test/policy_tests/document_test.exs

  ## Options

    * `--output` - Write generated code to file instead of stdout
    * `--module` - Override the generated module name
  """

  use Mix.Task

  @shortdoc "Import YAML policy tests and generate Elixir DSL"

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, switches: [output: :string, module: :string])

    case args do
      [yaml_path | _] ->
        output = Keyword.get(opts, :output)
        module_name = Keyword.get(opts, :module)

        import_yaml(yaml_path, output, module_name)

      [] ->
        Mix.shell().error("Usage: mix ash_grant.import path/to/policy.yaml [--output=file.exs]")
    end
  end

  defp import_yaml(yaml_path, output, module_name) do
    if File.exists?(yaml_path) do
      code =
        if module_name do
          # Generate with custom module name
          {:ok, parsed} = AshGrant.PolicyTest.YamlParser.parse_file(yaml_path)

          AshGrant.PolicyTest.DslGenerator.generate_from_parsed(parsed, nil)
          |> String.replace(~r/defmodule \w+/, "defmodule #{module_name}")
        else
          AshGrant.PolicyTest.DslGenerator.generate(yaml_path)
        end

      if output do
        # Ensure directory exists
        output |> Path.dirname() |> File.mkdir_p!()

        File.write!(output, code)
        Mix.shell().info("Generated #{output}")
      else
        Mix.shell().info(code)
      end
    else
      Mix.shell().error("File not found: #{yaml_path}")
    end
  rescue
    e ->
      Mix.shell().error("Failed to import YAML: #{Exception.message(e)}")
  end
end
