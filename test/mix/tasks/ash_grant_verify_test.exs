defmodule Mix.Tasks.AshGrant.VerifyTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @fixture_path "test/fixtures/policy_tests/document.yaml"

  describe "run/1" do
    test "runs YAML tests" do
      output =
        capture_io(fn ->
          Mix.Tasks.AshGrant.Verify.run([@fixture_path])
        end)

      assert String.contains?(output, "passed")
    end

    test "runs with verbose flag" do
      output =
        capture_io(fn ->
          Mix.Tasks.AshGrant.Verify.run([@fixture_path, "--verbose"])
        end)

      assert String.contains?(output, "admin can read")
    end
  end
end
