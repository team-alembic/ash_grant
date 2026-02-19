defmodule AshGrant.ValidateFieldGroupsTest do
  use ExUnit.Case, async: true

  test "valid field groups compile without error" do
    # SensitiveRecord has valid field group definitions (no cycles, no missing parents)
    assert AshGrant.Info.field_groups(AshGrant.Test.SensitiveRecord) |> length() == 3
  end

  test "field groups have correct inheritance chain" do
    fg = AshGrant.Info.get_field_group(AshGrant.Test.SensitiveRecord, :confidential)
    assert fg.inherits == [:sensitive]
  end
end
