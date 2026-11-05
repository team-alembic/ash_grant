defmodule AshGrant.InstanceTypeWildcardTest do
  @moduledoc """
  Pins issue #131: instance-permission type wildcards are **live**, not dead.

  `matches_instance?/4` and the four instance-path evaluator entry points
  (`has_instance_access?/4`, `get_instance_scope/4`, `get_all_instance_scopes/4`,
  `get_matching_instance_ids/4`) all evaluate type wildcards when an `action_type`
  is supplied — the same grant that reads filters already honor. Without an
  `action_type` the wildcard cannot be evaluated; `AshGrant.IndeterminateMatch`
  reports that.

  `async: false` — the module reads `AshGrant.IndeterminateMatch` mode from the
  application environment.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshGrant.Evaluator
  alias AshGrant.IndeterminateMatch.IndeterminateMatchError
  alias AshGrant.Permission

  setup do
    original = Application.fetch_env(:ash_grant, :indeterminate_type_wildcard)
    Application.put_env(:ash_grant, :indeterminate_type_wildcard, :off)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:ash_grant, :indeterminate_type_wildcard, value)
        :error -> Application.delete_env(:ash_grant, :indeterminate_type_wildcard)
      end
    end)

    :ok
  end

  describe "matches_instance?/4 — type wildcards" do
    test "@read matches a read-type action when the type is supplied" do
      perm = Permission.parse!("doc:abc:@read:")

      assert Permission.matches_instance?(perm, "abc", "list_published", :read)
      assert Permission.matches_instance?(perm, "abc", "read", :read)
      refute Permission.matches_instance?(perm, "abc", "update", :update)
      refute Permission.matches_instance?(perm, "other", "read", :read)
    end

    test "the deprecated read* spelling behaves identically" do
      perm = Permission.parse!("doc:abc:read*:")

      assert Permission.matches_instance?(perm, "abc", "list_published", :read)
      refute Permission.matches_instance?(perm, "abc", "update", :update)
    end

    test "3-arity (no action_type) still cannot evaluate a type wildcard" do
      perm = Permission.parse!("doc:abc:@read:")

      refute Permission.matches_instance?(perm, "abc", "read")
    end
  end

  describe "get_matching_instance_ids/4 and matches_instance?/4 agree (#131)" do
    test "both paths return the live grant when action_type is supplied" do
      perms = ["doc:abc:@read:"]

      assert Evaluator.get_matching_instance_ids(perms, "doc", "read", :read) == ["abc"]
      assert Evaluator.has_instance_access?(perms, "abc", "read", :read)

      # Permission.diagnostics/1 no longer claims the grant is dead:
      assert Permission.diagnostics("doc:abc:@read:") == []
    end

    test "has_instance_access?/4 honors the type for a type wildcard" do
      perms = ["doc:abc:@read:"]

      assert Evaluator.has_instance_access?(perms, "abc", "list_published", :read)
      refute Evaluator.has_instance_access?(perms, "abc", "update", :update)
      refute Evaluator.has_instance_access?(perms, "other", "read", :read)
    end

    test "get_instance_scope/4 returns the scope for a type-wildcard grant" do
      perms = ["doc:abc:@read:business_hours"]

      assert Evaluator.get_instance_scope(perms, "abc", "list", :read) == "business_hours"
      assert Evaluator.get_instance_scope(perms, "abc", "update", :update) == nil
    end

    test "get_all_instance_scopes/4 collects scopes across matching type wildcards" do
      perms = ["doc:abc:@read:draft", "doc:abc:@read:internal"]

      scopes = Evaluator.get_all_instance_scopes(perms, "abc", "list", :read)
      assert Enum.sort(scopes) == ["draft", "internal"]
    end
  end

  describe "IndeterminateMatch reports the untyped instance-path call" do
    test "has_instance_access?/3 signals when an instance type wildcard was skipped" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :warn)

      log =
        capture_log(fn ->
          refute Evaluator.has_instance_access?(["doc:abc:@read:"], "abc", "read")
        end)

      assert log =~ "indeterminate authorization result"
      assert log =~ "doc:abc:@read:"
    end

    test "get_matching_instance_ids/3 raises in :strict when wildcards would add ids" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      assert_raise IndeterminateMatchError, fn ->
        Evaluator.get_matching_instance_ids(["doc:abc:@read:"], "doc", "read")
      end
    end

    test "silent when the action_type is supplied — everything was evaluable" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      assert Evaluator.has_instance_access?(["doc:abc:@read:"], "abc", "read", :read)

      assert Evaluator.get_matching_instance_ids(["doc:abc:@read:"], "doc", "read", :read) ==
               ["abc"]
    end

    test "silent for a literal instance grant — no wildcard involved" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      assert Evaluator.has_instance_access?(["doc:abc:read:"], "abc", "read")
      assert Evaluator.get_matching_instance_ids(["doc:abc:read:"], "doc", "read") == ["abc"]
    end

    test "silent when the type wildcard belongs to a different instance_id" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      # has_instance_access?/3 asked about `abc`, but the wildcard is on `other` — not
      # indeterminate for this specific call.
      refute Evaluator.has_instance_access?(["doc:other:@read:"], "abc", "read")
    end

    test "silent for a concrete deny that already settles the instance result" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      # The concrete deny wins regardless of how the @read wildcard would resolve.
      perms = ["!doc:abc:read:", "doc:abc:@read:"]
      refute Evaluator.has_instance_access?(perms, "abc", "read")
    end

    test "RBAC path stays silent for a wildcard whose instance_id makes it an instance perm" do
      Application.put_env(:ash_grant, :indeterminate_type_wildcard, :strict)

      # `doc:abc:@read:always` is an instance permission — the RBAC path's
      # Permission.matches?/4 excludes it, and no RBAC guard should signal.
      refute Evaluator.has_access?(["doc:abc:@read:always"], "doc", "read")
    end
  end

  describe "diagnostics/1 does not certify live grants as dead (#131)" do
    test "an instance-scoped @read wildcard reports no :dead_instance_type_wildcard" do
      codes =
        "doc:abc:@read:"
        |> Permission.diagnostics()
        |> Enum.map(& &1.code)

      refute :dead_instance_type_wildcard in codes
      assert codes == []
    end

    test "an instance-scoped read* reports only the deprecation" do
      codes =
        "doc:abc:read*:"
        |> Permission.diagnostics()
        |> Enum.map(& &1.code)

      refute :dead_instance_type_wildcard in codes
      assert codes == [:deprecated_type_wildcard]
    end

    test "deprecation suggestion for an instance grant points at the live @-spelling" do
      [d] = Permission.diagnostics("doc:abc:read*:")
      assert d.code == :deprecated_type_wildcard
      assert d.suggestion == "doc:abc:@read:"
      assert Permission.diagnostics(d.suggestion) == []
    end
  end
end
