defmodule AshGrant.Verifiers.GrantReferences do
  @moduledoc false
  # Shared permission-reference validation used by both the resource-level
  # verifier (`AshGrant.Verifiers.ValidateGrantReferences`) and the
  # domain-level verifier (`AshGrant.Domain.Verifiers.ValidateGrantReferences`).
  #
  # Checks each permission within each grant:
  # - `on:` is an `Ash.Resource`
  # - `action:` exists on the target resource (or is `:*`)
  # - `scope:` is defined on the target (merged with target's domain scopes)
  #
  # `caller_module` is the module declaring the grants (resource or domain) —
  # used only for error attribution. `local_scopes` / `local_actions` are the
  # scopes/action names already visible in the caller's DSL state; they are
  # consulted when a permission's `on:` points back at the caller itself.
  # Domains pass empty lists for both (a domain is not a valid `on:` target).

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
      # Domain-level broadcast (no target): the resource isn't known until
      # runtime, so action/scope existence can't be checked statically.
      # Trust the user — fail-closed at runtime if the action/scope is
      # missing on a particular resource (the permission string just won't
      # match that resource's check).
      nil ->
        :ok

      _ ->
        with :ok <- validate_resource_reference(permission, caller_module, path),
             :ok <- validate_action_reference(permission, caller_module, path, local_actions) do
          validate_scope_reference(permission, caller_module, path, local_scopes)
        end
    end
  end

  # `validate_permission/5` short-circuits on `on: nil`, so we always have a
  # non-nil target by the time we reach this clause.
  defp validate_resource_reference(%{on: target}, caller_module, path) when is_atom(target) do
    cond do
      target == caller_module ->
        :ok

      not looks_like_module?(target) ->
        # Plain atom like `:read` (not a module alias) — almost always a
        # typo or a forgotten positional argument. Keeping this as a soft
        # pass-through would let the error silently surface at runtime.
        dsl_error(
          caller_module,
          path,
          "`on: #{inspect(target)}` is not a module. Did you forget the target " <>
            "resource as the second positional argument? Expected form: " <>
            "`permission :name, TargetResource, :action, :scope`."
        )

      not Code.ensure_loaded?(target) ->
        case Code.ensure_compiled(target) do
          {:module, _} -> ensure_resource(target, caller_module, path)
          _ -> :ok
        end

      true ->
        ensure_resource(target, caller_module, path)
    end
  end

  # Elixir module aliases compile to atoms prefixed with `"Elixir."`
  # (e.g. `MyApp.Blog.Post` -> `:"Elixir.MyApp.Blog.Post"`). Plain atoms
  # like `:read` don't have that prefix and are never resources.
  defp looks_like_module?(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> _ -> true
      _ -> false
    end
  end

  defp ensure_resource(target, caller_module, path) do
    if Ash.Resource.Info.resource?(target) do
      :ok
    else
      dsl_error(
        caller_module,
        path,
        "`on: #{inspect(target)}` is not an `Ash.Resource`."
      )
    end
  end

  defp validate_action_reference(%{action: :*}, _caller_module, _path, _local_actions), do: :ok

  defp validate_action_reference(
         %{on: target, action: action},
         caller_module,
         path,
         local_actions
       )
       when is_atom(target) and is_atom(action) do
    cond do
      target == caller_module ->
        ensure_action_in(action, local_actions, target, caller_module, path)

      Code.ensure_loaded?(target) ->
        actions =
          target
          |> Ash.Resource.Info.actions()
          |> Enum.map(& &1.name)

        ensure_action_in(action, actions, target, caller_module, path)

      true ->
        :ok
    end
  end

  defp ensure_action_in(action, actions, target, caller_module, path) do
    if action in actions do
      :ok
    else
      dsl_error(
        caller_module,
        path,
        "`action: #{inspect(action)}` is not defined on #{inspect(target)}. " <>
          "Available actions: #{inspect(actions)}."
      )
    end
  end

  # `scope` is optional on a permission — a nil scope means "no row filter"
  # (equivalent to `:always`). Skip reference validation entirely in that
  # case; there's nothing to look up.
  defp validate_scope_reference(%{scope: nil}, _caller_module, _path, _local_scopes), do: :ok

  defp validate_scope_reference(
         %{on: target, scope: scope},
         caller_module,
         path,
         local_scopes
       )
       when is_atom(target) and is_atom(scope) do
    cond do
      target == caller_module ->
        ensure_scope_in(scope, local_scopes, target, caller_module, path)

      Code.ensure_loaded?(target) ->
        scopes =
          target
          |> AshGrant.Info.scopes()
          |> Enum.map(& &1.name)

        ensure_scope_in(scope, scopes, target, caller_module, path)

      true ->
        :ok
    end
  end

  defp ensure_scope_in(scope, scopes, target, caller_module, path) do
    if scope in scopes do
      :ok
    else
      dsl_error(
        caller_module,
        path,
        "`scope: #{inspect(scope)}` is not defined on #{inspect(target)}. " <>
          "Available scopes: #{inspect(scopes)}. " <>
          "Add one with `scope #{inspect(scope)}, expr(...)` in the resource's `ash_grant` block."
      )
    end
  end

  defp dsl_error(caller_module, path, message) do
    {:error, DslError.exception(module: caller_module, path: path, message: message)}
  end
end
