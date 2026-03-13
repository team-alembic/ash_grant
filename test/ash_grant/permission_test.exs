defmodule AshGrant.PermissionTest do
  use ExUnit.Case, async: true

  alias AshGrant.Permission

  describe "parse/1 - new four-part format" do
    test "parses full RBAC permission" do
      assert {:ok, perm} = Permission.parse("blog:*:read:all")
      assert perm.resource == "blog"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == "all"
      assert perm.deny == false
    end

    test "parses deny permission" do
      assert {:ok, perm} = Permission.parse("!blog:*:delete:all")
      assert perm.resource == "blog"
      assert perm.instance_id == "*"
      assert perm.action == "delete"
      assert perm.scope == "all"
      assert perm.deny == true
    end

    test "parses instance permission with empty scope" do
      assert {:ok, perm} = Permission.parse("blog:post_abc123xyz789ab:read:")
      assert perm.resource == "blog"
      assert perm.instance_id == "post_abc123xyz789ab"
      assert perm.action == "read"
      assert perm.scope == nil
      assert perm.deny == false
    end

    test "parses instance permission with wildcard action" do
      assert {:ok, perm} = Permission.parse("blog:post_abc123xyz789ab:*:")
      assert perm.resource == "blog"
      assert perm.instance_id == "post_abc123xyz789ab"
      assert perm.action == "*"
      assert perm.scope == nil
    end

    test "parses full wildcard permission" do
      assert {:ok, perm} = Permission.parse("*:*:*:all")
      assert perm.resource == "*"
      assert perm.instance_id == "*"
      assert perm.action == "*"
      assert perm.scope == "all"
    end

    test "parses action type wildcard" do
      assert {:ok, perm} = Permission.parse("blog:*:read*:all")
      assert perm.action == "read*"
    end
  end

  describe "parse/1 - legacy format compatibility" do
    test "parses legacy three-part format (resource:action:scope)" do
      assert {:ok, perm} = Permission.parse("blog:read:all")
      assert perm.resource == "blog"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == "all"
    end

    test "parses legacy two-part format (resource:action)" do
      assert {:ok, perm} = Permission.parse("blog:read")
      assert perm.resource == "blog"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == nil
    end

    test "parses legacy deny permission" do
      assert {:ok, perm} = Permission.parse("!blog:delete:all")
      assert perm.deny == true
      assert perm.instance_id == "*"
    end
  end

  describe "parse/1 - error handling" do
    test "returns error for single part" do
      assert {:error, _} = Permission.parse("invalid")
    end

    test "returns error for empty string" do
      assert {:error, _} = Permission.parse("")
    end
  end

  describe "parse!/1" do
    test "returns permission for valid string" do
      perm = Permission.parse!("blog:*:read:all")
      assert perm.resource == "blog"
    end

    test "raises for invalid string" do
      assert_raise ArgumentError, fn ->
        Permission.parse!("invalid")
      end
    end
  end

  describe "to_string/1" do
    test "converts RBAC permission to four-part format" do
      perm = %Permission{resource: "blog", instance_id: "*", action: "read", scope: "all"}
      assert Permission.to_string(perm) == "blog:*:read:all"
    end

    test "converts instance permission with empty scope" do
      perm = %Permission{resource: "blog", instance_id: "post_abc123", action: "read", scope: nil}
      assert Permission.to_string(perm) == "blog:post_abc123:read:"
    end

    test "converts deny permission" do
      perm = %Permission{
        resource: "blog",
        instance_id: "*",
        action: "delete",
        scope: "all",
        deny: true
      }

      assert Permission.to_string(perm) == "!blog:*:delete:all"
    end

    test "handles nil instance_id as *" do
      perm = %Permission{resource: "blog", instance_id: nil, action: "read", scope: "all"}
      assert Permission.to_string(perm) == "blog:*:read:all"
    end
  end

  describe "matches?/3 - RBAC matching" do
    test "matches exact resource and action" do
      perm = Permission.parse!("blog:*:read:all")
      assert Permission.matches?(perm, "blog", "read")
    end

    test "does not match different resource" do
      perm = Permission.parse!("blog:*:read:all")
      refute Permission.matches?(perm, "comment", "read")
    end

    test "does not match different action" do
      perm = Permission.parse!("blog:*:read:all")
      refute Permission.matches?(perm, "blog", "write")
    end

    test "matches wildcard resource" do
      perm = Permission.parse!("*:*:read:all")
      assert Permission.matches?(perm, "blog", "read")
      assert Permission.matches?(perm, "comment", "read")
    end

    test "matches wildcard action" do
      perm = Permission.parse!("blog:*:*:all")
      assert Permission.matches?(perm, "blog", "read")
      assert Permission.matches?(perm, "blog", "write")
      assert Permission.matches?(perm, "blog", "delete")
    end

    test "matches action type wildcard" do
      perm = Permission.parse!("blog:*:read*:all")
      assert Permission.matches?(perm, "blog", "read")
      assert Permission.matches?(perm, "blog", "read_all")
      assert Permission.matches?(perm, "blog", "read_published")
      refute Permission.matches?(perm, "blog", "write")
    end

    test "matches full wildcard" do
      perm = Permission.parse!("*:*:*:all")
      assert Permission.matches?(perm, "blog", "read")
      assert Permission.matches?(perm, "comment", "delete")
      assert Permission.matches?(perm, "anything", "any_action")
    end

    test "instance permission does not match RBAC query" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:read:")
      refute Permission.matches?(perm, "blog", "read")
    end
  end

  describe "matches_instance?/3" do
    test "matches instance permission" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:read:")
      assert Permission.matches_instance?(perm, "post_abc123xyz789ab", "read")
    end

    test "does not match different instance" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:read:")
      refute Permission.matches_instance?(perm, "post_xyz789abc123xy", "read")
    end

    test "does not match different action" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:read:")
      refute Permission.matches_instance?(perm, "post_abc123xyz789ab", "write")
    end

    test "matches instance wildcard action" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:*:")
      assert Permission.matches_instance?(perm, "post_abc123xyz789ab", "read")
      assert Permission.matches_instance?(perm, "post_abc123xyz789ab", "write")
    end

    test "RBAC permission does not match instance query" do
      perm = Permission.parse!("blog:*:read:all")
      refute Permission.matches_instance?(perm, "post_abc123xyz789ab", "read")
    end
  end

  describe "instance_permission?/1" do
    test "returns true for instance permission" do
      perm = Permission.parse!("blog:post_abc123xyz789ab:read:")
      assert Permission.instance_permission?(perm)
    end

    test "returns false for RBAC permission" do
      perm = Permission.parse!("blog:*:read:all")
      refute Permission.instance_permission?(perm)
    end
  end

  describe "deny?/1" do
    test "returns true for deny permission" do
      perm = Permission.parse!("!blog:*:delete:all")
      assert Permission.deny?(perm)
    end

    test "returns false for allow permission" do
      perm = Permission.parse!("blog:*:read:all")
      refute Permission.deny?(perm)
    end
  end

  describe "5-part format (field groups)" do
    test "parses 5-part permission string" do
      assert {:ok, perm} = Permission.parse("employee:*:read:all:sensitive")
      assert perm.resource == "employee"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == "all"
      assert perm.field_group == "sensitive"
      assert perm.deny == false
    end

    test "parses 5-part with deny" do
      assert {:ok, perm} = Permission.parse("!employee:*:read:all:confidential")
      assert perm.deny == true
      assert perm.field_group == "confidential"
      assert perm.resource == "employee"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == "all"
    end

    test "parses 4-part without field_group (backward compatible)" do
      assert {:ok, perm} = Permission.parse("employee:*:read:all")
      assert perm.field_group == nil
      assert perm.resource == "employee"
      assert perm.instance_id == "*"
      assert perm.action == "read"
      assert perm.scope == "all"
    end

    test "to_string includes field_group when present" do
      perm = %Permission{
        resource: "employee",
        instance_id: "*",
        action: "read",
        scope: "all",
        field_group: "sensitive"
      }

      assert Permission.to_string(perm) == "employee:*:read:all:sensitive"
    end

    test "to_string omits field_group when nil" do
      perm = %Permission{
        resource: "employee",
        instance_id: "*",
        action: "read",
        scope: "all",
        field_group: nil
      }

      assert Permission.to_string(perm) == "employee:*:read:all"
    end

    test "matches? works with 5-part permission" do
      perm = Permission.parse!("employee:*:read:all:sensitive")
      assert Permission.matches?(perm, "employee", "read")
    end

    test "parse round-trip with field_group" do
      {:ok, original} = Permission.parse("employee:*:read:all:sensitive")
      round_tripped = Permission.to_string(original)
      {:ok, reparsed} = Permission.parse(round_tripped)

      assert original.resource == reparsed.resource
      assert original.instance_id == reparsed.instance_id
      assert original.action == reparsed.action
      assert original.scope == reparsed.scope
      assert original.field_group == reparsed.field_group
      assert original.deny == reparsed.deny
    end

    test "5-part with instance permission" do
      assert {:ok, perm} = Permission.parse("employee:emp_123:read::sensitive")
      assert perm.resource == "employee"
      assert perm.instance_id == "emp_123"
      assert perm.action == "read"
      assert perm.scope == nil
      assert perm.field_group == "sensitive"
    end

    test "5-part with empty field_group" do
      assert {:ok, perm} = Permission.parse("employee:*:read:all:")
      assert perm.field_group == nil
    end

    test "5-part with action wildcard" do
      assert {:ok, perm} = Permission.parse("employee:*:*:all:sensitive")
      assert perm.resource == "employee"
      assert perm.action == "*"
      assert perm.scope == "all"
      assert perm.field_group == "sensitive"
    end

    test "5-part with action prefix wildcard" do
      assert {:ok, perm} = Permission.parse("employee:*:read*:all:sensitive")
      assert perm.action == "read*"
      assert perm.field_group == "sensitive"
      assert Permission.matches?(perm, "employee", "read")
      assert Permission.matches?(perm, "employee", "read_all")
      refute Permission.matches?(perm, "employee", "write")
    end

    test "5-part with resource wildcard" do
      assert {:ok, perm} = Permission.parse("*:*:read:all:sensitive")
      assert perm.resource == "*"
      assert perm.field_group == "sensitive"
      assert Permission.matches?(perm, "employee", "read")
      assert Permission.matches?(perm, "blog", "read")
    end

    test "5-part deny matches? returns true (deny flag is separate from matching)" do
      perm = Permission.parse!("!employee:*:read:all:sensitive")
      assert Permission.matches?(perm, "employee", "read")
      assert Permission.deny?(perm)
    end

    test "5-part instance permission roundtrip with scope" do
      {:ok, original} = Permission.parse("employee:emp_123:read:draft:sensitive")
      assert original.instance_id == "emp_123"
      assert original.scope == "draft"
      assert original.field_group == "sensitive"

      round_tripped = Permission.to_string(original)
      assert round_tripped == "employee:emp_123:read:draft:sensitive"

      {:ok, reparsed} = Permission.parse(round_tripped)
      assert reparsed.instance_id == original.instance_id
      assert reparsed.scope == original.scope
      assert reparsed.field_group == original.field_group
    end

    test "5-part instance permission with empty scope roundtrip" do
      {:ok, original} = Permission.parse("employee:emp_123:read::sensitive")
      str = Permission.to_string(original)
      {:ok, reparsed} = Permission.parse(str)

      assert reparsed.instance_id == "emp_123"
      assert reparsed.scope == nil
      assert reparsed.field_group == "sensitive"
    end
  end

  describe "matches_action?/3 with action_type" do
    test "read* matches :read type regardless of action name" do
      assert Permission.matches_action?("read*", "list_published", :read)
      assert Permission.matches_action?("read*", "by_slug", :read)
      assert Permission.matches_action?("read*", "search", :read)
    end

    test "read* still matches actions starting with read (string prefix)" do
      assert Permission.matches_action?("read*", "read", :read)
      assert Permission.matches_action?("read*", "read_all", :update)
      assert Permission.matches_action?("read*", "read_published", nil)
    end

    test "read* does NOT match :update type when name doesn't start with read" do
      refute Permission.matches_action?("read*", "list_published", :update)
      refute Permission.matches_action?("read*", "by_slug", :destroy)
    end

    test "update* matches :update type regardless of action name" do
      assert Permission.matches_action?("update*", "publish", :update)
      assert Permission.matches_action?("update*", "archive", :update)
    end

    test "create* matches :create type regardless of action name" do
      assert Permission.matches_action?("create*", "register", :create)
      assert Permission.matches_action?("create*", "signup", :create)
    end

    test "destroy* matches :destroy type regardless of action name" do
      assert Permission.matches_action?("destroy*", "soft_delete", :destroy)
      assert Permission.matches_action?("destroy*", "purge", :destroy)
    end

    test "exact match still works with action_type" do
      assert Permission.matches_action?("read", "read", :read)
      refute Permission.matches_action?("read", "list_published", :read)
    end

    test "wildcard * matches anything regardless of action_type" do
      assert Permission.matches_action?("*", "anything", :read)
      assert Permission.matches_action?("*", "anything", nil)
    end

    test "backward compat: 2-arg calls still work" do
      assert Permission.matches_action?("read*", "read_all")
      assert Permission.matches_action?("*", "anything")
      refute Permission.matches_action?("read", "write")
    end
  end

  describe "matches?/4 with action_type" do
    test "read* matches :read type action with non-prefixed name" do
      perm = Permission.parse!("blog:*:read*:all")
      assert Permission.matches?(perm, "blog", "list_published", :read)
    end

    test "read* does NOT match :update type with non-prefixed name" do
      perm = Permission.parse!("blog:*:read*:all")
      refute Permission.matches?(perm, "blog", "list_published", :update)
    end

    test "backward compat: 3-arg matches? still works" do
      perm = Permission.parse!("blog:*:read*:all")
      assert Permission.matches?(perm, "blog", "read_published")
      refute Permission.matches?(perm, "blog", "list_published")
    end

    test "instance permission still returns false for matches?/4" do
      perm = Permission.parse!("blog:post_abc123:read*:")
      refute Permission.matches?(perm, "blog", "list_published", :read)
    end
  end

  describe "String.Chars protocol" do
    test "converts to string" do
      perm = Permission.parse!("blog:*:read:all")
      assert "#{perm}" == "blog:*:read:all"
    end
  end
end
