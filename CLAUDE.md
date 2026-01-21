# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AshGrant is a permission-based authorization extension for Ash Framework. It provides an Apache Shiro-inspired permission system with deny-wins semantics, supporting both RBAC and resource-instance permissions.

## Language Policy

**All repository content must be written in English**, including:
- README.md, CHANGELOG.md, and all documentation
- Code comments and docstrings (@moduledoc, @doc)
- Commit messages and PR descriptions
- CLAUDE.md instructions

## Common Commands

```bash
# Run tests (auto-creates and migrates test DB)
mix test

# Run a single test file
mix test test/ash_grant/permission_test.exs

# Run a specific test by line number
mix test test/ash_grant/permission_test.exs:42

# Linting
mix credo

# Type checking
mix dialyzer

# Generate documentation
mix docs

# Database management (test only)
mix ecto.setup    # Create and migrate
mix ecto.reset    # Drop, create, and migrate
```

## Architecture

### Core Modules

- **`AshGrant`** (`lib/ash_grant.ex`) - Main extension module, exports `check/1` and `filter_check/1`
- **`AshGrant.Dsl`** (`lib/ash_grant/dsl.ex`) - Spark DSL definition for the `ash_grant` block
- **`AshGrant.Permission`** (`lib/ash_grant/permission.ex`) - Parses and matches permission strings (`resource:instance_id:action:scope`)
- **`AshGrant.Evaluator`** (`lib/ash_grant/evaluator.ex`) - Implements deny-wins evaluation logic

### Policy Checks

- **`AshGrant.Check`** (`lib/ash_grant/checks/check.ex`) - SimpleCheck for write actions (returns true/false)
- **`AshGrant.FilterCheck`** (`lib/ash_grant/checks/filter_check.ex`) - FilterCheck for read actions (returns filter expression)

### Behaviours

- **`AshGrant.PermissionResolver`** - Behaviour for fetching actor permissions
- **`AshGrant.ScopeResolver`** - Legacy behaviour for custom scope resolution

### Transformers

- **`AshGrant.Transformers.AddDefaultPolicies`** - Auto-generates policies when `default_policies: true`

## Permission Format

```
[!]resource:instance_id:action:scope
```

- `!` prefix = deny rule
- `instance_id` = `*` for RBAC, specific ID for instance permissions
- Deny rules always override allow rules

## Key Patterns

### Scope DSL

Scopes are defined inline with `expr()` expressions:

```elixir
ash_grant do
  scope :all, true
  scope :own, expr(author_id == ^actor(:id))
  scope :own_draft, [:own], expr(status == :draft)  # Inherits from :own
end
```

### Multi-tenancy

Use `^tenant()` in scope expressions:

```elixir
scope :same_tenant, expr(tenant_id == ^tenant())
```

## Test Structure

- **Unit tests**: `test/ash_grant/permission_test.exs`, `evaluator_test.exs`
- **Property tests**: `permission_property_test.exs`, `evaluator_property_test.exs`
- **DB integration**: `db_integration_test.exs` (requires PostgreSQL)
- **Business scenarios**: `business_scenarios_test.exs` (8 authorization patterns)
- **Support files**: `test/support/` contains test resources, domain, repo, and generators

Tests require PostgreSQL. The test alias auto-runs `ecto.create` and `ecto.migrate`.

## Dependencies

- **Runtime**: `ash ~> 3.0`, `spark ~> 2.0`
- **Test only**: `ash_postgres`, `postgrex`, `simple_sat`

## Git Workflow

All changes must go through Pull Requests (no direct push to main).

### Branch Naming Convention

| Type | Branch Name | Example |
|------|-------------|---------|
| Feature | `feat/<description>` | `feat/sat-solver-callbacks` |
| Bug Fix | `fix/<description>` | `fix/in-operator-fallback` |
| Documentation | `docs/<description>` | `docs/update-readme` |
| Refactoring | `refactor/<description>` | `refactor/evaluator-cleanup` |
| Release | `release/v<version>` | `release/v0.4.1` |

### Feature

```bash
git checkout -b feat/my-feature
# Work on feature...
git push -u origin feat/my-feature
# Create PR → CI passes → Merge
```

### Fix

```bash
git checkout -b fix/bug-description
# Fix the bug...
mix test  # Local test
git push -u origin fix/bug-description
# Create PR → CI passes → Merge
```

### Release

```bash
git checkout -b release/v0.4.2
# 1. Update version in mix.exs
# 2. Update CHANGELOG.md (move Unreleased to new version)
git push -u origin release/v0.4.2
# Create PR → CI passes → Merge
# 3. Tag on main
git checkout main && git pull
git tag v0.4.2
git push --tags
```

### Commit Message Convention

```
<type>: <description>

Types: feat, fix, docs, refactor, test, release
```
