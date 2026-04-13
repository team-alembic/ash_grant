defmodule AshGrant.IntrospectByIdentifierTest do
  @moduledoc """
  Tests for identifier-based introspection entry points.

  These functions let external consumers (admin dashboards, LLM tools,
  `mix ash_grant.explain` task) drive AshGrant using only string/ID
  inputs — no module references, no fully-hydrated actor structs. The
  core flow is:

      resource_key (string) → resource module (via find_resource_by_key)
      actor_id (term)       → actor struct (via resolver.load_actor/1)
      then delegate to explain/3, can?/4, actor_permissions/3.
  """
  use ExUnit.Case, async: true

  alias AshGrant.{Explanation, Introspect}

  describe "explain_by_identifier/1" do
    test "returns {:ok, Explanation} when resolver loads the actor and allows action" do
      assert {:ok, %Explanation{} = exp} =
               Introspect.explain_by_identifier(
                 actor_id: "user_1",
                 resource_key: "id_loadable_post",
                 action: :read
               )

      assert exp.decision == :allow
      assert exp.action == :read
      # Actor was hydrated from the resolver — not a raw ID
      assert is_map(exp.actor)
      assert exp.actor.id == "user_1"
    end

    test "returns {:ok, Explanation} with scope_filter when scope applies" do
      assert {:ok, exp} =
               Introspect.explain_by_identifier(
                 actor_id: "user_2",
                 resource_key: "id_loadable_post",
                 action: :update
               )

      assert exp.decision == :allow
      assert is_binary(exp.scope_filter_string)
      assert exp.scope_filter_string =~ "^actor(:id)"
    end

    test "accepts an optional :context keyword" do
      assert {:ok, exp} =
               Introspect.explain_by_identifier(
                 actor_id: "user_1",
                 resource_key: "id_loadable_post",
                 action: :read,
                 context: %{source: "admin_ui"}
               )

      assert exp.decision == :allow
    end

    test "returns {:error, :unknown_resource} when resource_key has no match" do
      assert {:error, :unknown_resource} =
               Introspect.explain_by_identifier(
                 actor_id: "user_1",
                 resource_key: "definitely_not_a_resource",
                 action: :read
               )
    end

    test "returns {:error, :actor_not_found} when load_actor/1 returns :error" do
      assert {:error, :actor_not_found} =
               Introspect.explain_by_identifier(
                 actor_id: "missing_user",
                 resource_key: "id_loadable_post",
                 action: :read
               )
    end

    test "returns {:error, :actor_loader_not_implemented} when resolver module lacks load_actor/1" do
      assert {:error, :actor_loader_not_implemented} =
               Introspect.explain_by_identifier(
                 actor_id: "user_1",
                 resource_key: "no_load_actor_post",
                 action: :read
               )
    end

    test "returns {:error, :actor_loader_not_implemented} when resolver is an anonymous function" do
      # AshGrant.Test.Post uses an inline fn resolver, which cannot define
      # a load_actor/1 callback.
      assert {:error, :actor_loader_not_implemented} =
               Introspect.explain_by_identifier(
                 actor_id: "user_1",
                 resource_key: "post",
                 action: :read
               )
    end
  end

  describe "can_by_identifier/3" do
    test "returns {:allow, details} when actor is loaded and action is allowed" do
      assert {:allow, details} =
               Introspect.can_by_identifier("user_1", "id_loadable_post", :read)

      assert details.scope == "always"
    end

    test "returns {:deny, %{reason: :no_permission}} when actor has no matching permission" do
      # user_1 has only "post:*:read:always" — update is not granted
      assert {:deny, %{reason: :no_permission}} =
               Introspect.can_by_identifier("user_1", "id_loadable_post", :update)
    end

    test "returns {:error, :unknown_resource} for an unknown resource key" do
      assert {:error, :unknown_resource} =
               Introspect.can_by_identifier("user_1", "definitely_not_a_resource", :read)
    end

    test "returns {:error, :actor_not_found} when actor id does not resolve" do
      assert {:error, :actor_not_found} =
               Introspect.can_by_identifier("missing_user", "id_loadable_post", :read)
    end

    test "returns {:error, :actor_loader_not_implemented} when resolver can't load actors" do
      assert {:error, :actor_loader_not_implemented} =
               Introspect.can_by_identifier("user_1", "no_load_actor_post", :read)
    end

    test "accepts a keyword context option" do
      assert {:allow, _details} =
               Introspect.can_by_identifier("user_1", "id_loadable_post", :read,
                 context: %{source: "admin_ui"}
               )
    end
  end

  describe "actor_permissions_by_id/2" do
    test "returns {:ok, statuses} listing each action with allow/deny" do
      assert {:ok, statuses} =
               Introspect.actor_permissions_by_id("user_1", "id_loadable_post")

      assert is_list(statuses)
      assert Enum.all?(statuses, &is_map/1)
      assert Enum.all?(statuses, &Map.has_key?(&1, :action))
      assert Enum.all?(statuses, &Map.has_key?(&1, :allowed))

      read_status = Enum.find(statuses, &(&1.action == "read"))
      assert read_status.allowed == true
    end

    test "returns {:error, :unknown_resource} for an unknown resource_key" do
      assert {:error, :unknown_resource} =
               Introspect.actor_permissions_by_id("user_1", "definitely_not_a_resource")
    end

    test "returns {:error, :actor_not_found} when the actor id does not resolve" do
      assert {:error, :actor_not_found} =
               Introspect.actor_permissions_by_id("missing_user", "id_loadable_post")
    end

    test "returns {:error, :actor_loader_not_implemented} when resolver can't load actors" do
      assert {:error, :actor_loader_not_implemented} =
               Introspect.actor_permissions_by_id("user_1", "no_load_actor_post")
    end
  end
end
