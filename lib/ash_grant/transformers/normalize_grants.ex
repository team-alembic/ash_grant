defmodule AshGrant.Transformers.NormalizeGrants do
  @moduledoc """
  Normalizes and validates the `grants` DSL block.

  This transformer runs once all entities are parsed and:

  - Fills in `on:` with the current resource module when omitted on a
    permission declared inside a resource's own `ash_grant` block.
  - Validates that `grants` and an explicit `resolver` are not both set.
  - Validates that every `purpose:` / `purposes:` atom is a member of the
    declared vocabulary, when one is configured.

  Reference validation (that each permission's `on:`, `action:`, and `scope:`
  resolve to real things) is handled by
  `AshGrant.Verifiers.ValidateGrantReferences`, which runs after all
  transformers so that Ash's default actions have been materialized.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def after?(AshGrant.Transformers.MergeDomainConfig), do: true
  def after?(_), do: false

  @impl true
  def before?(AshGrant.Transformers.SynthesizeGrantsResolver), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)
    grants = Transformer.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        {:ok, dsl_state}

      _ ->
        with :ok <- validate_not_both_resolver_and_grants(dsl_state, resource),
             {:ok, dsl_state} <- inject_default_resource(dsl_state, resource, grants),
             :ok <- validate_grants(dsl_state, resource) do
          {:ok, dsl_state}
        end
    end
  end

  defp validate_not_both_resolver_and_grants(dsl_state, resource) do
    case Transformer.get_option(dsl_state, [:ash_grant], :resolver) do
      nil ->
        :ok

      _resolver ->
        {:error,
         dsl_error(
           resource,
           [:ash_grant, :grants],
           "Cannot declare both `grants` and `resolver` on #{inspect(resource)}. " <>
             "Use one or the other — grants synthesize a resolver automatically."
         )}
    end
  end

  defp inject_default_resource(dsl_state, resource, grants) do
    updated = Enum.reduce(grants, dsl_state, &inject_into_grant(&1, &2, resource))
    {:ok, updated}
  end

  defp inject_into_grant(grant, dsl_state, resource) do
    new_permissions = Enum.map(grant.permissions || [], &inject_permission_resource(&1, resource))
    new_grant = %{grant | permissions: new_permissions}
    Transformer.replace_entity(dsl_state, [:ash_grant, :grants], new_grant, &(&1.name == grant.name))
  end

  defp inject_permission_resource(%{on: nil} = permission, resource), do: %{permission | on: resource}
  defp inject_permission_resource(permission, _resource), do: permission

  defp validate_grants(dsl_state, resource) do
    grants = Transformer.get_entities(dsl_state, [:ash_grant, :grants])
    declared_purposes = Transformer.get_option(dsl_state, [:ash_grant], :purposes)

    Enum.reduce_while(grants, :ok, fn grant, :ok ->
      case validate_grant_purposes(grant, declared_purposes, resource) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_grant_purposes(grant, declared_purposes, resource) do
    with :ok <- validate_purpose_vocabulary(grant, declared_purposes, resource, grant_path(grant)) do
      validate_permission_purposes(grant, declared_purposes, resource)
    end
  end

  defp validate_permission_purposes(grant, declared_purposes, resource) do
    Enum.reduce_while(grant.permissions || [], :ok, fn permission, :ok ->
      case validate_purpose_vocabulary(
             permission,
             declared_purposes,
             resource,
             permission_path(grant, permission)
           ) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp validate_purpose_vocabulary(_entity, nil, _resource, _path), do: :ok

  defp validate_purpose_vocabulary(entity, declared, resource, path) do
    purposes = purpose_list(entity)

    case Enum.reject(purposes, &(&1 in declared)) do
      [] ->
        :ok

      unknown ->
        {:error,
         dsl_error(
           resource,
           path,
           "Unknown purpose(s) #{inspect(unknown)}. Declared vocabulary: #{inspect(declared)}. " <>
             "Add them to `ash_grant do purposes [...] end` or remove them from this entity."
         )}
    end
  end

  defp purpose_list(%{purpose: nil, purposes: nil}), do: []
  defp purpose_list(%{purpose: single, purposes: nil}), do: [single]
  defp purpose_list(%{purpose: nil, purposes: list}), do: list
  defp purpose_list(%{purpose: single, purposes: list}), do: [single | list]

  defp grant_path(grant), do: [:ash_grant, :grants, :grant, grant.name]

  defp permission_path(grant, permission),
    do: [:ash_grant, :grants, :grant, grant.name, :permission, permission.name]

  defp dsl_error(resource, path, message) do
    DslError.exception(module: resource, path: path, message: message)
  end
end
