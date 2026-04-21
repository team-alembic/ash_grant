defmodule AshGrant.Verifiers.ValidateGrantReferences do
  @moduledoc """
  Verifies that every `permission` in a `grants` block refers to a real
  resource, action, and scope.

  This runs as a Spark verifier after every transformer so that Ash's default
  actions have been materialized before we check them.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    resource = Verifier.get_persisted(dsl_state, :module)
    grants = Verifier.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        :ok

      _ ->
        local_scopes =
          Verifier.get_entities(dsl_state, [:ash_grant])
          |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))
          |> Enum.map(& &1.name)

        local_actions =
          Verifier.get_entities(dsl_state, [:actions])
          |> Enum.map(& &1.name)

        validate_all_grants(grants, resource, local_scopes, local_actions)
    end
  end

  defp validate_all_grants(grants, resource, local_scopes, local_actions) do
    Enum.reduce_while(grants, :ok, fn grant, :ok ->
      case validate_grant_permissions(grant, resource, local_scopes, local_actions) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_grant_permissions(grant, resource, local_scopes, local_actions) do
    Enum.reduce_while(grant.permissions || [], :ok, fn permission, :ok ->
      case validate_permission(permission, grant, resource, local_scopes, local_actions) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_permission(permission, grant, resource, local_scopes, local_actions) do
    path = [:ash_grant, :grants, :grant, grant.name, :permission, permission.name]

    with :ok <- validate_resource_reference(permission, resource, path),
         :ok <- validate_action_reference(permission, resource, path, local_actions) do
      validate_scope_reference(permission, resource, path, local_scopes)
    end
  end

  defp validate_resource_reference(%{on: nil}, resource, path) do
    dsl_error(
      resource,
      path,
      "`on:` is required — could not infer the target resource. " <>
        "Declare the permission inside a resource's `ash_grant` block, or pass `on: MyApp.Blog.Post`."
    )
  end

  defp validate_resource_reference(%{on: target}, resource, path) when is_atom(target) do
    cond do
      target == resource ->
        :ok

      not Code.ensure_loaded?(target) ->
        case Code.ensure_compiled(target) do
          {:module, _} -> ensure_resource(target, resource, path)
          _ -> :ok
        end

      true ->
        ensure_resource(target, resource, path)
    end
  end

  defp ensure_resource(target, resource, path) do
    if Ash.Resource.Info.resource?(target) do
      :ok
    else
      dsl_error(
        resource,
        path,
        "`on: #{inspect(target)}` is not an `Ash.Resource`."
      )
    end
  end

  defp validate_action_reference(%{action: :*}, _resource, _path, _local_actions), do: :ok

  defp validate_action_reference(%{on: target, action: action}, resource, path, local_actions)
       when is_atom(target) and is_atom(action) do
    cond do
      target == resource ->
        ensure_action_in(action, local_actions, target, resource, path)

      Code.ensure_loaded?(target) ->
        actions =
          target
          |> Ash.Resource.Info.actions()
          |> Enum.map(& &1.name)

        ensure_action_in(action, actions, target, resource, path)

      true ->
        :ok
    end
  end

  defp ensure_action_in(action, actions, target, resource, path) do
    if action in actions do
      :ok
    else
      dsl_error(
        resource,
        path,
        "`action: #{inspect(action)}` is not defined on #{inspect(target)}. " <>
          "Available actions: #{inspect(actions)}."
      )
    end
  end

  defp validate_scope_reference(%{on: target, scope: scope}, resource, path, local_scopes)
       when is_atom(target) and is_atom(scope) do
    cond do
      target == resource ->
        ensure_scope_in(scope, local_scopes, target, resource, path)

      Code.ensure_loaded?(target) ->
        scopes =
          target
          |> AshGrant.Info.scopes()
          |> Enum.map(& &1.name)

        ensure_scope_in(scope, scopes, target, resource, path)

      true ->
        :ok
    end
  end

  defp ensure_scope_in(scope, scopes, target, resource, path) do
    if scope in scopes do
      :ok
    else
      dsl_error(
        resource,
        path,
        "`scope: #{inspect(scope)}` is not defined on #{inspect(target)}. " <>
          "Available scopes: #{inspect(scopes)}. " <>
          "Add one with `scope #{inspect(scope)}, expr(...)` in the resource's `ash_grant` block."
      )
    end
  end

  defp dsl_error(resource, path, message) do
    {:error, DslError.exception(module: resource, path: path, message: message)}
  end
end
