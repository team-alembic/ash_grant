defmodule AshGrant.PolicyTest.AssertionsTest do
  @moduledoc """
  Tests for the PolicyTest assertion macros.
  """
  use ExUnit.Case, async: true

  # Fixture modules are defined in test/support/policy_test_fixtures.ex
  alias AshGrant.PolicyTest.Fixtures.{DocumentPolicyTest, PostPolicyTest}

  describe "assert_can/2 without record" do
    test "passes when actor has permission" do
      result = run_test(DocumentPolicyTest, "admin can do anything")
      assert result == :ok
    end

    test "passes when actor can read" do
      result = run_test(DocumentPolicyTest, "reader can read")
      assert result == :ok
    end

    test "raises when actor lacks permission" do
      assert_raise AshGrant.PolicyTest.AssertionError, fn ->
        AshGrant.PolicyTest.Assertions.do_assert_can(
          DocumentPolicyTest,
          :guest,
          :read,
          nil
        )
      end
    end
  end

  describe "assert_cannot/2 without record" do
    test "passes when actor lacks permission" do
      result = run_test(DocumentPolicyTest, "guest cannot read")
      assert result == :ok
    end

    test "raises when actor has permission" do
      assert_raise AshGrant.PolicyTest.AssertionError, fn ->
        AshGrant.PolicyTest.Assertions.do_assert_cannot(
          DocumentPolicyTest,
          :admin,
          :read,
          nil
        )
      end
    end
  end

  describe "assert_can/3 with record" do
    test "passes when actor can access record matching scope" do
      result = run_test(DocumentPolicyTest, "reader can read approved documents")
      assert result == :ok
    end

    test "passes for own scope" do
      result = run_test(PostPolicyTest, "editor can update own posts")
      assert result == :ok
    end

    test "raises when record doesn't match scope" do
      assert_raise AshGrant.PolicyTest.AssertionError, fn ->
        AshGrant.PolicyTest.Assertions.do_assert_can(
          DocumentPolicyTest,
          :reader,
          :read,
          %{status: :draft}
        )
      end
    end
  end

  describe "assert_cannot/3 with record" do
    test "passes when actor cannot access specific record" do
      result = run_test(DocumentPolicyTest, "reader cannot read drafts")
      assert result == :ok
    end

    test "passes when scope doesn't match" do
      result = run_test(PostPolicyTest, "editor cannot update others posts")
      assert result == :ok
    end
  end

  describe "action keyword" do
    test "supports action_type: keyword" do
      result = run_test(DocumentPolicyTest, "author can update")
      assert result == :ok
    end

    test "supports action: keyword for specific action" do
      result = run_test(DocumentPolicyTest, "author can update action")
      assert result == :ok
    end
  end

  # Helper to run a specific test from a policy test module
  defp run_test(module, test_name) do
    tests = module.__policy_test__(:tests)

    case Enum.find(tests, &(&1.name == test_name)) do
      nil ->
        raise "Test not found: #{test_name}. Available: #{inspect(Enum.map(tests, & &1.name))}"

      test_def ->
        context = module.__policy_test__(:context)
        test_def.fun.(context)
    end
  end
end
