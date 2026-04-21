defmodule AshGrant.GrantsResolver do
  @moduledoc """
  A generic `AshGrant.PermissionResolver` that synthesizes permissions from
  declarative `grants` blocks at runtime.

  This resolver walks the grants declared on `context.resource`, evaluates
  each grant's predicate `Ash.Expr` against the actor via `Ash.Expr.eval/2`,
  and emits permission strings from every matching grant's permissions. It is
  set as the resolver on any resource that declares a `grants` block and does
  not provide its own resolver.

  Resources should never reference this module directly — the
  `AshGrant.Transformers.SynthesizeGrantsResolver` transformer wires it up
  automatically.
  """

  @behaviour AshGrant.PermissionResolver

  @impl true
  def resolve(actor, %{resource: resource} = context) when not is_nil(resource) do
    resolve_for_resource(actor, resource, context)
  end

  def resolve(_actor, _context), do: []

  defp resolve_for_resource(actor, resource, context) do
    tenant = Map.get(context, :tenant)

    resource
    |> AshGrant.Info.grants()
    |> Enum.flat_map(fn grant ->
      if predicate_true?(grant.predicate, actor, resource, tenant) do
        Enum.map(grant.permissions || [], &to_permission_string/1)
      else
        []
      end
    end)
  end

  defp predicate_true?(true, _actor, _resource, _tenant), do: true
  defp predicate_true?(false, _actor, _resource, _tenant), do: false
  defp predicate_true?(nil, _actor, _resource, _tenant), do: false

  defp predicate_true?(expression, actor, resource, tenant) do
    filled = Ash.Expr.fill_template(expression, actor: actor, tenant: tenant, context: %{}, args: %{})

    case Ash.Expr.eval(filled, actor: actor, resource: resource, tenant: tenant) do
      {:ok, true} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

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
