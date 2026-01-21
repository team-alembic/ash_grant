defmodule AshGrant.PolicyTest.Runner do
  @moduledoc """
  Executes policy tests and collects results.

  The runner provides two main functions:

  - `run_module/1` - Run all tests in a single module
  - `run_all/1` - Run tests across multiple modules with summary statistics

  ## Examples

      # Run a single module
      results = Runner.run_module(MyApp.PolicyTests.DocumentTest)

      # Run multiple modules
      summary = Runner.run_all(modules: [DocumentTest, PostTest])

      # Run with discovery (finds all policy test modules)
      summary = Runner.run_all(path: "test/policy_tests/")
  """

  alias AshGrant.PolicyTest.Result

  @type summary :: %{
          passed: non_neg_integer(),
          failed: non_neg_integer(),
          results: [Result.t()]
        }

  @doc """
  Runs all tests in a policy test module.

  Returns a list of `Result` structs, one for each test.

  ## Examples

      results = Runner.run_module(MyApp.PolicyTests.DocumentTest)

      Enum.each(results, fn result ->
        if result.passed do
          IO.puts("✓ \#{result.test_name}")
        else
          IO.puts("✗ \#{result.test_name}: \#{result.message}")
        end
      end)
  """
  @spec run_module(module()) :: [Result.t()]
  def run_module(module) do
    tests = module.__policy_test__(:tests)
    context = module.__policy_test__(:context)

    Enum.map(tests, fn test_def ->
      run_single_test(test_def, context)
    end)
  end

  @doc """
  Runs tests across multiple modules and returns a summary.

  ## Options

  - `:modules` - List of modules to run tests from
  - `:path` - Path to directory containing policy test files (discovers modules)

  ## Examples

      # Run specific modules
      summary = Runner.run_all(modules: [DocumentTest, PostTest])

      # Discover and run all policy tests in a directory
      summary = Runner.run_all(path: "test/policy_tests/")

  ## Returns

      %{
        passed: 10,
        failed: 2,
        results: [%Result{}, ...]
      }
  """
  @spec run_all(keyword()) :: summary()
  def run_all(opts) do
    modules = get_modules(opts)

    all_results =
      Enum.flat_map(modules, fn module ->
        module
        |> run_module()
        |> Enum.map(&Map.put(&1, :module, module))
      end)

    passed = Enum.count(all_results, & &1.passed)
    failed = Enum.count(all_results, &(not &1.passed))

    %{
      passed: passed,
      failed: failed,
      results: all_results
    }
  end

  @doc """
  Discovers policy test modules from a path.

  Finds all modules that `use AshGrant.PolicyTest` in the given path.
  """
  @spec discover_modules(String.t()) :: [module()]
  def discover_modules(path) do
    path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.flat_map(&find_policy_test_modules/1)
  end

  # Private functions

  defp run_single_test(test_def, context) do
    test_name = test_def.name
    start_time = System.monotonic_time(:microsecond)

    try do
      test_def.fun.(context)
      duration = System.monotonic_time(:microsecond) - start_time
      Result.pass(test_name, duration)
    rescue
      e in AshGrant.PolicyTest.AssertionError ->
        duration = System.monotonic_time(:microsecond) - start_time
        Result.fail(test_name, e.message, duration)

      e ->
        duration = System.monotonic_time(:microsecond) - start_time
        message = "Unexpected error: #{Exception.message(e)}"
        Result.fail(test_name, message, duration)
    end
  end

  defp get_modules(opts) do
    cond do
      Keyword.has_key?(opts, :modules) ->
        Keyword.fetch!(opts, :modules)

      Keyword.has_key?(opts, :path) ->
        discover_modules(Keyword.fetch!(opts, :path))

      true ->
        raise ArgumentError, "Either :modules or :path option is required"
    end
  end

  defp find_policy_test_modules(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        if String.contains?(content, "use AshGrant.PolicyTest") do
          extract_module_names(content)
        else
          []
        end

      {:error, _} ->
        []
    end
  end

  defp extract_module_names(content) do
    # Find all defmodule declarations
    ~r/defmodule\s+([\w.]+)\s+do/
    |> Regex.scan(content)
    |> Enum.map(fn [_, module_name] ->
      try do
        String.to_existing_atom("Elixir." <> module_name)
      rescue
        ArgumentError -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
