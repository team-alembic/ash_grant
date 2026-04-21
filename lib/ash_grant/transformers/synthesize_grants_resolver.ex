defmodule AshGrant.Transformers.SynthesizeGrantsResolver do
  @moduledoc """
  Compiles the declarative `grants` block into a permission resolver function.

  When a resource declares `grants do ... end` and no explicit `resolver`,
  this transformer builds a 2-arity function that:

  - Walks every declared grant
  - Evaluates each grant's predicate against the supplied actor
  - Emits permission strings from the permissions of grants that match

  The synthesized resolver is stored in the `resolver` DSL option so the
  existing `Check`, `FilterCheck`, and `Explainer` machinery picks it up
  without change.

  The resource name embedded in each permission string is resolved at runtime
  via `AshGrant.Info.resource_name/1`, so grants can refer to other resources
  that compile in a different order.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshGrant.Transformers.NormalizeGrants), do: true
  def after?(AshGrant.Transformers.MergeDomainConfig), do: true
  def after?(_), do: false

  @impl true
  def before?(AshGrant.Transformers.ValidateResolverPresent), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    grants = Transformer.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        {:ok, dsl_state}

      _ ->
        {:ok,
         Transformer.set_option(
           dsl_state,
           [:ash_grant],
           :resolver,
           AshGrant.GrantsResolver
         )}
    end
  end
end
