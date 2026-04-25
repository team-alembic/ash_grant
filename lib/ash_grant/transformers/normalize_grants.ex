defmodule AshGrant.Transformers.NormalizeGrants do
  @moduledoc """
  Normalizes the `grants` DSL block.

  Runs once all entities are parsed and fills in `on:` with the current
  resource module when omitted on a permission declared inside a
  resource's own `ash_grant` block.

  Reference validation (that each permission's `on:`, `action:`, and `scope:`
  resolve to real things) is handled by
  `AshGrant.Verifiers.ValidateGrantReferences`, which runs after all
  transformers so that Ash's default actions have been materialized.

  `grants` and an explicit `resolver` are **not** mutually exclusive. When
  both are declared, `AshGrant.GrantsResolver` runs grants and then calls
  the user's resolver, concatenating the permission lists. See
  `AshGrant.GrantsResolver` for the runtime merge.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: false

  @impl true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)
    grants = Transformer.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        {:ok, dsl_state}

      _ ->
        inject_default_resource(dsl_state, resource, grants)
    end
  end

  defp inject_default_resource(dsl_state, resource, grants) do
    updated = Enum.reduce(grants, dsl_state, &inject_into_grant(&1, &2, resource))
    {:ok, updated}
  end

  defp inject_into_grant(grant, dsl_state, resource) do
    new_permissions = Enum.map(grant.permissions || [], &inject_permission_resource(&1, resource))
    new_grant = %{grant | permissions: new_permissions}

    Transformer.replace_entity(
      dsl_state,
      [:ash_grant, :grants],
      new_grant,
      &(&1.name == grant.name)
    )
  end

  defp inject_permission_resource(%{on: nil} = permission, resource),
    do: %{permission | on: resource}

  defp inject_permission_resource(permission, _resource), do: permission
end
