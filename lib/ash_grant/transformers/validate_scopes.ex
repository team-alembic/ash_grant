defmodule AshGrant.Transformers.ValidateScopes do
  @moduledoc """
  Spark DSL transformer that validates scope definitions at compile time.

  This transformer provides helpful warnings for common scope configuration issues:

  - Warns if `:all` scope is commonly expected but not defined
  - Warns about deprecated `owner_field` usage
  - Warns when scopes use relationship traversal (`exists()` or dot-paths)
    without a `write:` option

  ## Relationship Traversal Warning

  When a scope uses `exists()` or dot-path references (e.g., `order.center_id`)
  and does not have a `write:` option set, a warning is emitted. These expressions
  cannot be evaluated in-memory for write actions (create, update, destroy).

  The warning is suppressed when the scope has a `write:` option, since the user
  has explicitly provided a write-safe expression (or `write: false` to deny writes).

  This warning is emitted regardless of `default_policies` setting, since explicit
  policies using `AshGrant.check()` have the same limitation.

  ## See Also

  - `AshGrant.Dsl` - DSL definition with scope entity and `write:` option
  - `AshGrant.Info` - Runtime introspection for scopes
  - `AshGrant.Check` - Write action check that uses write scope resolution
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)

    # Only validate if ash_grant is configured
    resolver = Transformer.get_option(dsl_state, [:ash_grant], :resolver)

    if resolver do
      validate_common_scopes(dsl_state, resource)
      validate_deprecated_options(dsl_state, resource)
      validate_exists_in_write_scopes(dsl_state, resource)
    end

    {:ok, dsl_state}
  end

  defp validate_common_scopes(dsl_state, resource) do
    scopes = get_scope_entities(dsl_state)
    scope_names = Enum.map(scopes, & &1.name)

    # Warn if :all scope is missing - it's commonly expected
    unless :all in scope_names do
      IO.warn(
        """
        AshGrant: scope :all is not defined in #{inspect(resource)}.
        Consider adding: scope :all, true

        This scope is commonly used for permissions like "#{derive_resource_name(resource)}:*:read:all"
        """,
        []
      )
    end
  end

  defp validate_deprecated_options(dsl_state, resource) do
    # Check for deprecated owner_field
    owner_field = Transformer.get_option(dsl_state, [:ash_grant], :owner_field)

    if owner_field do
      IO.warn(
        """
        AshGrant: owner_field is deprecated in #{inspect(resource)}.

        Replace:
            owner_field #{inspect(owner_field)}

        With:
            scope :own, expr(#{owner_field} == ^actor(:id))

        The owner_field option will be removed in v1.0.0.
        """,
        []
      )
    end

    # Check for deprecated scope_resolver
    scope_resolver = Transformer.get_option(dsl_state, [:ash_grant], :scope_resolver)

    if scope_resolver do
      IO.warn(
        """
        AshGrant: scope_resolver is deprecated in #{inspect(resource)}.

        Migrate your scopes to inline definitions:
            scope :scope_name, expr(your_filter_expression)

        The scope_resolver option will be removed in a future version.
        """,
        []
      )
    end
  end

  defp validate_exists_in_write_scopes(dsl_state, resource) do
    scopes = get_scope_entities(dsl_state)

    for scope <- scopes,
        is_nil(scope.write),
        contains_relationship_reference?(scope.filter) do
      IO.warn(
        """
        AshGrant: scope :#{scope.name} in #{inspect(resource)} uses relationship traversal \
        (exists() or dot-path) which cannot be evaluated in-memory for write actions.

        Add a `write:` option with a direct-field expression, or `write: false` to \
        explicitly deny writes with this scope:

            scope :#{scope.name}, #{inspect_filter_brief(scope.filter)},
              write: expr(direct_field in ^actor(:accessible_ids))
            # or
            scope :#{scope.name}, #{inspect_filter_brief(scope.filter)},
              write: false
        """,
        []
      )
    end
  end

  defp contains_relationship_reference?(filter) do
    contains_exists?(filter) or contains_dot_path?(filter)
  end

  # Recursively check if an Ash expression contains %Ash.Query.Exists{} nodes
  defp contains_exists?(true), do: false
  defp contains_exists?(false), do: false
  defp contains_exists?(%Ash.Query.Exists{}), do: true

  defp contains_exists?(%Ash.Query.BooleanExpression{left: left, right: right}) do
    contains_exists?(left) or contains_exists?(right)
  end

  defp contains_exists?(%Ash.Query.Not{expression: expr}), do: contains_exists?(expr)
  defp contains_exists?(_), do: false

  # Check if an Ash expression contains dot-path references (relationship traversal)
  defp contains_dot_path?(true), do: false
  defp contains_dot_path?(false), do: false

  defp contains_dot_path?(%Ash.Query.Ref{relationship_path: path}) when path != [] do
    true
  end

  defp contains_dot_path?(%Ash.Query.BooleanExpression{left: left, right: right}) do
    contains_dot_path?(left) or contains_dot_path?(right)
  end

  defp contains_dot_path?(%Ash.Query.Not{expression: expr}), do: contains_dot_path?(expr)

  defp contains_dot_path?(%{__struct__: _, left: left, right: right}) do
    contains_dot_path?(left) or contains_dot_path?(right)
  end

  defp contains_dot_path?(_), do: false

  defp inspect_filter_brief(true), do: "true"
  defp inspect_filter_brief(false), do: "false"
  defp inspect_filter_brief(_filter), do: "expr(...)"

  defp get_scope_entities(dsl_state) do
    Transformer.get_entities(dsl_state, [:ash_grant])
    |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))
  end

  defp derive_resource_name(resource) do
    resource
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end
end
