defmodule AshGrant.FieldGroupResolutionTest do
  use ExUnit.Case, async: true

  describe "resolve_field_group/2" do
    test "resolves root field group to its fields" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.SensitiveRecord, :public)
      assert result != nil
      assert Enum.sort(result.fields) == [:department, :name, :position]
      assert result.masked_fields == %{}
    end

    test "resolves inherited field group (union of parent + own)" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.SensitiveRecord, :sensitive)
      assert result != nil
      assert Enum.sort(result.fields) == [:address, :department, :name, :phone, :position]
      assert result.masked_fields == %{}
    end

    test "resolves deeply inherited field group" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.SensitiveRecord, :confidential)
      assert result != nil

      assert Enum.sort(result.fields) == [
               :address,
               :department,
               :email,
               :name,
               :phone,
               :position,
               :salary
             ]

      assert result.masked_fields == %{}
    end

    test "returns nil for unknown field group" do
      assert AshGrant.Info.resolve_field_group(AshGrant.Test.SensitiveRecord, :nonexistent) == nil
    end

    test "inherited fields come before own fields" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.SensitiveRecord, :sensitive)
      # Parent fields first, then own
      parent_fields = [:name, :department, :position]
      own_fields = [:phone, :address]
      for f <- parent_fields, do: assert(f in result.fields)
      for f <- own_fields, do: assert(f in result.fields)
    end
  end
end
