defmodule AshGrant.Transformers.ValidateScopes do
  @moduledoc """
  Spark DSL transformer that validates scope definitions at compile time.

  This transformer provides helpful warnings for common scope configuration issues:

  - Warns about deprecated `owner_field` and `scope_resolver` usage

  ## See Also

  - `AshGrant.Dsl` - DSL definition with scope entity and `write:` option
  - `AshGrant.Info` - Runtime introspection for scopes
  - `AshGrant.Check` - Write action check with DB query fallback for relational scopes
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
      validate_deprecated_options(dsl_state, resource)
      validate_instance_key(dsl_state, resource)
    end

    {:ok, dsl_state}
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

  defp validate_instance_key(dsl_state, resource) do
    instance_key = Transformer.get_option(dsl_state, [:ash_grant], :instance_key)

    if instance_key && instance_key != :id do
      attributes = Transformer.get_entities(dsl_state, [:attributes])
      attr_names = Enum.map(attributes, & &1.name)

      unless instance_key in attr_names do
        raise Spark.Error.DslError,
          module: resource,
          path: [:ash_grant, :instance_key],
          message:
            "instance_key :#{instance_key} does not exist as an attribute on #{inspect(resource)}. " <>
              "Available attributes: #{inspect(attr_names)}"
      end
    end
  end
end
