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

  ## Predicate evaluation

  Grant predicates may reference `^actor(:key)`, `^tenant()`, and
  `^context(:key)` templates. Actor and tenant are pulled from the
  authorization context; `^context(...)` values come from `context.context`
  when callers pass one through (for example, via `Ash.Query.set_context/2`).

  ## Error handling

  Expression evaluation is wrapped in a `rescue` because a malformed
  predicate must never crash authorization. Any error is logged at `:warning`
  with the resource, grant name, and error — the grant is then treated as
  non-matching (fail closed). Silent drops without a log entry would hide
  real configuration bugs, so the log is deliberate.
  """

  require Logger

  @behaviour AshGrant.PermissionResolver

  @impl true
  def resolve(actor, %{resource: resource} = context) when not is_nil(resource) do
    resolve_for_resource(actor, resource, context)
  end

  def resolve(_actor, _context), do: []

  defp resolve_for_resource(actor, resource, context) do
    tenant = Map.get(context, :tenant)
    inner_context = Map.get(context, :context) || %{}

    resource
    |> AshGrant.Info.grants()
    |> Enum.flat_map(fn grant ->
      if predicate_true?(grant, actor, resource, tenant, inner_context) do
        Enum.map(grant.permissions || [], &to_permission_string/1)
      else
        []
      end
    end)
  end

  defp predicate_true?(%{predicate: true}, _actor, _resource, _tenant, _context), do: true
  defp predicate_true?(%{predicate: false}, _actor, _resource, _tenant, _context), do: false
  defp predicate_true?(%{predicate: nil}, _actor, _resource, _tenant, _context), do: false

  defp predicate_true?(grant, actor, resource, tenant, context) do
    filled =
      Ash.Expr.fill_template(grant.predicate,
        actor: actor,
        tenant: tenant,
        context: context,
        args: %{}
      )

    case Ash.Expr.eval(filled, actor: actor, resource: resource, tenant: tenant) do
      {:ok, true} -> true
      _ -> false
    end
  rescue
    error ->
      Logger.warning(
        "AshGrant.GrantsResolver: predicate for grant #{inspect(grant.name)} on " <>
          "#{inspect(resource)} raised — treating grant as non-matching. " <>
          "Error: #{Exception.message(error)}"
      )

      false
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
