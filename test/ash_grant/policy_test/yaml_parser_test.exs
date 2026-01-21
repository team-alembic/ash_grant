defmodule AshGrant.PolicyTest.YamlParserTest do
  @moduledoc """
  Tests for the YAML policy test parser.
  """
  use ExUnit.Case, async: true

  alias AshGrant.PolicyTest.YamlParser

  @fixture_path "test/fixtures/policy_tests/document.yaml"

  describe "parse_file/1" do
    test "parses YAML file successfully" do
      assert {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      assert is_map(parsed)
      assert Map.has_key?(parsed, :resource)
      assert Map.has_key?(parsed, :actors)
      assert Map.has_key?(parsed, :tests)
    end

    test "returns error for non-existent file" do
      assert {:error, _} = YamlParser.parse_file("non_existent.yaml")
    end
  end

  describe "parse/1" do
    test "parses resource name" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      assert parsed.resource == AshGrant.Test.Document
    end

    test "parses actors" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      assert is_map(parsed.actors)
      assert Map.has_key?(parsed.actors, :admin)
      assert Map.has_key?(parsed.actors, :reader)
      assert Map.has_key?(parsed.actors, :guest)

      assert parsed.actors.admin == %{role: :admin}
      assert parsed.actors.reader == %{role: :reader}
      assert parsed.actors.guest == %{permissions: []}
    end

    test "parses tests" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      assert is_list(parsed.tests)
      assert length(parsed.tests) == 6
    end

    test "parses assert_can tests without record" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      admin_test = Enum.find(parsed.tests, &(&1.name == "admin can read"))

      assert admin_test != nil
      assert admin_test.type == :assert_can
      assert admin_test.actor == :admin
      assert admin_test.action == :read
      assert admin_test.record == nil
    end

    test "parses assert_cannot tests" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      guest_test = Enum.find(parsed.tests, &(&1.name == "guest cannot read"))

      assert guest_test != nil
      assert guest_test.type == :assert_cannot
      assert guest_test.actor == :guest
      assert guest_test.action == :read
    end

    test "parses tests with record" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      test_with_record =
        Enum.find(parsed.tests, &(&1.name == "reader can read approved documents"))

      assert test_with_record != nil
      assert test_with_record.record == %{status: :approved}
    end

    test "parses tests with action_type" do
      {:ok, parsed} = YamlParser.parse_file(@fixture_path)

      action_type_test = Enum.find(parsed.tests, &(&1.name == "author can update"))

      assert action_type_test != nil
      assert action_type_test.action_type == :update
      assert action_type_test.action == nil
    end
  end

  describe "run_yaml_tests/1" do
    test "runs tests from YAML file" do
      {:ok, results} = YamlParser.run_yaml_tests(@fixture_path)

      assert is_list(results)
      assert length(results) == 6

      # All tests should pass
      assert Enum.all?(results, & &1.passed)
    end

    test "returns results with test names" do
      {:ok, results} = YamlParser.run_yaml_tests(@fixture_path)

      test_names = Enum.map(results, & &1.test_name)

      assert "admin can read" in test_names
      assert "reader can read" in test_names
      assert "guest cannot read" in test_names
    end
  end
end
