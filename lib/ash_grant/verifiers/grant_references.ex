defmodule AshGrant.Verifiers.GrantReferences do
  @moduledoc false
  # Resource-level reference validation for grants. Called by
  # `AshGrant.Resource.Verifiers.ValidateGrantReferences`. Domain-level grants
  # (broadcasts) are validated separately in
  # `AshGrant.Domain.Verifiers.ValidateGrantReferences`, which has access
  # to the full list of resources in the domain.
  #
  # A resource's grants always target the enclosing resource — there is no
  # cross-resource keyword. So every permission's action and scope must
  # resolve against the resource's local actions and merged scopes.

  alias AshGrant.Verifiers.GrantTraversal
  alias Spark.Error.DslError

  @spec validate(
          grants :: [AshGrant.Dsl.Grant.t()],
          caller_module :: module(),
          local_scopes :: [atom()],
          local_actions :: [atom()]
        ) :: :ok | {:error, Exception.t()}
  def validate(grants, caller_module, local_scopes, local_actions) do
    GrantTraversal.each_permission(grants, fn permission, grant ->
      validate_permission(permission, grant, caller_module, local_scopes, local_actions)
    end)
  end

  defp validate_permission(permission, grant, caller_module, local_scopes, local_actions) do
    path = [:ash_grant, :grants, :grant, grant.name, :permission, permission.name]

    with :ok <- validate_action_reference(permission, caller_module, path, local_actions) do
      validate_scope_reference(permission, caller_module, path, local_scopes)
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
