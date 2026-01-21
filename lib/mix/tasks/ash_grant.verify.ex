defmodule Mix.Tasks.AshGrant.Verify do
  @moduledoc """
  Runs policy configuration tests.

  ## Usage

      # Run all policy tests in default location
      mix ash_grant.verify

      # Run tests from specific directory
      mix ash_grant.verify test/policy_tests/

      # Run tests from a YAML file
      mix ash_grant.verify priv/policy_tests/document.yaml

      # Run with verbose output
      mix ash_grant.verify --verbose

  ## Options

    * `--verbose` - Show detailed output for each test
    * `--format` - Output format: text (default), json

  ## Exit Codes

    * 0 - All tests passed
    * 1 - One or more tests failed
  """

  use Mix.Task

  @shortdoc "Run policy configuration tests"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, args, _} = OptionParser.parse(args, switches: [verbose: :boolean, format: :string])

    verbose = Keyword.get(opts, :verbose, false)
    format = Keyword.get(opts, :format, "text")

    results = run_tests(args, verbose)

    output_results(results, format, verbose)

    if results.failed > 0 do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  defp run_tests([], verbose) do
    # Default: discover policy test modules
    if verbose, do: Mix.shell().info("Discovering policy test modules...")

    modules = discover_modules()

    if modules == [] do
      Mix.shell().info("No policy test modules found.")
      %{passed: 0, failed: 0, results: []}
    else
      if verbose do
        Mix.shell().info("Found #{length(modules)} module(s)")
      end

      AshGrant.PolicyTest.Runner.run_all(modules: modules)
    end
  end

  defp run_tests([path | _], verbose) do
    cond do
      String.ends_with?(path, ".yaml") or String.ends_with?(path, ".yml") ->
        run_yaml_tests(path, verbose)

      File.dir?(path) ->
        run_directory_tests(path, verbose)

      String.ends_with?(path, ".ex") or String.ends_with?(path, ".exs") ->
        run_file_tests(path, verbose)

      true ->
        Mix.shell().error("Unknown path type: #{path}")
        %{passed: 0, failed: 0, results: []}
    end
  end

  defp run_yaml_tests(path, verbose) do
    if verbose, do: Mix.shell().info("Running YAML tests from: #{path}")

    case AshGrant.PolicyTest.YamlParser.run_yaml_tests(path) do
      {:ok, results} ->
        passed = Enum.count(results, & &1.passed)
        failed = Enum.count(results, &(not &1.passed))
        %{passed: passed, failed: failed, results: results}

      {:error, reason} ->
        Mix.shell().error("Failed to parse YAML: #{inspect(reason)}")
        %{passed: 0, failed: 0, results: []}
    end
  end

  defp run_directory_tests(path, verbose) do
    if verbose, do: Mix.shell().info("Running tests from directory: #{path}")

    modules = AshGrant.PolicyTest.Runner.discover_modules(path)

    if modules == [] do
      Mix.shell().info("No policy test modules found in #{path}")
      %{passed: 0, failed: 0, results: []}
    else
      AshGrant.PolicyTest.Runner.run_all(modules: modules)
    end
  end

  defp run_file_tests(path, verbose) do
    if verbose, do: Mix.shell().info("Running tests from file: #{path}")

    # Compile the file and find policy test modules
    Code.compile_file(path)

    modules = AshGrant.PolicyTest.Runner.discover_modules(Path.dirname(path))

    if modules == [] do
      Mix.shell().info("No policy test modules found in #{path}")
      %{passed: 0, failed: 0, results: []}
    else
      AshGrant.PolicyTest.Runner.run_all(modules: modules)
    end
  end

  defp discover_modules do
    # Look in common locations
    paths = ["test/policy_tests", "priv/policy_tests"]

    paths
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(&AshGrant.PolicyTest.Runner.discover_modules/1)
  end

  defp output_results(results, "json", _verbose) do
    json =
      %{
        passed: results.passed,
        failed: results.failed,
        tests:
          Enum.map(results.results, fn r ->
            %{
              name: r.test_name,
              passed: r.passed,
              message: r.message,
              duration_us: r.duration_us
            }
          end)
      }
      |> Jason.encode!(pretty: true)

    Mix.shell().info(json)
  end

  defp output_results(results, _format, verbose) do
    if verbose do
      Enum.each(results.results, fn result ->
        if result.passed do
          Mix.shell().info("  ✓ #{result.test_name}")
        else
          Mix.shell().error("  ✗ #{result.test_name}")
          Mix.shell().error("    #{result.message}")
        end
      end)

      Mix.shell().info("")
    end

    total = results.passed + results.failed

    if results.failed == 0 do
      Mix.shell().info("#{results.passed} test(s) passed")
    else
      Mix.shell().error("#{results.failed}/#{total} test(s) failed")
    end
  end
end
