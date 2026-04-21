defmodule AshGrant.GrantsResolver do
  @moduledoc """
  A generic `AshGrant.PermissionResolver` that synthesizes permissions from
  declarative `grants` blocks at runtime.

  This resolver walks the grants declared on `context.resource`, evaluates
  each grant's predicate against the actor, and emits permission strings from
  every matching grant's permissions. It is set as the resolver on any
  resource that declares a `grants` block and does not provide its own
  resolver.

  Resources should never reference this module directly — the
  `AshGrant.Transformers.SynthesizeGrantsResolver` transformer wires it up
  automatically.
  """

  @behaviour AshGrant.PermissionResolver

  @impl true
  def resolve(actor, %{resource: resource}) when not is_nil(resource) do
    resolve_for_resource(actor, resource)
  end

  def resolve(_actor, _context), do: []

  defp resolve_for_resource(actor, resource) do
    resource
    |> AshGrant.Info.grants()
    |> Enum.flat_map(fn grant ->
      if safe_predicate(grant.predicate, actor) do
        Enum.map(grant.permissions || [], &to_permission_string/1)
      else
        []
      end
    end)
  end

  defp safe_predicate(predicate, actor) when is_function(predicate, 1) do
    !!predicate.(actor)
  rescue
    _ -> false
  end

  defp safe_predicate(_, _), do: false

  defp to_permission_string(%AshGrant.Dsl.Permission{} = permission) do
    resource_name = AshGrant.Info.resource_name(permission.on)
    prefix = if permission.deny, do: "!", else: ""

    prefix <>
      resource_name <>
      ":" <>
      stringify(permission.instance) <>
      ":" <>
      stringify(permission.action) <>
      ":" <>
      stringify(permission.scope)
  end

  defp stringify(:*), do: "*"
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
