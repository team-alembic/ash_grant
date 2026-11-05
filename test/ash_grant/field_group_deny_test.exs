defmodule AshGrant.FieldGroupDenyTest do
  @moduledoc """
  Field-group-qualified deny subtracts only the named field group (issue #117).

  A permission of the form `!resource:*:action:scope:field_group` is a
  field-visibility restriction, not an action restriction. It must leave the
  row-level read untouched and subtract exactly the named field group (and the
  groups that reach it through `inherits`) from the actor's visible-field set.

  Resource: `AshGrant.Test.SensitiveRecord`
  (`:public ⊂ :sensitive ⊂ :confidential`, scope `:always`).
  """
  use ExUnit.Case, async: true

  alias AshGrant.Evaluator
  alias AshGrant.Test.SensitiveRecord

  describe "Evaluator.has_access?/4" do
    test "a field-group-scoped deny does not block the whole action" do
      perms = [
        "sensitiverecord:*:read:always",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      assert Evaluator.has_access?(perms, "sensitiverecord", "read")
    end

    test "an action-wide deny (no field_group) still blocks the whole action" do
      perms = [
        "sensitiverecord:*:read:always",
        "!sensitiverecord:*:read:always"
      ]

      refute Evaluator.has_access?(perms, "sensitiverecord", "read")
    end

    test "a field-group deny alone still grants no row-level access" do
      perms = ["!sensitiverecord:*:read:always:sensitive"]
      refute Evaluator.has_access?(perms, "sensitiverecord", "read")
    end
  end

  describe "Evaluator.get_all_scopes/4 (row-level scopes)" do
    test "a field-group-scoped deny is not deny-wins at action level" do
      perms = [
        "sensitiverecord:*:read:always",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      assert Evaluator.get_all_scopes(perms, "sensitiverecord", "read") == ["always"]
    end

    test "an action-wide deny still clears the scope list" do
      perms = [
        "sensitiverecord:*:read:always",
        "!sensitiverecord:*:read:always"
      ]

      assert Evaluator.get_all_scopes(perms, "sensitiverecord", "read") == []
    end
  end

  describe "Evaluator.get_write_scopes/4" do
    test "a field-group deny does not make a write :denied" do
      perms = [
        "sensitiverecord:*:update:always",
        "!sensitiverecord:*:update:always:sensitive"
      ]

      assert Evaluator.get_write_scopes(perms, "sensitiverecord", "update") ==
               {:scopes, ["always"]}
    end

    test "an action-wide deny still returns :denied" do
      perms = [
        "sensitiverecord:*:update:always",
        "!sensitiverecord:*:update:always"
      ]

      assert Evaluator.get_write_scopes(perms, "sensitiverecord", "update") == :denied
    end
  end

  describe "Evaluator.field_group_grants/5" do
    test "a deny on the required group removes all contributing allows" do
      perms = [
        "sensitiverecord:*:read:always:sensitive",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      assert Evaluator.field_group_grants(perms, SensitiveRecord, "read", :sensitive) == []
    end

    test "a deny on one group does not touch an unrelated group" do
      perms = [
        "sensitiverecord:*:read:always:sensitive",
        "sensitiverecord:*:read:always:confidential",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      grants = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :confidential)
      assert [%{field_group: "confidential"}] = grants
    end

    test "a deny on :sensitive removes reach from a wider grant (:confidential)" do
      # :confidential inherits [:sensitive], so a grant for :confidential would
      # otherwise reach :sensitive. The deny for :sensitive removes that
      # reach: no grant can supply :sensitive. The same grant still supplies
      # :confidential and :public (the deny only names :sensitive).
      perms = [
        "sensitiverecord:*:read:always:confidential",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      assert Evaluator.field_group_grants(perms, SensitiveRecord, "read", :sensitive) == []

      confidential = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :confidential)
      assert [%{field_group: "confidential"}] = confidential

      public = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :public)
      assert [%{field_group: "confidential"}] = public
    end

    test "a deny on :public does not touch :sensitive or :confidential grants" do
      perms = [
        "sensitiverecord:*:read:always:sensitive",
        "!sensitiverecord:*:read:always:public"
      ]

      # The deny only names :public and only subtracts :public.
      grants = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :sensitive)
      assert [%{field_group: "sensitive"}] = grants

      assert Evaluator.field_group_grants(perms, SensitiveRecord, "read", :public) == []
    end

    test "a group-less allow is subtracted by a field-group deny for the targeted group" do
      perms = [
        "sensitiverecord:*:read:always",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      # The group-less grant would otherwise supply every group. The deny
      # removes :sensitive.
      assert Evaluator.field_group_grants(perms, SensitiveRecord, "read", :sensitive) == []

      # :confidential stays reachable through the group-less allow (the deny
      # only names :sensitive).
      grants = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :confidential)
      assert [%{field_group: nil}] = grants
    end

    test "an instance-scoped field-group deny only affects that instance's field group" do
      perms = [
        "sensitiverecord:*:read:always:sensitive",
        "!sensitiverecord:rec_x:read::sensitive"
      ]

      # The RBAC grant remains — the per-row deny on rec_x is handled by the
      # per-record predicate, not by subtracting every actor-wide allow.
      grants = Evaluator.field_group_grants(perms, SensitiveRecord, "read", :sensitive)
      assert [%{field_group: "sensitive", instance_id: "*"}] = grants
    end
  end

  describe "Evaluator.get_all_field_groups/4" do
    test "a field-group deny subtracts only the denied group" do
      perms = [
        "sensitiverecord:*:read:always:sensitive",
        "sensitiverecord:*:read:always:confidential",
        "!sensitiverecord:*:read:always:sensitive"
      ]

      assert Evaluator.get_all_field_groups(perms, "sensitiverecord", "read") ==
               ["confidential"]
    end

    test "a group-less allow with no denies still collapses to [] (unrestricted)" do
      perms = ["sensitiverecord:*:read:always"]
      assert Evaluator.get_all_field_groups(perms, "sensitiverecord", "read") == []
    end
  end

  describe "end-to-end — field policies" do
    setup do
      record =
        SensitiveRecord
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Alice",
            department: "Eng",
            position: "Dev",
            email: "a@x.com",
            phone: "010-1",
            address: "1 St",
            salary: 100
          },
          authorize?: false
        )
        |> Ash.create!()

      %{record: record}
    end

    test "field-group deny lets the read succeed and hides only the denied group",
         %{record: record} do
      actor = %{
        permissions: [
          "sensitiverecord:*:read:always",
          "!sensitiverecord:*:read:always:sensitive"
        ]
      }

      result =
        SensitiveRecord
        |> Ash.read!(actor: actor)
        |> Enum.find(&(&1.id == record.id))

      # The read succeeds (no Ash.Error.Forbidden).
      assert result != nil

      # :public fields remain visible — the deny named :sensitive only.
      assert result.name == "Alice"
      assert result.department == "Eng"
      assert result.position == "Dev"

      # :sensitive fields are forbidden on this row.
      assert match?(%Ash.ForbiddenField{}, result.phone)
      assert match?(%Ash.ForbiddenField{}, result.address)
    end

    test "action-wide deny still forbids the whole read (regression guard)" do
      actor = %{
        permissions: [
          "sensitiverecord:*:read:always",
          "!sensitiverecord:*:read:always"
        ]
      }

      assert_raise Ash.Error.Forbidden, fn ->
        SensitiveRecord |> Ash.read!(actor: actor)
      end
    end
  end
end
