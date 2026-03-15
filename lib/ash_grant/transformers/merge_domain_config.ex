defmodule AshGrant.Transformers.MergeDomainConfig do
  @moduledoc """
  Spark DSL transformer that merges domain-level AshGrant configuration into resources.

  This transformer runs on resources (registered in the `AshGrant` extension) and
  copies `resolver` and `scope` definitions from the domain if the domain uses
  `AshGrant.Domain`.

  ## Merge Rules

  - **Resolver**: Inherited from domain only if the resource has no resolver.
  - **Scopes**: Domain scopes are added to the resource unless the resource
    defines a scope with the same name (resource wins).

  This transformer runs before all other AshGrant transformers so that downstream
  consumers (`Info`, `Check`, `FilterCheck`, etc.) see the merged state.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def before?(_), do: true

  @impl true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :domain)

    if domain && domain_has_ash_grant?(domain) do
      dsl_state = maybe_merge_resolver(dsl_state, domain)
      dsl_state = merge_scopes(dsl_state, domain)
      {:ok, dsl_state}
    else
      {:ok, dsl_state}
    end
  end

  defp domain_has_ash_grant?(domain) do
    AshGrant.Domain.Info.configured?(domain)
  end

  defp maybe_merge_resolver(dsl_state, domain) do
    resource_resolver = Transformer.get_option(dsl_state, [:ash_grant], :resolver)

    if resource_resolver do
      dsl_state
    else
      case AshGrant.Domain.Info.resolver(domain) do
        nil ->
          dsl_state

        domain_resolver ->
          Transformer.set_option(dsl_state, [:ash_grant], :resolver, domain_resolver)
      end
    end
  end

  defp merge_scopes(dsl_state, domain) do
    resource_scopes = get_scope_entities(dsl_state)
    resource_scope_names = MapSet.new(resource_scopes, & &1.name)
    domain_scopes = AshGrant.Domain.Info.scopes(domain)

    Enum.reduce(domain_scopes, dsl_state, fn domain_scope, acc ->
      if MapSet.member?(resource_scope_names, domain_scope.name) do
        acc
      else
        Transformer.add_entity(acc, [:ash_grant], domain_scope)
      end
    end)
  end

  defp get_scope_entities(dsl_state) do
    Transformer.get_entities(dsl_state, [:ash_grant])
    |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))
  end
end
