defmodule AshGrant.Domain.Verifiers.ValidateGrantReferences do
  @moduledoc """
  Domain-level counterpart of
  `AshGrant.Verifiers.ValidateGrantReferences`.

  Verifies each `permission` declared in a domain's `grants` block refers to a
  real `Ash.Resource`, a real action on it (or `:*`), and a scope that is
  defined on the target resource (including scopes the target inherits from
  this domain — that merge happens inside `AshGrant.Info.scopes/1`).

  A domain is not a valid `on:` target, so `local_scopes` and `local_actions`
  are passed as empty lists — they would only be consulted if a permission
  pointed back at the caller itself.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    domain = Verifier.get_persisted(dsl_state, :module)
    grants = Verifier.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] -> :ok
      _ -> AshGrant.Verifiers.GrantReferences.validate(grants, domain, [], [])
    end
  end
end
