defmodule AshGrant.ApplyMaskingTest do
  use ExUnit.Case, async: true

  describe "resolve_field_group masked_fields" do
    test "sensitive group has masked_fields for phone and address" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.MaskedRecord, :sensitive)
      assert result != nil
      assert Map.has_key?(result.masked_fields, :phone)
      assert Map.has_key?(result.masked_fields, :address)
    end

    test "confidential group has no masked_fields (masking not inherited)" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.MaskedRecord, :confidential)
      assert result != nil
      assert result.masked_fields == %{}
    end

    test "public group has no masked_fields" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.MaskedRecord, :public)
      assert result != nil
      assert result.masked_fields == %{}
    end

    test "masking function transforms values correctly" do
      result = AshGrant.Info.resolve_field_group(AshGrant.Test.MaskedRecord, :sensitive)
      phone_mask_fn = result.masked_fields[:phone]

      assert phone_mask_fn.("hello", :phone) == "*****"
      assert phone_mask_fn.(nil, :phone) == "***"
    end
  end

  describe "preparation registration" do
    test "MaskedRecord has the masking preparation registered" do
      preparations =
        Spark.Dsl.Extension.get_entities(AshGrant.Test.MaskedRecord, [:preparations])

      masking_preps =
        Enum.filter(preparations, fn prep ->
          match?({AshGrant.Preparations.ApplyMasking, _}, prep.preparation)
        end)

      assert length(masking_preps) == 1
    end

    test "SensitiveRecord does NOT have masking preparation (no masking defined)" do
      preparations =
        Spark.Dsl.Extension.get_entities(AshGrant.Test.SensitiveRecord, [:preparations])

      masking_preps =
        Enum.filter(preparations, fn prep ->
          match?({AshGrant.Preparations.ApplyMasking, _}, prep.preparation)
        end)

      assert masking_preps == []
    end
  end
end
