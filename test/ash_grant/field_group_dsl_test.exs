defmodule AshGrant.FieldGroupDslTest do
  use ExUnit.Case, async: true

  alias AshGrant.Dsl.FieldGroup

  describe "FieldGroup struct" do
    test "creates a basic field group with name and fields" do
      fg = %FieldGroup{
        name: :public,
        fields: [:title, :body, :status]
      }

      assert fg.name == :public
      assert fg.fields == [:title, :body, :status]
    end

    test "creates a field group with inheritance" do
      fg = %FieldGroup{
        name: :internal,
        fields: [:salary, :ssn],
        inherits: [:public]
      }

      assert fg.name == :internal
      assert fg.fields == [:salary, :ssn]
      assert fg.inherits == [:public]
    end

    test "creates a field group with masking" do
      mask_fn = fn _value, _field_name -> "***" end

      fg = %FieldGroup{
        name: :sensitive,
        fields: [:email, :phone, :ssn],
        mask: [:ssn, :phone],
        mask_with: mask_fn
      }

      assert fg.name == :sensitive
      assert fg.fields == [:email, :phone, :ssn]
      assert fg.mask == [:ssn, :phone]
      assert is_function(fg.mask_with, 2)
      assert fg.mask_with.("secret", :ssn) == "***"
    end

    test "optional fields default to nil" do
      fg = %FieldGroup{
        name: :basic,
        fields: [:title]
      }

      assert fg.name == :basic
      assert fg.fields == [:title]
      assert fg.inherits == nil
      assert fg.mask == nil
      assert fg.mask_with == nil
      assert fg.description == nil
      assert fg.__spark_metadata__ == nil
    end

    test "creates a field group with description" do
      fg = %FieldGroup{
        name: :public,
        fields: [:title, :body],
        description: "Fields visible to all users"
      }

      assert fg.description == "Fields visible to all users"
    end

    test "creates a field group with all fields populated" do
      mask_fn = fn value, _field -> String.slice(to_string(value), 0, 1) <> "***" end

      fg = %FieldGroup{
        name: :confidential,
        fields: [:email, :phone, :address],
        inherits: [:public, :internal],
        mask: [:phone, :address],
        mask_with: mask_fn,
        description: "Confidential fields with partial masking",
        __spark_metadata__: %{line: 42}
      }

      assert fg.name == :confidential
      assert fg.fields == [:email, :phone, :address]
      assert fg.inherits == [:public, :internal]
      assert fg.mask == [:phone, :address]
      assert fg.mask_with.("secret", :phone) == "s***"
      assert fg.description == "Confidential fields with partial masking"
      assert fg.__spark_metadata__ == %{line: 42}
    end
  end

  describe "field_group in DSL" do
    alias AshGrant.Test.SensitiveRecord

    test "SensitiveRecord compiles with field_group definitions" do
      assert Code.ensure_loaded?(SensitiveRecord)
    end

    test "field_groups/1 returns all 3 field groups" do
      groups = AshGrant.Info.field_groups(SensitiveRecord)
      assert length(groups) == 3
      names = Enum.map(groups, & &1.name)
      assert :public in names
      assert :sensitive in names
      assert :confidential in names
    end

    test "get_field_group/2 returns the correct field group" do
      fg = AshGrant.Info.get_field_group(SensitiveRecord, :public)
      assert %FieldGroup{} = fg
      assert fg.name == :public
      assert fg.fields == [:name, :department, :position]
    end

    test "get_field_group/2 returns nil for unknown group" do
      assert AshGrant.Info.get_field_group(SensitiveRecord, :nonexistent) == nil
    end

    test "field group with inheritance has correct inherits value" do
      fg = AshGrant.Info.get_field_group(SensitiveRecord, :sensitive)
      assert fg.inherits == [:public]
      assert fg.fields == [:phone, :address]
    end

    test "field group with nested inheritance has correct inherits value" do
      fg = AshGrant.Info.get_field_group(SensitiveRecord, :confidential)
      assert fg.inherits == [:sensitive]
      assert fg.fields == [:salary, :email]
    end

    test "field group without inheritance has nil inherits" do
      fg = AshGrant.Info.get_field_group(SensitiveRecord, :public)
      assert fg.inherits == nil
    end
  end
end
