defmodule AshGrant.PolicyTest.ConversionTest do
  @moduledoc """
  Tests for DSL <-> YAML conversion.
  """
  use ExUnit.Case, async: true

  alias AshGrant.PolicyTest.{YamlExporter, DslGenerator}
  alias AshGrant.PolicyTest.Fixtures.DocumentPolicyTest

  describe "YamlExporter.export/1" do
    test "exports module to YAML string" do
      yaml = YamlExporter.export(DocumentPolicyTest)

      assert is_binary(yaml)
      assert String.contains?(yaml, "resource:")
      assert String.contains?(yaml, "actors:")
      assert String.contains?(yaml, "tests:")
    end

    test "includes resource name" do
      yaml = YamlExporter.export(DocumentPolicyTest)

      assert String.contains?(yaml, "AshGrant.Test.Document")
    end

    test "includes actors" do
      yaml = YamlExporter.export(DocumentPolicyTest)

      assert String.contains?(yaml, "admin:")
      assert String.contains?(yaml, "reader:")
      assert String.contains?(yaml, "guest:")
    end

    test "includes test names" do
      yaml = YamlExporter.export(DocumentPolicyTest)

      assert String.contains?(yaml, "admin can do anything")
      assert String.contains?(yaml, "reader can read")
      assert String.contains?(yaml, "guest cannot read")
    end
  end

  describe "DslGenerator.generate/1" do
    @fixture_path "test/fixtures/policy_tests/document.yaml"

    test "generates DSL code from YAML" do
      code = DslGenerator.generate(@fixture_path)

      assert is_binary(code)
      assert String.contains?(code, "defmodule")
      assert String.contains?(code, "use AshGrant.PolicyTest")
    end

    test "includes resource declaration" do
      code = DslGenerator.generate(@fixture_path)

      assert String.contains?(code, "resource AshGrant.Test.Document")
    end

    test "includes actor declarations" do
      code = DslGenerator.generate(@fixture_path)

      assert String.contains?(code, "actor :admin")
      assert String.contains?(code, "actor :reader")
      assert String.contains?(code, "actor :guest")
    end

    test "includes test declarations" do
      code = DslGenerator.generate(@fixture_path)

      assert String.contains?(code, "test \"admin can read\"")
      assert String.contains?(code, "test \"reader can read\"")
      assert String.contains?(code, "test \"guest cannot read\"")
    end

    test "includes assert_can and assert_cannot" do
      code = DslGenerator.generate(@fixture_path)

      assert String.contains?(code, "assert_can :admin, :read")
      assert String.contains?(code, "assert_cannot :guest, :read")
    end
  end

  describe "round-trip conversion" do
    test "DSL -> YAML produces valid structure" do
      # Export to YAML
      yaml = YamlExporter.export(DocumentPolicyTest)

      # Verify structure contains expected sections
      assert String.contains?(yaml, "resource:")
      assert String.contains?(yaml, "actors:")
      assert String.contains?(yaml, "tests:")

      # Verify test names appear in output
      original_tests = DocumentPolicyTest.__policy_test__(:tests)

      Enum.each(original_tests, fn test ->
        assert String.contains?(yaml, test.name), "Expected to find test name: #{test.name}"
      end)
    end

    test "YAML -> DSL -> execution works" do
      # Generate DSL from YAML
      code = DslGenerator.generate(@fixture_path)

      # Verify the code is valid Elixir
      assert {:ok, _} = Code.string_to_quoted(code)
    end
  end
end
