defmodule AshGrant.PermissionValidationTest do
  @moduledoc """
  `AshGrant.PermissionValidation.validate/3` is a no-op since issue #117 was
  fixed. A deny carrying a `field_group` is now a valid field-visibility
  restriction — it subtracts only the named group's reach from the
  field-visibility layer and leaves the row-level read authorized. `validate/3`
  stays in place for API compatibility with the `field_group_permissions` DSL
  option; none of the modes raises or warns.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias AshGrant.PermissionValidation

  @deny_fg ["employee:*:read:always", "!employee:*:read:always:sensitive"]

  describe "validate/3 is a no-op in every mode" do
    test ":strict returns :ok and does not raise for a deny carrying a field_group" do
      assert PermissionValidation.validate(@deny_fg, :strict) == :ok
    end

    test ":warn returns :ok and logs nothing" do
      log = capture_log(fn -> assert PermissionValidation.validate(@deny_fg, :warn) == :ok end)
      refute log =~ "field_group"
    end

    test ":off returns :ok" do
      log = capture_log(fn -> assert PermissionValidation.validate(@deny_fg, :off) == :ok end)
      refute log =~ "field_group"
    end

    test "accepts raw permission strings and %Permission{} structs alike" do
      structs = Enum.map(@deny_fg, &AshGrant.Permission.parse!/1)
      assert PermissionValidation.validate(structs, :strict) == :ok
    end

    test "accepts a `resource:` option without raising" do
      assert PermissionValidation.validate(@deny_fg, :strict, resource: MyApp.Employee) == :ok
    end
  end
end
