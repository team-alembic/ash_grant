# AshGrant

Permission-based authorization extension for [Ash Framework](https://ash-hq.org/).

AshGrant connects three Ash-native concepts — **resources**, **actions**, and
**`expr()` scopes** — through a permission string (`[!]resource:instance_id:action:scope[:field_group]`).
Permissions resolve to native Ash filters and policy checks, with deny-wins semantics.

**Authorization:**
- **Declarative `grants` DSL** — named grants pair an actor predicate (`expr(^actor(:role) == :admin)`) with a set of compile-time-verified permissions. The resolver is synthesized for you.
- **Domain-level DSL** — shared resolver and scopes inherited by all resources in a domain
- **Scope DSL** with `expr()` — row-level filters, `^tenant()` support
- **Argument-based scopes** with `resolve_argument` — multi-hop authorization via action arguments populated from the resource's own relationships, with lazy loading
- **Field groups** — column-level read access with inheritance and masking
- **Instance permissions** — per-record sharing with optional scope conditions
- **Deny-wins evaluation** — deny rules always override allows

**UI Integration:**
- **`CanPerform` calculation** — per-record boolean for UI visibility (compiles to SQL), with DSL sugar (`can_perform_actions`, `can_perform`)

**Verification & Tooling:**
- **`explain/4`** — trace why authorization succeeded or failed
- **`Introspect`** — query actor permissions, available actions at runtime
- **Policy testing** — DSL and YAML-based config tests, no database required

AshGrant handles permission evaluation, not role management. Resolve roles to
permission strings in your resolver.

## Installation

Add `ash_grant` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_grant, "~> 0.14"}
  ]
end
```

## Quick Start

### 1. Add the Extension to Your Resource

```elixir
defmodule MyApp.Blog.Post do
  use Ash.Resource,
    domain: MyApp.Blog,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    default_policies true  # Auto-generates read/write policies

    # Scopes define row-level filters (referenced by grants below)
    scope :always, true
    scope :own, expr(author_id == ^actor(:id))
    scope :published, expr(status == :published)

    # Grants pair an actor predicate with a set of compile-time-verified
    # permissions. AshGrant synthesizes the resolver from these.
    grants do
      grant :admin, expr(^actor(:role) == :admin) do
        permission :manage_all, :*, :always
      end

      grant :editor, expr(^actor(:role) == :editor) do
        permission :read_all,   :read,   :always
        permission :create_any, :create, :always
        permission :update_own, :update, :own
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        permission :read_published, :read, :published
      end
    end
  end

  # ... attributes, actions, etc.
end
```

**How it works:**
1. Actor (`%{role: :editor, id: "user_123"}`) matches the `:editor` grant's predicate
2. Each permission compiles to a string like `"post:*:update:own"` and references a scope by name
3. Compile-time verifier checks that every permission's action and scope exist on the resource
4. Scope `:own` adds filter `author_id == actor.id` to queries, Scope `:published` filters by status

### 2. Use It

```elixir
# Editor can read all posts
editor = %{id: "user_123", role: :editor}
Post |> Ash.read!(actor: editor)

# Editor can only update their own posts
Ash.update!(post, %{title: "New Title"}, actor: editor)
# => Succeeds if post.author_id == "user_123"
# => Fails if post.author_id != "user_123"

# Viewer can only read published posts
viewer = %{id: "user_456", role: :viewer}
Post |> Ash.read!(actor: viewer)
# => Returns only posts where status == :published
```

### Function-form resolver (escape hatch)

The `grants` DSL covers RBAC and most ABAC cases declaratively. For runtime
instance-specific permissions (e.g. per-row sharing fetched from a database),
use a `resolver` function instead — it's mutually exclusive with `grants`:

```elixir
ash_grant do
  resolver fn actor, _context ->
    MyApp.Accounts.load_permissions(actor)  # returns list of permission strings
  end

  scope :always, true
end
```

### Declare grants on the domain (or on resources — or both)

You can also put the `grants` block on an `Ash.Domain` using the
`AshGrant.Domain` extension. Every resource in the domain inherits the
domain's grants (and scopes), which is a clean way to centralize RBAC across
a bounded context without repeating the same grant on each resource:

```elixir
defmodule MyApp.Blog do
  use Ash.Domain, extensions: [AshGrant.Domain]

  ash_grant do
    scope :always, true
    scope :own, expr(author_id == ^actor(:id))

    grants do
      grant :admin, expr(^actor(:role) == :admin) do
        permission :manage_posts,    MyApp.Blog.Post,    :*, :always
        permission :manage_comments, MyApp.Blog.Comment, :*, :always
      end
    end
  end

  resources do
    resource MyApp.Blog.Post
    resource MyApp.Blog.Comment
  end
end
```

Resources and domains can both declare grants — they merge, with the
resource winning on grant-name conflicts. A domain grant's permissions must
name their target — either as the second positional argument (shown above)
or via the `on:` keyword option — since there's no enclosing resource to
default from.

## Guides

- **[Getting Started](guides/getting-started.md)** — Module-based resolvers, explicit policies, domain-level DSL, resolver patterns
- **[Permissions](guides/permissions.md)** — Permission format, wildcards, RBAC, instance permissions, instance_key, scope_through, deny-wins
- **[Scopes](guides/scopes.md)** — Scope DSL, combination rules, multi-tenancy, relational scopes, business examples
- **[Scope Naming Convention](guides/scope-naming-convention.md)** — Predicate naming, sentence test, RBAC/ABAC patterns, AND/OR composition
- **[Argument-Based Scope](guides/argument-based-scope.md)** — Multi-hop authorization via action arguments + resource-local lazy loading, avoids DB-query fallback
- **[Advanced Patterns](guides/advanced-patterns.md)** — Real-world recipes combining `resolve_argument` and `scope_through` (multi-hop writes, parent-shared children, both together)
- **[Field-Level Permissions](guides/field-level-permissions.md)** — Field groups, whitelist/blacklist modes, inheritance, masking
- **[Checks & Policies](guides/checks-and-policies.md)** — Check types, CanPerform calculations, DSL configuration, default_policies
- **[Debugging & Introspection](guides/debugging-and-introspection.md)** — explain/4, permission introspection, identifier-based lookups, expression stringification
- **[Policy Testing](guides/policy-testing.md)** — DSL and YAML tests, mix tasks, export/import
- **[Migration Guide](guides/migration.md)** — Moving off deprecated `write:`, `scope_resolver`, and `owner_field`

## Architecture

```
                    Ash Policy Check                Ash Calculation
                          |                              |
            +-------------+-------------+--------+  +---v-----------+
            |                           |        |  | CanPerform    |
      +-----v-----+              +------v------+ |  | (UI booleans) |
      |  Check    |              | FilterCheck | |  +---+-----------+
      | (writes)  |              |  (reads)    | |      |
      +-----+-----+              +------+------+ |      |
            |                           |        |      |
            +-----------+---------------+-+------+------+
                        |
            +-----------v-----------+
            | PermissionResolver    |
            | (actor -> permissions)|
            +-----------+-----------+
                        |
            +-----------v-----------+
            | Evaluator             |
            | (deny-wins matching)  |
            +-----------+-----------+
                        |
            +-----------v-----------+
            | Scope DSL / Field     |
            | Groups / Resolver     |
            +-----------------------+
```

## Disclosure

  I've been a developer for about six years. I became interested in Elixir, Phoenix, and Ash a couple of years ago, but only started actually building with
  them about four months ago. This library was born out of my own needs, and honestly, my skills in this ecosystem aren't at the level where I'd normally
  attempt building something like this.

  Most of AshGrant was developed through TDD with Claude Code—I described what I needed, Claude Code wrote the tests and implementation, and I reviewed the
  results. I treated it like any third-party library: if the tests pass and the code looks reasonable, I use it. I haven't read every line of code in detail,
  so I can't guarantee everything works perfectly.

  I'm using this in production because I need it now, but please consider this more as a **proof of concept**—a proposal for how authorization could be handled
   in Ash. I'm sharing this publicly in hopes that it can be a starting point. If others find it useful and want to contribute, we could build something better
   together.

  If you have suggestions or find issues, please feel free to open an issue or submit a PR—contributions are very welcome.

  What made this possible is how exceptionally well-documented Elixir and Ash are. The clear abstractions—DSLs, Domains, Resources, Extensions—gave me a
  precise vocabulary to communicate my requirements to an LLM. These well-defined concepts provided both the courage to start and the foundation to actually
  ship something I use in production.

  I'm deeply grateful to Zach for creating Ash Framework, the Ash Core Team, all the contributors, and the broader Elixir community. We have something special
  here.

## License

MIT License - see [LICENSE](LICENSE) for details.
