defmodule AshGrant.Verifiers.GrantReferences do
  @moduledoc false
  # Resource-level reference validation for grants. Called by
  # `AshGrant.Verifiers.ValidateGrantReferences`. Domain-level grants
  # (broadcasts) are validated separately in
  # `AshGrant.Domain.Verifiers.ValidateGrantReferences`, which has access
  # to the full list of resources in the domain.
  #
  # `permission.on` is set by `AshGrant.Transformers.NormalizeGrants` to
  # the enclosing resource at compile time, so the only case we need to
  # validate is `permission.on == caller_module`. The `nil` case is a
  # defensive no-op in case a future transformer leaves the field unset.

  alias Spark.Error.DslError

  @spec validate(
          grants :: [AshGrant.Dsl.Grant.t()],
          caller_module :: module(),
          local_scopes :: [atom()],
          local_actions :: [atom()]
        ) :: :ok | {:error, Exception.t()}
  def validate(grants, caller_module, local_scopes, local_actions) do
    Enum.reduce_while(grants, :ok, fn grant, :ok ->
      case validate_grant(grant, caller_module, local_scopes, local_actions) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_grant(grant, caller_module, local_scopes, local_actions) do
    Enum.reduce_while(grant.permissions || [], :ok, fn permission, :ok ->
      case validate_permission(permission, grant, caller_module, local_scopes, local_actions) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_permission(permission, grant, caller_module, local_scopes, local_actions) do
    path = [:ash_grant, :grants, :grant, grant.name, :permission, permission.name]

    case permission.on do
      nil ->
        # Defensive: NormalizeGrants always injects the enclosing resource
        # at the resource level, so this branch shouldn't trigger. If a
        # future transformer leaves it unset, skip silently rather than
        # error — the domain-level verifier handles intentional broadcasts.
        :ok

      ^caller_module ->
        with :ok <- validate_action_reference(permission, caller_module, path, local_actions) do
          validate_scope_reference(permission, caller_module, path, local_scopes)
        end

      _other ->
        # Should never happen: `NormalizeGrants` only injects the enclosing
        # resource, and there is no user-facing cross-resource keyword. If
        # we ever get here it's a transformer bug — fail loudly.
        dsl_error(
          caller_module,
          path,
          "Internal error: permission target #{inspect(permission.on)} is not " <>
            "the enclosing module #{inspect(caller_module)}. Please open an issue."
        )
    end
  end

  defp validate_action_reference(%{action: :*}, _caller_module, _path, _local_actions), do: :ok

  defp validate_action_reference(%{action: action}, caller_module, path, local_actions)
       when is_atom(action) do
    if action in local_actions do
      :ok
    else
      dsl_error(
        caller_module,
        path,
        "`action: #{inspect(action)}` is not defined on #{inspect(caller_module)}. " <>
          "Available actions: #{inspect(local_actions)}."
      )
    end
  end

  # `scope` is optional on a permission — a nil scope means "no row filter"
  # (equivalent to `:always`). Skip reference validation entirely in that
  # case; there's nothing to look up.
  defp validate_scope_reference(%{scope: nil}, _caller_module, _path, _local_scopes), do: :ok

  defp validate_scope_reference(%{scope: scope}, caller_module, path, local_scopes)
       when is_atom(scope) do
    if scope in local_scopes do
      :ok
    else
      dsl_error(
        caller_module,
        path,
        "`scope: #{inspect(scope)}` is not defined on #{inspect(caller_module)}. " <>
          "Available scopes: #{inspect(local_scopes)}. " <>
          "Add one with `scope #{inspect(scope)}, expr(...)` in the resource's `ash_grant` block."
      )
    end
  end

  defp dsl_error(caller_module, path, message) do
    {:error, DslError.exception(module: caller_module, path: path, message: message)}
  end
end
