defmodule AshGrant.Transformers.ValidateResolverPresent do
  @moduledoc """
  Spark DSL transformer that validates a resolver is present after domain merge.

  This runs after `MergeDomainConfig` and before `ValidateScopes`.
  It raises a compile error if no resolver was found from either the resource
  or the domain.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshGrant.Transformers.MergeDomainConfig), do: true
  def after?(_), do: false

  @impl true
  def before?(AshGrant.Transformers.MergeDomainConfig), do: false
  def before?(_), do: true

  @impl true
  def transform(dsl_state) do
    resolver = Transformer.get_option(dsl_state, [:ash_grant], :resolver)

    if resolver do
      {:ok, dsl_state}
    else
      resource = Transformer.get_persisted(dsl_state, :module)

      {:error,
       Spark.Error.DslError.exception(
         module: resource,
         path: [:ash_grant, :resolver],
         message: """
         No resolver configured for #{inspect(resource)}.

         Either set a resolver on the resource:

             ash_grant do
               resolver MyApp.PermissionResolver
             end

         Or set one on the domain using the AshGrant.Domain extension:

             use Ash.Domain, extensions: [AshGrant.Domain]

             ash_grant do
               resolver MyApp.PermissionResolver
             end
         """
       )}
    end
  end
end
