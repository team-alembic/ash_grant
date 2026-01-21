defmodule AshGrant.PolicyTest.DslTest do
  @moduledoc """
  Tests for the PolicyTest DSL macros.
  """
  use ExUnit.Case, async: true

  # Fixture modules are defined in test/support/policy_test_fixtures.ex
  # to avoid macro conflicts with ExUnit's test/describe
  alias AshGrant.PolicyTest.Fixtures.{
    TestWithResource,
    TestWithActors,
    TestWithDescribeAndTest,
    TestWithoutDescribe,
    TestWithFunctions,
    TestContextInheritance
  }

  describe "use AshGrant.PolicyTest" do
    test "defines a policy test module with resource macro" do
      assert TestWithResource.__policy_test__(:resource) == AshGrant.Test.Document
    end

    test "defines actors with actor macro" do
      actors = TestWithActors.__policy_test__(:actors)

      assert actors[:admin] == %{role: :admin}
      assert actors[:reader] == %{role: :reader}
      assert actors[:author] == %{role: :author, id: "author_001"}
    end

    test "defines tests with describe and test macros" do
      tests = TestWithDescribeAndTest.__policy_test__(:tests)

      assert length(tests) == 3
      assert Enum.any?(tests, &(&1.name == "read access: reader can read"))
      assert Enum.any?(tests, &(&1.name == "read access: another test"))
      assert Enum.any?(tests, &(&1.name == "write access: reader cannot write"))
    end

    test "supports tests without describe block" do
      tests = TestWithoutDescribe.__policy_test__(:tests)

      assert length(tests) == 1
      assert hd(tests).name == "admin can do anything"
    end

    test "stores test functions for execution" do
      tests = TestWithFunctions.__policy_test__(:tests)
      test_def = hd(tests)

      assert is_function(test_def.fun, 1)
      # The function receives context and should execute the test body
      assert test_def.fun.(%{}) == 42
    end
  end

  describe "context inheritance" do
    test "test context includes resource and actors" do
      context = %{
        resource: TestContextInheritance.__policy_test__(:resource),
        actors: TestContextInheritance.__policy_test__(:actors)
      }

      assert context.resource == AshGrant.Test.Document
      assert context.actors[:reader] == %{role: :reader}
    end
  end
end
