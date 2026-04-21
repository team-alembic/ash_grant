defmodule AshGrant.Domain.Transformers.SynthesizeGrantsResolver do
  @moduledoc """
  Domain-level counterpart of
  `AshGrant.Transformers.SynthesizeGrantsResolver`.

  When a domain declares a `grants do ... end` block and no explicit
  `resolver`, this transformer sets the domain's `resolver` option to
  `AshGrant.GrantsResolver`. Resources in the domain that don't declare
  their own resolver then inherit it (via `AshGrant.Info.resolver/1`), so
  domain-only grants actually run.

  Also fails compilation with a clear error when both `grants` and an explicit
  `resolver` are declared on the same domain — they are mutually exclusive
  (grants synthesize the resolver).

  No `on:` defaulting is performed here: a domain has no enclosing resource
  to default to, and the verifier emits a clear error if a permission is
  missing `on:`.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def after?(_), do: false

  @impl true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    grants = Transformer.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        {:ok, dsl_state}

      _ ->
        domain = Transformer.get_persisted(dsl_state, :module)

        with :ok <- validate_not_both_resolver_and_grants(dsl_state, domain) do
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

  defp validate_not_both_resolver_and_grants(dsl_state, domain) do
    case Transformer.get_option(dsl_state, [:ash_grant], :resolver) do
      nil ->
        :ok

      AshGrant.GrantsResolver ->
        # Already set by a previous run of this transformer; safe to no-op.
        :ok

      _resolver ->
        {:error,
         DslError.exception(
           module: domain,
           path: [:ash_grant, :grants],
           message:
             "Cannot declare both `grants` and `resolver` on #{inspect(domain)}. " <>
               "Use one or the other — grants synthesize a resolver automatically."
         )}
    end
  end
end
