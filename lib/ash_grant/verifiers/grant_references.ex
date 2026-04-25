defmodule AshGrant.Verifiers.GrantReferences do
  @moduledoc false
  # Shared permission-reference validation used by both the resource-level
  # verifier (`AshGrant.Verifiers.ValidateGrantReferences`) and the
  # domain-level verifier (`AshGrant.Domain.Verifiers.ValidateGrantReferences`).
  #
  # There is no user-facing cross-resource keyword: a permission's target
  # is determined by where the grant lives. At the resource level,
  # `AshGrant.Transformers.NormalizeGrants` sets `permission.on` to the
  # enclosing resource at compile time; at the domain level no transformer
  # runs and `permission.on` stays `nil` (broadcast). That makes
  # validation simple:
  #
  # - `permission.on == nil` (domain broadcast) — the resource isn't known
  #   until runtime, so action/scope existence can't be checked statically.
  #   Skip all reference checks.
  # - `permission.on == caller_module` (resource-level after NormalizeGrants)
  #   — verify the action exists on the enclosing resource and, when a
  #   scope is given, that the scope is defined locally or inherited from
  #   the domain.
  #
  # `caller_module` is the module declaring the grants (resource or domain),
  # used for error attribution. `local_scopes` / `local_actions` are the
  # scope/action names visible in the caller's DSL state. Domains pass
  # empty lists for both (broadcasts skip validation entirely).

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
        # Domain-level broadcast — target unknown until runtime.
        :ok

      ^caller_module ->
        with :ok <- validate_action_reference(permission, caller_module, path, local_actions) do
          validate_scope_reference(permission, caller_module, path, local_scopes)
        end

      _other ->
        # Should never happen: `NormalizeGrants` only injects the enclosing
        # resource, and the user can't override `permission.on` themselves.
        # If we ever get here it's a bug in a transformer somewhere; fail
        # loudly rather than silently passing.
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
