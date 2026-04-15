# Migration Guide

This guide covers migrations away from deprecated AshGrant APIs. Each
section explains **why** the old API is deprecated, what replaces it,
and the mechanical steps to upgrade existing code.

## `write:` scope option → `resolve_argument`

**Deprecated in 0.14.** Still compiles; emits a compile-time
deprecation warning.

### Why it exists

When a scope's read-side expression traversed a relationship
(`expr(order.center_id in ...)`), the write-side couldn't evaluate in
memory. `write:` was an escape hatch: "use *this* simpler expression
when checking a write."

```elixir
# Before
scope :at_own_unit,
  expr(order.center_id in ^actor(:own_org_unit_ids)),
  write: expr(center_id in ^actor(:own_org_unit_ids))
```

This worked, but had two problems:

1. Two independent expressions for one logical rule — easy to drift.
2. Composite scopes (`[:at_own_unit]`) didn't compose `write:` cleanly,
   causing subtle inheritance bugs (see CHANGELOG 0.14 #83, #86).

### What replaces it

`resolve_argument` + an argument-based scope expression. The scope
becomes in-memory-evaluable **for both read and write**, and the
resource populates the argument from its own FK lazily.

```elixir
# After
ash_grant do
  scope :at_own_unit, expr(^arg(:center_id) in ^actor(:own_org_unit_ids))

  resolve_argument :center_id, from_path: [:order, :center_id]
end
```

One expression, no composite edge cases, zero cost for scopes that don't
need the value (see the
[Argument-Based Scope guide](argument-based-scope.md) for why).

### Migration steps

1. For each scope with a `write:` override, identify the FK path from
   the record to the authorizing value. Usually this mirrors the `write:`
   expression's attribute name (`center_id`) and the read expression's
   relationship path (`order.center_id`).
2. Rewrite the scope to compare `^arg(<name>)` instead of traversing
   the relationship:

   ```elixir
   scope :at_own_unit, expr(^arg(:center_id) in ^actor(:own_org_unit_ids))
   ```

3. Add a `resolve_argument` entity declaring the FK path:

   ```elixir
   resolve_argument :center_id, from_path: [:order, :center_id]
   ```

4. Ensure affected update/destroy actions have `require_atomic? false`
   — the injected change is non-atomic.
5. Ensure all callers pass `actor:` to `for_update/4`, `for_create/4`,
   `for_destroy/4`. The lazy change needs the actor to introspect
   permissions.
6. Drop the `write:` option.

### When you actually want different read/write semantics

Occasionally `write:` was used not as an escape hatch but to intentionally
diverge read and write rules ("users can *see* published posts but only
*edit* their own"). That's not what `write:` was for — model it as two
separate scopes:

```elixir
# Before — semantic misuse of write:
scope :readable_published,
  expr(status == :published),
  write: expr(author_id == ^actor(:id))

# After — two scopes, permissions mapped per-action
scope :published, expr(status == :published)
scope :own, expr(author_id == ^actor(:id))
```

Then grant `"post:*:read:published"` and `"post:*:update:own"`
separately. Per-action permissions are how AshGrant already expresses
this.

## `scope_resolver` → inline `scope` entities

**Deprecated since 0.7.** Still loads as a fallback for scopes not
defined inline.

### Why it exists

Early AshGrant used a `scope_resolver` module behaviour — you wrote a
module that mapped scope names to filter expressions at runtime:

```elixir
# Before
defmodule MyApp.PostScopeResolver do
  @behaviour AshGrant.ScopeResolver

  @impl true
  def resolve(:own, ctx), do: expr(author_id == ^actor(:id))
  def resolve(:published, _ctx), do: expr(status == :published)
end

ash_grant do
  resolver MyApp.PermissionResolver
  scope_resolver MyApp.PostScopeResolver
end
```

This worked, but inverted where scope logic lived: compile-time
expressions were authored in a separate runtime module, invisible to
the DSL introspection layer (`AshGrant.Info.scopes/1`,
`Introspect.available_permissions/1`, `explain/4`). Tooling couldn't
see the scopes.

### What replaces it

The inline `scope` entity inside the `ash_grant` block:

```elixir
# After
ash_grant do
  resolver MyApp.PermissionResolver

  scope :own, expr(author_id == ^actor(:id))
  scope :published, expr(status == :published)
end
```

Same filter expressions — just authored where the DSL can see them.
Every introspection, debugging, and testing surface now works against
them.

### Migration steps

1. For each scope your resolver module returns, add an equivalent
   `scope :name, expr(...)` entity inside `ash_grant do ... end`.
2. Translate any `ctx` the resolver module used:
   - `ctx.actor` → `^actor(:field)` inside `expr()`
   - `ctx.tenant` → `^tenant()`
   - Other values passed by the caller → `^context(:key)` (set at query
     time via `Ash.Query.set_context/2` or
     `Ash.Changeset.set_context/2`; see
     [Scopes: Context Injection](scopes.md#context-injection-context)).
3. Remove the `scope_resolver` option from `ash_grant do`.
4. Delete the resolver module (or keep it for any scopes you couldn't
   express inline — see the next section).

### Mixed mode during transition

If you can't migrate every scope at once, both can coexist. Inline scopes
take priority; any scope name not found inline falls back to
`scope_resolver`. An error is raised if a scope is in neither. That's
the safe state to run in while migrating one scope at a time.

```elixir
ash_grant do
  resolver MyApp.PermissionResolver
  scope_resolver MyApp.PostScopeResolver   # still here, falls back

  scope :own, expr(author_id == ^actor(:id))
  scope :published, expr(status == :published)
  # :legacy_scope still comes from the resolver module
end
```

### Why you can't skip migrating

The deprecated surface is maintained for backward compatibility but
does not participate in:

- `AshGrant.Introspect.available_permissions/1`
- `AshGrant.explain/4`'s matching/evaluated permission lists
- Policy testing assertions that reference scope metadata
- Admin dashboard and LLM tool surfaces

Any scope that stays in `scope_resolver` is invisible to those surfaces.

## `owner_field` option → `scope :own`

**Deprecated.** Scheduled for removal in 1.0.

### Why it exists

`owner_field :author_id` was a shorthand for "authorize writes where
`author_id == actor.id`." It ran ahead of the scope system and
pre-dated inline `expr()` scopes.

### What replaces it

A plain `:own` scope. Same behavior, participates in the introspection
surface, and composes with other scopes through inheritance.

```elixir
# Before
ash_grant do
  resolver MyApp.PermissionResolver
  owner_field :author_id
end

# After
ash_grant do
  resolver MyApp.PermissionResolver
  scope :own, expr(author_id == ^actor(:id))
end
```

Update resolvers to emit `"post:*:update:own"` (or whatever action)
instead of relying on the implicit `owner_field` check.

## See also

- [Scopes](scopes.md) — the inline `scope` DSL
- [Argument-Based Scope](argument-based-scope.md) — the `resolve_argument`
  pattern in depth
- [Advanced Patterns](advanced-patterns.md) — real-world recipes
  combining `resolve_argument` and `scope_through`
- [CHANGELOG](../CHANGELOG.md) — exact release each deprecation landed in
