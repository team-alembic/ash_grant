defmodule AshGrant.IntrospectSummarizeActorTest do
  @moduledoc """
  Tests for `Introspect.summarize_actor/2` — the actor-wide access
  summary used by admin dashboards and LLM tools to answer
  "what can this user do across every registered resource?" in one call.
  """
  use ExUnit.Case, async: true

  alias AshGrant.Introspect

  describe "summarize_actor/2" do
    test "returns a list of per-resource summaries for the given actor" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      result =
        Introspect.summarize_actor(actor, resources: [AshGrant.Test.Post, AshGrant.Test.Employee])

      assert is_list(result)
      assert length(result) == 2

      post_summary = Enum.find(result, &(&1.resource == AshGrant.Test.Post))
      assert post_summary.resource_key == "post"
      assert :read in post_summary.allowed_actions
    end

    test "each summary has :resource, :resource_key, :allowed_actions, and :permissions" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      [summary | _] =
        Introspect.summarize_actor(actor, resources: [AshGrant.Test.Post])

      assert Map.has_key?(summary, :resource)
      assert Map.has_key?(summary, :resource_key)
      assert Map.has_key?(summary, :allowed_actions)
      assert Map.has_key?(summary, :permissions)

      assert is_list(summary.allowed_actions)
      assert Enum.all?(summary.allowed_actions, &is_atom/1)

      # :permissions mirrors actor_permissions/3 output
      assert is_list(summary.permissions)
      assert Enum.all?(summary.permissions, &Map.has_key?(&1, :action))
    end

    test "allowed_actions reflects actual grants, not all resource actions" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      [summary] =
        Introspect.summarize_actor(actor, resources: [AshGrant.Test.Post])

      assert :read in summary.allowed_actions
      # No update/create permission → those must not be in allowed_actions
      refute :update in summary.allowed_actions
      refute :destroy in summary.allowed_actions
    end

    test "returns summaries even for resources the actor has no access to" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      result =
        Introspect.summarize_actor(actor,
          resources: [AshGrant.Test.Post, AshGrant.Test.Employee]
        )

      employee_summary = Enum.find(result, &(&1.resource == AshGrant.Test.Employee))
      assert employee_summary != nil
      assert employee_summary.allowed_actions == []
    end

    test "with :only_with_access true, filters out resources with no allowed actions" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      result =
        Introspect.summarize_actor(actor,
          resources: [AshGrant.Test.Post, AshGrant.Test.Employee],
          only_with_access: true
        )

      assert length(result) == 1
      assert hd(result).resource == AshGrant.Test.Post
    end

    test "returns [] for a nil actor" do
      assert [] == Introspect.summarize_actor(nil)

      assert [] ==
               Introspect.summarize_actor(nil, resources: [AshGrant.Test.Post])
    end

    test "auto-discovers resources when no :resources or :domains option is given" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      result = Introspect.summarize_actor(actor)

      # Should include every AshGrant-enabled resource on the registered domains
      resource_modules = Enum.map(result, & &1.resource)
      assert AshGrant.Test.Post in resource_modules
      assert AshGrant.Test.Employee in resource_modules
    end

    test "respects :domains option to scope discovery" do
      actor = %{id: "u1", permissions: []}

      result = Introspect.summarize_actor(actor, domains: [AshGrant.Test.GrantDomain])

      resource_modules = Enum.map(result, & &1.resource)
      # GrantDomain only contains Domain* resources
      assert AshGrant.Test.DomainInheritedPost in resource_modules
      refute AshGrant.Test.Post in resource_modules
    end

    test "passes :context through to resolvers" do
      # The Post resource exposes a :today_injectable scope that uses
      # ^context(:reference_date) — passing a context should not crash.
      actor = %{id: "u1", permissions: ["post:*:read:today_injectable"]}

      result =
        Introspect.summarize_actor(actor,
          resources: [AshGrant.Test.Post],
          context: %{reference_date: ~D[2024-01-01]}
        )

      assert is_list(result)
      assert length(result) == 1
    end

    test "summaries are stable — every call returns the same shape" do
      actor = %{id: "u1", permissions: ["post:*:read:always"]}

      r1 = Introspect.summarize_actor(actor, resources: [AshGrant.Test.Post])
      r2 = Introspect.summarize_actor(actor, resources: [AshGrant.Test.Post])
      assert r1 == r2
    end
  end
end
