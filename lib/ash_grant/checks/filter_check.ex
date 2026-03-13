defmodule AshGrant.FilterCheck do
  @moduledoc """
  FilterCheck for read actions.

  This check integrates with Ash's policy system to provide permission-based
  authorization for read operations. Unlike `AshGrant.Check` which returns
  `true`/`false`, this check returns a filter expression that limits query
  results to records the actor has permission to access.

  For write actions, use `AshGrant.Check` instead.

  > #### Auto-generated Policies {: .info}
  >
  > When using `default_policies: true` in your resource's `ash_grant` block,
  > this check is automatically configured for read actions. You don't need
  > to manually add it to your policies.

  ## When to Use

  Use `AshGrant.filter_check/1` for:
  - `:read` actions
  - List/index queries
  - Any action where you want to filter results based on permissions

  ## Usage in Policies

      policies do
        # For all read actions
        policy action_type(:read) do
          authorize_if AshGrant.filter_check()
        end

        # For specific read actions with action override
        policy action(:list_published) do
          authorize_if AshGrant.filter_check(action: "read")
        end
      end

  ## Options

  | Option | Type | Description |
  |--------|------|-------------|
  | `:action` | string | Override action name for permission matching |
  | `:resource` | string | Override resource name for permission matching |

  ## How It Works

  1. **Resolve permissions**: Calls the configured `PermissionResolver` to get
     the actor's permissions
  2. **Get all scopes**: Uses `AshGrant.Evaluator.get_all_scopes/3` to find
     all matching scopes (respecting deny-wins semantics)
  3. **Check for global access**: If scopes include "all" or "global", returns
     `true` (no filter needed)
  4. **Resolve scopes to filters**: Uses inline scope DSL or `ScopeResolver`
     to get filter expressions
  5. **Combine filters**: Combines all filters with OR logic

  ## Multi-Scope Support

  When an actor has permissions with multiple scopes, all scopes are combined:

      # Actor has both permissions:
      # - "post:*:read:own"       → filters to author_id == actor.id
      # - "post:*:read:published" → filters to status == :published

      # Result: author_id == actor.id OR status == :published

  This allows users to see both their own posts AND all published posts.

  ## Examples

  ### Basic Usage

      # Permission: "post:*:read:all"
      # Returns: true (no filter)

      # Permission: "post:*:read:own"
      # Returns: expr(author_id == ^actor(:id))

      # Permission: "post:*:read:published"
      # Returns: expr(status == :published)

  ### With Custom Action Name

      # Ash action is :get_by_slug, but we check "read" permission
      policy action(:get_by_slug) do
        authorize_if AshGrant.filter_check(action: "read")
      end

  ## Filter Return Values

  The check returns one of:

  - `true` - No filtering (actor has "all" or "global" scope)
  - `false` - Block all (no matching permissions or denied)
  - `Ash.Expr.t()` - Filter expression to apply to the query

  ## Context Injection

  Scopes can use `^context(:key)` for injectable values. Pass context via
  `Ash.Query.set_context/2`:

      # Scope definition:
      scope :today, expr(fragment("DATE(inserted_at) = ?", ^context(:reference_date)))

      # Query with injected context:
      Post
      |> Ash.Query.for_read(:read)
      |> Ash.Query.set_context(%{reference_date: ~D[2025-01-15]})
      |> Ash.read!(actor: actor)

  This enables deterministic testing of temporal and parameterized scopes.

  ## See Also

  - `AshGrant.Check` - For write actions
  - `AshGrant.Evaluator` - Permission evaluation logic
  - `AshGrant.Info` - DSL introspection helpers
  """

  use Ash.Policy.FilterCheck

  require Ash.Expr

  @doc """
  Creates a filter check tuple for use in policies.
  """
  def filter_check(opts \\ []) do
    {__MODULE__, opts}
  end

  @impl true
  def describe(opts) do
    action = Keyword.get(opts, :action, "current action")
    resource = Keyword.get(opts, :resource, "resource")
    "has permission filter for #{resource}:#{action}"
  end

  @doc """
  Simplifies a check reference into a SAT expression of simpler check references.

  For AshGrant filter checks, we return the ref unchanged since permissions are
  resolved dynamically at runtime and cannot be further decomposed statically.

  This callback is used by Ash's SAT solver to optimize policy evaluation.
  """
  @impl true
  def simplify(ref, _context) do
    ref
  end

  @doc """
  Determines if one check reference implies another.

  Two AshGrant filter checks imply each other if they have identical options
  (same action and resource overrides). This helps the SAT solver avoid
  redundant evaluations.
  """
  @impl true
  def implies?(ref1, ref2, _context) do
    normalize_ref(ref1) == normalize_ref(ref2)
  end

  @doc """
  Determines if two check references conflict (are mutually exclusive).

  AshGrant filter checks don't inherently conflict with each other.
  Returns `false` for all cases.
  """
  @impl true
  def conflicts?(_ref1, _ref2, _context) do
    false
  end

  # Normalize ref to handle both {Module, opts} and Module formats
  defp normalize_ref({module, opts}) when is_atom(module) and is_list(opts) do
    {module, Enum.sort(opts)}
  end

  defp normalize_ref(module) when is_atom(module) do
    {module, []}
  end

  defp normalize_ref(other), do: other

  @impl true
  def filter(actor, authorizer, opts) do
    if actor == nil do
      false
    else
      do_filter(actor, authorizer, opts)
    end
  end

  defp do_filter(actor, authorizer, opts) do
    resource_module = authorizer.resource
    action = authorizer.action

    # Get configuration from DSL
    resolver = AshGrant.Info.resolver(resource_module)
    scope_resolver = AshGrant.Info.scope_resolver(resource_module)
    configured_name = AshGrant.Info.resource_name(resource_module)

    # Note: Ash passes :resource as the module, we want a string name
    # Only use opts[:resource] if it's a string (user override)
    resource_name =
      case Keyword.get(opts, :resource) do
        nil -> configured_name
        name when is_binary(name) -> name
        _module -> configured_name
      end

    # When action is overridden via opts, don't infer action_type
    {action_name, action_type} =
      case Keyword.get(opts, :action) do
        nil -> {to_string(action.name), action_type_from(action)}
        override -> {override, nil}
      end

    # Build context
    context = %{
      actor: actor,
      resource: resource_module,
      action: action,
      tenant: get_tenant(authorizer)
    }

    # Resolve permissions
    permissions = resolve_permissions(resolver, actor, context)

    # Get RBAC scopes (instance_id = "*")
    scopes =
      AshGrant.Evaluator.get_all_scopes(permissions, resource_name, action_name, action_type)

    # Get instance permission IDs
    instance_ids =
      AshGrant.Evaluator.get_matching_instance_ids(
        permissions,
        resource_name,
        action_name,
        action_type
      )

    # Build combined filter from RBAC scopes + instance IDs
    build_filter_with_instances(scopes, instance_ids, scope_resolver, context)
  end

  defp action_type_from(%{type: type}), do: type
  defp action_type_from(_), do: nil

  defp build_filter_with_instances(scopes, instance_ids, scope_resolver, context) do
    # Check for global access from RBAC
    has_global_access = "all" in scopes or "global" in scopes

    cond do
      has_global_access ->
        # Global access via RBAC
        true

      scopes == [] and instance_ids == [] ->
        # No access at all
        false

      scopes == [] ->
        # Only instance permissions, no RBAC
        build_instance_filter(instance_ids)

      instance_ids == [] ->
        # Only RBAC, no instance permissions
        build_combined_filter(scopes, scope_resolver, context)

      true ->
        # Both RBAC and instance permissions - combine with OR
        rbac_filter = build_combined_filter(scopes, scope_resolver, context)
        instance_filter = build_instance_filter(instance_ids)
        combine_rbac_and_instance(rbac_filter, instance_filter)
    end
  end

  defp build_instance_filter(instance_ids) do
    # Build filter: id in ^instance_ids
    Ash.Expr.expr(id in ^instance_ids)
  end

  defp combine_rbac_and_instance(rbac_filter, _instance_filter) when rbac_filter == true do
    # RBAC gives full access, instance permissions are redundant
    true
  end

  defp combine_rbac_and_instance(rbac_filter, instance_filter) do
    # Combine RBAC scope filters with instance ID filter using OR
    Ash.Expr.expr(^rbac_filter or ^instance_filter)
  end

  defp resolve_permissions(resolver, actor, context) when is_function(resolver, 2) do
    resolver.(actor, context)
  end

  defp resolve_permissions(resolver, actor, context) when is_atom(resolver) do
    resolver.resolve(actor, context)
  end

  defp build_combined_filter(scopes, scope_resolver, context) do
    resource = context.resource

    filters =
      scopes
      |> Enum.map(&resolve_scope(resource, scope_resolver, &1, context))
      |> Enum.reject(&(&1 == true))

    case filters do
      [] ->
        # All scopes resolved to true
        true

      [single] ->
        single

      multiple ->
        # Combine with OR
        combine_with_or(multiple)
    end
  end

  # First try inline scope DSL, then fall back to scope_resolver
  defp resolve_scope(resource, scope_resolver, scope, context) do
    scope_atom = if is_binary(scope), do: String.to_existing_atom(scope), else: scope

    # Try inline scope DSL first
    case AshGrant.Info.get_scope(resource, scope_atom) do
      nil ->
        # Fall back to legacy scope_resolver
        resolve_with_scope_resolver(scope_resolver, scope, context)

      _scope_def ->
        # Use inline scope DSL
        AshGrant.Info.resolve_scope_filter(resource, scope_atom, context)
    end
  rescue
    ArgumentError ->
      # String.to_existing_atom failed, try legacy resolver
      resolve_with_scope_resolver(scope_resolver, scope, context)
  end

  defp resolve_with_scope_resolver(nil, "all", _context), do: true

  defp resolve_with_scope_resolver(nil, scope, _context) do
    raise """
    AshGrant: Scope "#{scope}" not found in inline scope DSL and no scope_resolver configured.

    Either define the scope inline in your ash_grant block:

        ash_grant do
          resolver MyApp.PermissionResolver
          scope :#{scope}, expr(...)
        end

    Or configure a scope_resolver:

        ash_grant do
          resolver MyApp.PermissionResolver
          scope_resolver MyApp.ScopeResolver
        end
    """
  end

  defp resolve_with_scope_resolver(resolver, scope, context) when is_function(resolver, 2) do
    resolver.(scope, context)
  end

  defp resolve_with_scope_resolver(resolver, scope, context) when is_atom(resolver) do
    resolver.resolve(scope, context)
  end

  defp combine_with_or(filters) do
    Enum.reduce(filters, fn filter, acc ->
      Ash.Expr.expr(^acc or ^filter)
    end)
  end

  defp get_tenant(authorizer) do
    case authorizer do
      %{query: %{tenant: tenant}} when not is_nil(tenant) -> tenant
      %{changeset: %{tenant: tenant}} when not is_nil(tenant) -> tenant
      _ -> nil
    end
  end
end
