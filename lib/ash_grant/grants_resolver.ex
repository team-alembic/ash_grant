defmodule AshGrant.GrantsResolver do
  @moduledoc """
  A generic `AshGrant.PermissionResolver` that emits permissions from
  declarative `grants` blocks at runtime, and merges in any user-declared
  resolver's output when both are configured.

  This resolver walks the grants declared on `context.resource` (merged
  with domain-level grants via `AshGrant.Info.grants/1`), evaluates each
  grant's predicate `Ash.Expr` against the actor via `Ash.Expr.eval/2`,
  and emits permission strings from every matching grant's permissions.

  If the resource (or its domain) also declares an explicit `resolver`
  function or module, that resolver is called afterwards and its output
  is concatenated onto the grants-derived list. Deny-wins in the
  downstream `AshGrant.Evaluator` still holds — a deny from either source
  overrides an allow from either source.

  `AshGrant.Info.resolver/1` routes through this module automatically any
  time grants are declared. Callers shouldn't reference `GrantsResolver`
  directly.

  ## Predicate evaluation

  Grant predicates may reference `^actor(:key)`, `^tenant()`, and
  `^context(:key)` templates. Actor and tenant are pulled from the
  authorization context; `^context(...)` values come from `context.context`
  when callers pass one through (for example, via `Ash.Query.set_context/2`).

  ## Error handling

  Expression evaluation is wrapped in a `rescue` because a malformed
  predicate must never crash authorization. Any error is logged at
  `:warning` with the resource, grant name, and error — the grant is then
  treated as non-matching (fail closed). The same applies to a raising
  user resolver: the error is logged and an empty list is substituted for
  that resolver's contribution so grants alone continue to work.
  """

  require Logger

  @behaviour AshGrant.PermissionResolver

  @impl true
  def resolve(actor, %{resource: resource} = context) when not is_nil(resource) do
    grants_perms = resolve_grants(actor, resource, context)
    extra_perms = resolve_via_resolver(actor, resource, context)
    grants_perms ++ extra_perms
  end

  def resolve(_actor, _context), do: []

  defp resolve_grants(actor, resource, context) do
    tenant = Map.get(context, :tenant)
    inner_context = Map.get(context, :context) || %{}

    resource
    |> AshGrant.Info.grants()
    |> Enum.flat_map(fn grant ->
      if predicate_true?(grant, actor, resource, tenant, inner_context) do
        Enum.map(grant.permissions || [], &to_permission_string(&1, resource))
      else
        []
      end
    end)
  end

  # Calls the user-declared resolver (the value of the `:resolver` DSL
  # option, looked up via `AshGrant.Info.raw_resolver/1` to bypass the
  # grants-synthesis routing). Returns its emitted permission list, or `[]`
  # when there is no explicit resolver.
  defp resolve_via_resolver(actor, resource, context) do
    case AshGrant.Info.raw_resolver(resource) do
      nil -> []
      resolver -> call_resolver(resolver, actor, resource, context)
    end
  end

  defp call_resolver(mod, actor, resource, context) when is_atom(mod) do
    mod.resolve(actor, context)
  rescue
    error ->
      Logger.warning(
        "AshGrant.GrantsResolver: resolver #{inspect(mod)} for " <>
          "#{inspect(resource)} raised — treating as empty. " <>
          "Error: #{Exception.message(error)}"
      )

      []
  end

  defp call_resolver(fun, actor, resource, context) when is_function(fun, 2) do
    fun.(actor, context)
  rescue
    error ->
      Logger.warning(
        "AshGrant.GrantsResolver: resolver function for " <>
          "#{inspect(resource)} raised — treating as empty. " <>
          "Error: #{Exception.message(error)}"
      )

      []
  end

  defp call_resolver(_other, _actor, _resource, _context), do: []

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

  # `permission.on == nil` means a domain-level broadcast: the permission
  # was declared without a target so it applies to every resource in the
  # domain. At runtime we substitute the resource currently being checked
  # (the one passed to `resolve/2` via `context.resource`).
  defp to_permission_string(%AshGrant.Dsl.Permission{} = permission, current_resource) do
    target = permission.on || current_resource
    resource_name = AshGrant.Info.resource_name(target)
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

  # `nil` scope = permission declared without a scope. Emit it as an empty
  # trailing segment so the 4-part parser round-trips it to `scope: nil`
  # (see `AshGrant.Permission.parse/1` and `normalize_scope/1`).
  defp stringify(nil), do: ""
  defp stringify(:*), do: "*"
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
