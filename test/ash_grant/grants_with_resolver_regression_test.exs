defmodule AshGrant.GrantsWithResolverRegressionTest do
  @moduledoc """
  Regression tests for the "grants declared on the domain + user-
  declared resolver" pattern that drives Clarity's Actor Explorer.

  Covers three bugs that landed together and then had to be unwound:

  * `Info.resolver/1` returns the synthesized `GrantsResolver` whenever
    grants are declared, so introspection layers that want the user's
    resolver (for `load_actor/1`) must route through `Info.raw_resolver/1`.

  * `Introspect.permissions_for/3` and `Explainer.get_permissions/3`
    both need to inject `:resource` into the context they hand the
    resolver — without it, `GrantsResolver` hits its fallback clause
    and returns `[]`, which made `actor_permissions` and `explain`
    disagree with each other (table said `allowed`, explain said
    `DENY (no_matching_permissions)`).

  * The identifier-based entry points (`actor_permissions_by_id/3`,
    `explain_by_identifier/1`, `can_by_identifier/3`) must look
    `load_actor/1` up on the user-declared resolver, not on
    `GrantsResolver`, because `GrantsResolver` is a generic module that
    cannot know how to hydrate app-specific actors.
  """
  use ExUnit.Case, async: true

  alias AshGrant.{Explainer, Info, Introspect}
  alias AshGrant.Test.{GrantsWithResolverLoader, GrantsWithResolverPost}

  @admin %{id: "admin", role: :admin}
  @viewer %{id: "viewer", role: :viewer}

  describe "Info.resolver/1 and raw_resolver/1 coexist" do
    test "resolver/1 returns the synthesized GrantsResolver when grants are declared" do
      assert Info.resolver(GrantsWithResolverPost) == AshGrant.GrantsResolver
    end

    test "raw_resolver/1 surfaces the user-declared resolver from the domain" do
      assert Info.raw_resolver(GrantsWithResolverPost) == GrantsWithResolverLoader
    end
  end

  describe "Info.resolve_permissions/3 (context helper)" do
    test "emits permissions from grants when actor matches predicate" do
      perms = Info.resolve_permissions(GrantsWithResolverPost, @admin)
      assert "grants_with_resolver_post:*:*:" in perms
    end

    test "returns an empty list when no grant predicate matches" do
      assert [] ==
               Info.resolve_permissions(GrantsWithResolverPost, %{id: "stranger", role: :unknown})
    end

    test "a base context without :resource is still routed correctly" do
      perms = Info.resolve_permissions(GrantsWithResolverPost, @viewer, %{source: "test"})
      assert "grants_with_resolver_post:*:read:" in perms
    end
  end

  describe "actor_permissions <-> explain parity" do
    test "every action the status table marks allowed is also :allow under explain" do
      {:ok, statuses} =
        Introspect.actor_permissions_by_id("admin", "grants_with_resolver_post")

      for %{action: action, allowed: allowed} <- statuses do
        {:ok, exp} =
          Introspect.explain_by_identifier(
            actor_id: "admin",
            resource_key: "grants_with_resolver_post",
            action: String.to_existing_atom(action)
          )

        expected = if allowed, do: :allow, else: :deny

        assert exp.decision == expected,
               "action #{action}: table=#{inspect(allowed)} explain=#{inspect(exp.decision)}"
      end
    end

    test "explainer produces matching_permissions drawn from the grants" do
      exp = Explainer.explain(GrantsWithResolverPost, :read, @viewer)

      assert exp.decision == :allow

      assert Enum.any?(
               exp.matching_permissions,
               &(&1.permission == "grants_with_resolver_post:*:read:")
             )
    end
  end

  describe "identifier-based lookups find load_actor on the user resolver" do
    test "actor_permissions_by_id hydrates actor and evaluates grants" do
      {:ok, statuses} =
        Introspect.actor_permissions_by_id("admin", "grants_with_resolver_post")

      # admin grant covers all actions on this resource
      assert Enum.all?(statuses, & &1.allowed),
             "expected every action allowed, got: #{inspect(statuses)}"
    end

    test "can_by_identifier returns :allow for a grant-covered action" do
      assert {:allow, _} =
               Introspect.can_by_identifier("viewer", "grants_with_resolver_post", :read)
    end

    test "can_by_identifier returns :deny for a grant-uncovered action" do
      assert {:deny, _} =
               Introspect.can_by_identifier("viewer", "grants_with_resolver_post", :update)
    end

    test "returns :actor_not_found when the user resolver has no actor for that id" do
      assert {:error, :actor_not_found} =
               Introspect.actor_permissions_by_id("nobody", "grants_with_resolver_post")
    end
  end
end
