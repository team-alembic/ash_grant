defmodule AshGrant.FieldGroupPermissionsTest do
  @moduledoc """
  Config + end-to-end coverage for the `field_group_permissions` option
  (issue #117, phase ①): a deny rule carrying a field_group is invalid and is
  signaled per the configured mode, without changing the (already fail-closed)
  authorization outcome.
  """
  # async: false because one test mutates the global :ash_grant app-env.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias AshGrant.Test.{SensitiveRecord, StrictFieldGroupRecord}

  describe "AshGrant.Info.field_group_permissions/1" do
    test "returns the resource-level option when set" do
      assert AshGrant.Info.field_group_permissions(StrictFieldGroupRecord) == :strict
    end

    test "defaults to :warn when unset on the resource" do
      assert AshGrant.Info.field_group_permissions(SensitiveRecord) == :warn
    end

    test "falls back to the global app-env when no resource option is set" do
      Application.put_env(:ash_grant, :field_group_permissions, :strict)
      on_exit(fn -> Application.delete_env(:ash_grant, :field_group_permissions) end)

      assert AshGrant.Info.field_group_permissions(SensitiveRecord) == :strict
    end
  end

  describe "end-to-end :strict resource — field_group_permissions is dormant since #117" do
    setup do
      record =
        StrictFieldGroupRecord
        |> Ash.Changeset.for_create(
          :create,
          %{name: "Alice", department: "Eng", phone: "010-1", address: "1 St"},
          authorize?: false
        )
        |> Ash.create!()

      %{record: record}
    end

    test "a deny rule carrying a field_group reads normally and hides the named group",
         %{record: record} do
      actor = %{
        permissions: [
          "strictfieldgrouprecord:*:read:always",
          "!strictfieldgrouprecord:*:read:always:sensitive"
        ]
      }

      # The deny is a valid field-group restriction now. The row-level read
      # succeeds; only `:sensitive` fields are hidden.
      log =
        capture_log(fn ->
          result =
            StrictFieldGroupRecord
            |> Ash.read!(actor: actor)
            |> Enum.find(&(&1.id == record.id))

          assert result != nil
          assert result.name == "Alice"
          assert result.department == "Eng"
          assert match?(%Ash.ForbiddenField{}, result.phone)
        end)

      refute log =~ "deny rules cannot carry a field_group"
    end

    test "a valid allow + field_group permission reads normally", %{record: record} do
      actor = %{permissions: ["strictfieldgrouprecord:*:read:always:sensitive"]}

      result =
        StrictFieldGroupRecord
        |> Ash.read!(actor: actor)
        |> Enum.find(&(&1.id == record.id))

      assert result != nil
      assert result.name == "Alice"
      assert result.phone == "010-1"
    end
  end

  describe "end-to-end default :warn resource" do
    setup do
      record =
        SensitiveRecord
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "John",
            department: "Eng",
            position: "Dev",
            email: "j@x.com",
            phone: "010-2",
            address: "2 St",
            salary: 100
          },
          authorize?: false
        )
        |> Ash.create!()

      %{record: record}
    end

    test "a deny rule carrying a field_group lets the row read and hides only that group",
         %{record: record} do
      actor = %{
        permissions: [
          "sensitiverecord:*:read:always",
          "!sensitiverecord:*:read:always:sensitive"
        ]
      }

      log =
        capture_log(fn ->
          result =
            SensitiveRecord
            |> Ash.read!(actor: actor)
            |> Enum.find(&(&1.id == record.id))

          assert result != nil
          # :public fields stay visible.
          assert result.name == "John"
          assert result.position == "Dev"
          # :sensitive fields are hidden by the field-group deny.
          assert match?(%Ash.ForbiddenField{}, result.phone)
          assert match?(%Ash.ForbiddenField{}, result.address)
        end)

      refute log =~ "deny rules cannot carry a field_group"
    end
  end
end
