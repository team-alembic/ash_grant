# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AshGrant is a permission-based authorization extension for Ash Framework. It provides an Apache Shiro-inspired permission system with deny-wins semantics, supporting both RBAC and resource-instance permissions.

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

### Branch Naming Convention

| 타입 | 브랜치명 | 예시 |
|------|---------|------|
| 기능 추가 | `feat/<description>` | `feat/sat-solver-callbacks` |
| 버그 수정 | `fix/<description>` | `fix/in-operator-fallback` |
| 문서 수정 | `docs/<description>` | `docs/update-readme` |
| 리팩토링 | `refactor/<description>` | `refactor/evaluator-cleanup` |
| 릴리스 | `release/v<version>` | `release/v0.4.1` |

### Feature (새 기능)

```bash
git checkout -b feat/my-feature
# 작업...
git push -u origin feat/my-feature
# PR 생성 → CI 통과 → Merge
```

### Fix (버그 수정)

```bash
git checkout -b fix/bug-description
# 수정...
mix test  # 로컬 테스트
git push -u origin fix/bug-description
# PR 생성 → CI 통과 → Merge
```

### Release (버전 릴리스)

```bash
git checkout -b release/v0.4.2
# 1. mix.exs 버전 수정
# 2. CHANGELOG.md 업데이트 (Unreleased → 버전)
git push -u origin release/v0.4.2
# PR 생성 → CI 통과 → Merge
# 3. main에서 태그
git checkout main && git pull
git tag v0.4.2
git push --tags
```

### Commit Message Convention

```
<type>: <description>

types: feat, fix, docs, refactor, test, release
```
