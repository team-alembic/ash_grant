defmodule AshGrant.PolicyTest.YamlExporter do
  @moduledoc """
  Exports policy test modules to YAML format.

  This allows converting Elixir DSL policy tests to YAML for:
  - Documentation purposes
  - Sharing with non-Elixir developers
  - External tool integration

  ## Examples

      yaml = YamlExporter.export(MyApp.PolicyTests.DocumentTest)
      File.write!("document_tests.yaml", yaml)
  """

  @doc """
  Exports a policy test module to YAML format.
  """
  @spec export(module()) :: String.t()
  def export(module) do
    resource = module.__policy_test__(:resource)
    actors = module.__policy_test__(:actors)
    tests = module.__policy_test__(:tests)

    yaml_map = %{
      "resource" => module_to_string(resource),
      "actors" => export_actors(actors),
      "tests" => export_tests(tests)
    }

    to_yaml(yaml_map)
  end

  # Private functions

  defp module_to_string(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp export_actors(actors) do
    actors
    |> Enum.map(fn {name, attrs} ->
      {Atom.to_string(name), stringify_map(attrs)}
    end)
    |> Enum.into(%{})
  end

  defp export_tests(tests) do
    Enum.map(tests, &export_test/1)
  end

  defp export_test(%{type: type, fields: fields} = test)
       when type in [:assert_fields_visible, :assert_fields_hidden] do
    assertion_key = Atom.to_string(type)

    assertion = %{
      "actor" => Atom.to_string(test.actor),
      "action" => Atom.to_string(test.action),
      "fields" => Enum.map(fields, &Atom.to_string/1)
    }

    %{
      "name" => test.name,
      assertion_key => assertion
    }
  end

  defp export_test(test) do
    # Analyze test body to determine assertion type and parameters
    # This is a simplified version - in reality, we'd need to inspect
    # the test body AST to extract assertion details

    # For now, we'll create a placeholder that shows the test name
    # A full implementation would need to analyze the test function body
    %{
      "name" => test.name,
      "assert_can" => %{
        "actor" => "unknown",
        "action" => "unknown"
      }
    }
  end

  defp stringify_map(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      {stringify_key(k), stringify_value(v)}
    end)
    |> Enum.into(%{})
  end

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key), do: key

  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(value), do: value

  defp to_yaml(map) do
    if Code.ensure_loaded?(YamlElixir) do
      # YamlElixir doesn't have a write function, so we'll format manually
      format_yaml(map, 0)
    else
      raise "YamlElixir is not available. Add {:yaml_elixir, \"~> 2.9\"} to your dependencies."
    end
  end

  defp format_yaml(map, indent) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      indent_str = String.duplicate("  ", indent)
      "#{indent_str}#{key}:#{format_yaml_value(value, indent)}"
    end)
    |> Enum.join("\n")
  end

  defp format_yaml_value(value, indent) when is_map(value) do
    "\n" <> format_yaml(value, indent + 1)
  end

  defp format_yaml_value(value, indent) when is_list(value) do
    items =
      Enum.map(value, fn item ->
        format_list_item_with_indent(item, indent + 1)
      end)
      |> Enum.join("\n")

    "\n" <> items
  end

  defp format_yaml_value(value, _indent) when is_binary(value) do
    if String.contains?(value, "\n") or String.contains?(value, ":") do
      " \"#{String.replace(value, "\"", "\\\"")}\""
    else
      " #{value}"
    end
  end

  defp format_yaml_value(value, _indent) do
    " #{value}"
  end

  defp format_list_item_with_indent(item, indent) when is_map(item) do
    indent_str = String.duplicate("  ", indent)
    # For map items in a list, first key goes on same line as `-`
    [{first_key, first_val} | rest] = Enum.to_list(item)

    first_line = "#{indent_str}- #{first_key}:#{format_yaml_value(first_val, indent + 1)}"

    if rest == [] do
      first_line
    else
      rest_lines =
        rest
        |> Enum.map(fn {k, v} ->
          "#{indent_str}  #{k}:#{format_yaml_value(v, indent + 1)}"
        end)
        |> Enum.join("\n")

      first_line <> "\n" <> rest_lines
    end
  end

  defp format_list_item_with_indent(item, indent) do
    indent_str = String.duplicate("  ", indent)
    "#{indent_str}- #{item}"
  end
end
