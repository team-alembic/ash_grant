defmodule AshGrant.PolicyTest.Dsl do
  @moduledoc """
  DSL macros for defining policy tests.

  This module provides the following macros:

  - `resource/1` - Specify the resource being tested
  - `actor/2` - Define a named actor with attributes
  - `describe/2` - Group related tests
  - `test/2` - Define a single test case

  These macros are automatically imported when you `use AshGrant.PolicyTest`.
  """

  @doc """
  Specifies the resource being tested.

  ## Examples

      resource MyApp.Document
      resource MyApp.Blog.Post
  """
  defmacro resource(module) do
    quote do
      @policy_test_resource unquote(module)
    end
  end

  @doc """
  Defines a named actor with attributes.

  Actors are referenced by name in `assert_can` and `assert_cannot` macros.

  ## Examples

      actor :reader, %{role: :reader}
      actor :author, %{role: :author, id: "author_001"}
      actor :pm, %{
        role: :project_manager,
        id: "pm_001",
        team_id: "team_alpha",
        project_ids: ["proj_1", "proj_2"]
      }
  """
  defmacro actor(name, attrs) do
    quote do
      @policy_test_actors {unquote(name), unquote(attrs)}
    end
  end

  @doc """
  Groups related tests under a description.

  The description is prepended to test names within the block.

  ## Examples

      describe "read access" do
        test "reader can read" do
          assert_can :reader, :read
        end
      end
  """
  defmacro describe(description, do: block) do
    quote do
      previous_describe = Module.get_attribute(__MODULE__, :policy_test_current_describe)
      Module.put_attribute(__MODULE__, :policy_test_current_describe, unquote(description))

      unquote(block)

      Module.put_attribute(__MODULE__, :policy_test_current_describe, previous_describe)
    end
  end

  @doc """
  Defines a single test case.

  Within the test body, use `assert_can` and `assert_cannot` macros
  to verify policy behavior.

  ## Examples

      test "reader can read" do
        assert_can :reader, :read
      end

      test "reader can read published documents" do
        assert_can :reader, :read, %{status: :published}
      end
  """
  defmacro test(name, do: block) do
    # We need to escape the block as AST since module attributes can't hold functions
    escaped_block = Macro.escape(block)

    quote do
      current_describe = Module.get_attribute(__MODULE__, :policy_test_current_describe)

      full_name =
        case current_describe do
          nil -> unquote(name)
          desc -> "#{desc}: #{unquote(name)}"
        end

      @policy_test_tests %{
        name: full_name,
        body: unquote(escaped_block),
        describe: current_describe
      }
    end
  end
end
