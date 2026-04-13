defmodule AshGrant.ExprStringify do
  @moduledoc """
  Converts `Ash.Expr` terms and scope filter values into human-readable,
  LLM-friendly strings.

  Ash's default `Inspect` for expressions is already quite readable, but it
  uses internal reference tuples like `{:_actor, :id}` or `:_tenant`.
  Downstream consumers (the `AshGrant.Explanation` JSON surface, future
  Phoenix dashboard, and Ash AI tools) need strings that mirror the DSL
  syntax users write in their resources — `^actor(:id)`, `^tenant()`,
  `^context(:key)`.

  This module is **read-only and best-effort**: the output is a display
  string, never parsed back. Unknown terms fall back to `inspect/1` and the
  function never raises.

  ## Examples

      iex> AshGrant.ExprStringify.to_string(true)
      "true"

      iex> expr = AshGrant.Info.resolve_scope_filter(MyApp.Post, :own, %{})
      iex> AshGrant.ExprStringify.to_string(expr)
      "author_id == ^actor(:id)"

  ## Public API contract

  This module is part of AshGrant's public introspection surface consumed by
  `ash_grant_phoenix` and `ash_grant_ai`. Breaking changes are tracked in
  CHANGELOG.
  """

  @doc """
  Converts a scope filter value to a human-readable string.

  Accepts:
  - `true` / `false` / `nil`
  - `Ash.Expr` terms (any struct inspected via Ash's protocol)
  - Arbitrary Elixir terms (falls back to `inspect/1`)
  """
  @spec to_string(term()) :: String.t()
  def to_string(true), do: "true"
  def to_string(false), do: "false"
  def to_string(nil), do: "nil"

  def to_string(other) do
    other
    |> inspect(limit: :infinity, printable_limit: :infinity, structs: true)
    |> humanize()
  end

  # Replace internal reference tuples with their DSL-facing form.
  #
  # Why regex instead of walking the AST: Ash's own Inspect protocol already
  # handles nested operators, fragments, and refs readably. We just need to
  # unwrap the ^actor/^tenant/^context references so the output mirrors the
  # DSL. If Ash ever changes its inspect format, we tighten this here.
  defp humanize(str) do
    str
    |> String.replace(~r/\{:_actor,\s*:([a-zA-Z_][a-zA-Z0-9_]*)\}/, "^actor(:\\1)")
    |> String.replace(~r/\{:_context,\s*:([a-zA-Z_][a-zA-Z0-9_]*)\}/, "^context(:\\1)")
    |> String.replace(":_tenant", "^tenant()")
  end
end
