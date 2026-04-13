defmodule AshGrant.ExprStringifyTest do
  @moduledoc """
  Tests for ExprStringify — converting Ash.Expr terms to human/LLM-readable
  strings.

  These strings are surfaced in JSON output (Explanation.scope_filter_string)
  and LLM tool responses, so the format must be predictable and use the DSL
  syntax users wrote, not the internal reference tuples.
  """
  use ExUnit.Case, async: true

  alias AshGrant.ExprStringify

  describe "to_string/1 — scalars" do
    test "true → \"true\"" do
      assert ExprStringify.to_string(true) == "true"
    end

    test "false → \"false\"" do
      assert ExprStringify.to_string(false) == "false"
    end

    test "nil → \"nil\"" do
      assert ExprStringify.to_string(nil) == "nil"
    end
  end

  describe "to_string/1 — reference humanization" do
    test "humanizes actor references to ^actor(:key)" do
      expr = AshGrant.Info.resolve_scope_filter(AshGrant.Test.Post, :own, %{})
      assert ExprStringify.to_string(expr) == "author_id == ^actor(:id)"
    end

    test "humanizes tenant reference to ^tenant()" do
      expr =
        AshGrant.Info.resolve_scope_filter(AshGrant.Test.TenantPost, :same_tenant, %{})

      assert ExprStringify.to_string(expr) == "tenant_id == ^tenant()"
    end

    test "humanizes context references to ^context(:key)" do
      ctx = %{reference_date: ~D[2024-01-01]}
      expr = AshGrant.Info.resolve_scope_filter(AshGrant.Test.Post, :today_injectable, ctx)
      result = ExprStringify.to_string(expr)

      assert result =~ "^context(:reference_date)"
      refute result =~ ":_context"
    end
  end

  describe "to_string/1 — robustness" do
    test "always returns a binary" do
      expr = AshGrant.Info.resolve_scope_filter(AshGrant.Test.Post, :own, %{})
      assert is_binary(ExprStringify.to_string(expr))
    end

    test "accepts unknown terms and does not raise" do
      # Arbitrary term — should fall back to inspect-like output without crashing
      assert is_binary(ExprStringify.to_string({:some, :tuple, [1, 2, 3]}))
      assert is_binary(ExprStringify.to_string(%{arbitrary: "map"}))
    end
  end
end
