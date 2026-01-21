defmodule AshGrant.PolicyTest.RunnerTest do
  @moduledoc """
  Tests for the PolicyTest runner.
  """
  use ExUnit.Case, async: true

  alias AshGrant.PolicyTest.Runner
  alias AshGrant.PolicyTest.Result

  # Fixture modules from test/support/policy_test_fixtures.ex
  alias AshGrant.PolicyTest.Fixtures.{
    DocumentPolicyTest,
    PostPolicyTest,
    TestWithResource
  }

  describe "run_module/1" do
    test "runs all tests in a module and returns results" do
      results = Runner.run_module(DocumentPolicyTest)

      assert is_list(results)
      assert length(results) > 0

      # All results should be Result structs
      Enum.each(results, fn result ->
        assert %Result{} = result
        assert is_binary(result.test_name)
        assert is_boolean(result.passed)
        assert is_integer(result.duration_us)
      end)
    end

    test "all passing tests return passed: true" do
      results = Runner.run_module(DocumentPolicyTest)

      # All tests in DocumentPolicyTest should pass
      assert Enum.all?(results, & &1.passed)
    end

    test "returns empty list for module with no tests" do
      results = Runner.run_module(TestWithResource)

      assert results == []
    end

    test "captures test names correctly" do
      results = Runner.run_module(DocumentPolicyTest)

      test_names = Enum.map(results, & &1.test_name)

      assert "admin can do anything" in test_names
      assert "reader can read" in test_names
      assert "guest cannot read" in test_names
    end
  end

  describe "run_all/1" do
    test "runs multiple modules and returns summary" do
      summary =
        Runner.run_all(modules: [DocumentPolicyTest, PostPolicyTest])

      assert is_map(summary)
      assert Map.has_key?(summary, :passed)
      assert Map.has_key?(summary, :failed)
      assert Map.has_key?(summary, :results)

      assert summary.passed >= 0
      assert summary.failed >= 0
      assert is_list(summary.results)
    end

    test "counts passed and failed tests correctly" do
      summary =
        Runner.run_all(modules: [DocumentPolicyTest])

      # All DocumentPolicyTest tests should pass
      assert summary.failed == 0
      assert summary.passed == length(summary.results)
    end

    test "includes module name in results" do
      summary =
        Runner.run_all(modules: [DocumentPolicyTest])

      Enum.each(summary.results, fn result ->
        assert result.module == DocumentPolicyTest
      end)
    end
  end

  describe "Result struct" do
    test "has expected fields" do
      result = %Result{
        test_name: "test name",
        passed: true,
        message: nil,
        duration_us: 100
      }

      assert result.test_name == "test name"
      assert result.passed == true
      assert result.message == nil
      assert result.duration_us == 100
    end

    test "message contains error details for failed tests" do
      result = %Result{
        test_name: "failed test",
        passed: false,
        message: "Expected actor to be able to...",
        duration_us: 50
      }

      assert result.passed == false
      assert is_binary(result.message)
    end
  end
end
