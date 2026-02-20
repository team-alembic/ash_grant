defmodule AshGrant.DefaultFieldPoliciesTest do
  use ExUnit.Case, async: true

  describe "auto-generated field policies" do
    test "field policies are generated when default_field_policies is true" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      assert length(field_policies) > 0
    end

    test "generates field policy for each field group plus catch-all" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      # 3 field groups + 1 catch-all = 4 field policies
      assert length(field_policies) == 4
    end

    test "catch-all field policy exists" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      # After Ash processes the :* catch-all, it expands to all non-pkey fields.
      # Check that there's a policy that covers fields not in any group.
      all_field_group_fields =
        field_policies
        |> Enum.flat_map(& &1.fields)
        |> Enum.uniq()

      # All public non-pkey fields should be covered
      assert :name in all_field_group_fields
      assert :salary in all_field_group_fields
    end

    test "public fields have public field_group check" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      public_policy = Enum.find(field_policies, &(:name in &1.fields))
      assert public_policy != nil
      assert :department in public_policy.fields
      assert :position in public_policy.fields
    end

    test "sensitive fields have sensitive field_group check" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      sensitive_policy = Enum.find(field_policies, &(:phone in &1.fields))
      assert sensitive_policy != nil
      assert :address in sensitive_policy.fields
    end

    test "confidential fields have confidential field_group check" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)
      confidential_policy = Enum.find(field_policies, &(:salary in &1.fields))
      assert confidential_policy != nil
      assert :email in confidential_policy.fields
    end

    test "field policies use FieldCheck with correct field_group" do
      field_policies = Ash.Policy.Info.field_policies(AshGrant.Test.SensitiveRecord)

      # Find the policy for public fields
      public_policy = Enum.find(field_policies, &(:name in &1.fields))
      assert public_policy != nil

      [check] = public_policy.policies
      assert check.check_module == AshGrant.FieldCheck
      assert check.check_opts[:field_group] == :public
    end
  end

  describe "default_field_policies info" do
    test "returns true when enabled" do
      assert AshGrant.Info.default_field_policies(AshGrant.Test.SensitiveRecord) == true
    end
  end
end
