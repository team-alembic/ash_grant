defmodule AshGrant.Verifiers.ValidateGrantReferences do
  @moduledoc """
  Verifies that every `permission` in a resource's `grants` block refers to a
  real resource, action, and scope.

  This runs as a Spark verifier after every transformer so that Ash's default
  actions have been materialized before we check them. The actual rule set is
  shared with the domain-level verifier and lives in
  `AshGrant.Verifiers.GrantReferences`.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    resource = Verifier.get_persisted(dsl_state, :module)
    grants = Verifier.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        :ok

      _ ->
        AshGrant.Verifiers.GrantReferences.validate(
          grants,
          resource,
          available_scope_names(dsl_state),
          available_action_names(dsl_state)
        )
    end
  end

  # Scopes visible to a resource at runtime are the resource's own scopes
  # plus any scopes inherited from its domain (see `AshGrant.Info.scopes/1`).
  # The verifier mirrors that merge so a resource's grant can safely
  # reference a domain-inherited scope.
  defp available_scope_names(dsl_state) do
    local =
      Verifier.get_entities(dsl_state, [:ash_grant])
      |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))
      |> Enum.map(& &1.name)

    domain =
      case Verifier.get_persisted(dsl_state, :domain) do
        nil -> []
        domain -> AshGrant.Domain.Info.scopes(domain) |> Enum.map(& &1.name)
      end

    Enum.uniq(local ++ domain)
  end

  defp available_action_names(dsl_state) do
    Verifier.get_entities(dsl_state, [:actions])
    |> Enum.map(& &1.name)
  end
end
