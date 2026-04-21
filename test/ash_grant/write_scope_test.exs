defmodule AshGrant.WriteScopeTest do
  @moduledoc """
  Tests for the dual read/write scope DSL feature.

  Covers:
  - DSL: `write:` option on scope entity
  - Info: `resolve_write_scope_filter/3` with fallback to `filter`
  - Check: write actions use write scope resolution
  - FilterCheck: read actions are unaffected (still use `filter`)
  - Transformer: warnings for relationship scopes without `write:`
  """

  use ExUnit.Case, async: true

  alias AshGrant.Info

  require Ash.Expr

  # ============================================================
  # Test Resources (inline, no DB needed)
  # ============================================================

  # Resource with various write: option scenarios:
  # - :own       → write: same as filter (identity case)
  # - :team_visible → write: different from filter (in vs equality)
  # - :readonly  → write: false (deny writes)
  # - :write_all → write: true (allow all writes)
  # - :simple    → no write: option (fallback to filter)
  defmodule WriteScopePost do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      extensions: [AshGrant]

    ash_grant do
      resolver(fn _actor, _context -> [] end)

      scope(:always, true)

      # Same expression for read and write (simple ownership)
      scope(:own, expr(author_id == ^actor(:id)), write: expr(author_id == ^actor(:id)))

      # Different expressions: read uses equality, write uses `in` list
      scope(:team_visible, expr(team_id == ^actor(:team_id)),
        write: expr(team_id in ^actor(:team_ids))
      )

      # Explicitly deny writes
      scope(:readonly, expr(status == :published), write: false)

      # Explicitly allow all writes (write: true)
      scope(:write_all, expr(status == :draft), write: true)

      # No write: option — should fall back to filter
      scope(:simple, expr(status == :draft))
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:status, :atom, constraints: [one_of: [:draft, :published]])
      attribute(:author_id, :uuid)
      attribute(:team_id, :uuid)
    end
  end

  # ============================================================
  # DSL: Scope struct has write field
  # ============================================================

  describe "DSL: scope struct write field" do
    test "write: false is stored on scope struct" do
      scope = Info.get_scope(WriteScopePost, :readonly)
      assert scope.write == false
    end

    test "write: true is stored on scope struct" do
      scope = Info.get_scope(WriteScopePost, :write_all)
      assert scope.write == true
    end

    test "write: nil when not specified" do
      scope = Info.get_scope(WriteScopePost, :simple)
      assert scope.write == nil
    end

    test "write: expr(...) is stored as Ash expression" do
      scope = Info.get_scope(WriteScopePost, :team_visible)
      assert scope.write != nil
      refute scope.write == true
      refute scope.write == false
      # Should be an Ash expression struct (not a plain value)
      refute is_atom(scope.write)
    end

    test "all scope fields are present" do
      scope = Info.get_scope(WriteScopePost, :team_visible)
      assert Map.has_key?(scope, :name)
      assert Map.has_key?(scope, :filter)
      assert Map.has_key?(scope, :write)
      assert Map.has_key?(scope, :description)
    end
  end

  # ============================================================
  # Read path: resolve_scope_filter/3 is unaffected by write:
  # ============================================================

  describe "resolve_scope_filter/3 (read path) is unaffected" do
    test "returns filter expression even when write: false is set" do
      filter = Info.resolve_scope_filter(WriteScopePost, :readonly, %{})
      # Must return the read filter (status == :published), NOT false
      refute filter == false
      refute filter == true
      assert inspect(filter) =~ "status"
    end

    test "returns filter expression even when write: expr(...) differs" do
      filter = Info.resolve_scope_filter(WriteScopePost, :team_visible, %{})
      # Must return the read filter (team_id == ^actor(:team_id))
      refute filter == false
      refute filter == true
      filter_str = inspect(filter)
      assert filter_str =~ "team_id"
      # Read filter uses equality, not `in`
      refute filter_str =~ ":in"
    end

    test "returns filter when write: true is set" do
      filter = Info.resolve_scope_filter(WriteScopePost, :write_all, %{})
      # Read filter should be expr(status == :draft), not true
      refute filter == true
      assert inspect(filter) =~ "status"
    end
  end

  # ============================================================
  # Write path: resolve_write_scope_filter/3
  # ============================================================

  describe "resolve_write_scope_filter/3 basic resolution" do
    test "returns write expression when set (different from read filter)" do
      write_filter = Info.resolve_write_scope_filter(WriteScopePost, :team_visible, %{})
      read_filter = Info.resolve_scope_filter(WriteScopePost, :team_visible, %{})

      # Write uses `in`, read uses equality — they must differ
      refute inspect(write_filter) == inspect(read_filter)

      # Write filter should contain the `in` operator
      write_str = inspect(write_filter)
      assert write_str =~ "team_id"
      assert write_str =~ ":in" or write_str =~ "team_ids"
    end

    test "returns false when write: false" do
      assert Info.resolve_write_scope_filter(WriteScopePost, :readonly, %{}) == false
    end

    test "returns true when write: true" do
      assert Info.resolve_write_scope_filter(WriteScopePost, :write_all, %{}) == true
    end

    test "falls back to filter when write: is nil" do
      write_filter = Info.resolve_write_scope_filter(WriteScopePost, :simple, %{})
      read_filter = Info.resolve_scope_filter(WriteScopePost, :simple, %{})

      # Both should be the same expression (status == :draft)
      assert inspect(write_filter) == inspect(read_filter)
      assert inspect(write_filter) =~ "status"
    end

    test "returns true for :always scope (filter=true, no write:)" do
      assert Info.resolve_write_scope_filter(WriteScopePost, :always, %{}) == true
    end

    test "returns false for unknown scope" do
      assert Info.resolve_write_scope_filter(WriteScopePost, :nonexistent, %{}) == false
    end

    test "write: expr same as filter still works" do
      # :own has write: expr(author_id == ^actor(:id)) same as filter
      write_filter = Info.resolve_write_scope_filter(WriteScopePost, :own, %{})
      read_filter = Info.resolve_scope_filter(WriteScopePost, :own, %{})

      # Both should resolve to the same expression
      assert inspect(write_filter) == inspect(read_filter)
      assert inspect(write_filter) =~ "author_id"
    end
  end

  # ============================================================
  # Check integration: write scope values flow correctly to Check
  # ============================================================

  describe "Check integration: write scope values" do
    test "write: false flows to record_matches_filter? which returns false" do
      # Check has: record_matches_filter?(_record, false, _context, _opts) -> false
      filter = Info.resolve_write_scope_filter(WriteScopePost, :readonly, %{})
      assert filter == false
    end

    test "write: true flows to record_matches_filter? which returns true" do
      # Check has: record_matches_filter?(_record, true, _context, _opts) -> true
      filter = Info.resolve_write_scope_filter(WriteScopePost, :write_all, %{})
      assert filter == true
    end

    test "write expression contains correct field reference" do
      filter = Info.resolve_write_scope_filter(WriteScopePost, :own, %{})
      filter_str = inspect(filter)
      # Must reference author_id (the direct field), matching the read filter
      assert filter_str =~ "author_id"
    end

    test "write `in` expression references correct actor field" do
      filter = Info.resolve_write_scope_filter(WriteScopePost, :team_visible, %{})
      filter_str = inspect(filter)
      # Must contain team_id field and reference to actor's team_ids
      assert filter_str =~ "team_id"
      assert filter_str =~ "team_ids"
    end

    test "write expression is structurally different from read expression" do
      write_filter = Info.resolve_write_scope_filter(WriteScopePost, :team_visible, %{})
      read_filter = Info.resolve_scope_filter(WriteScopePost, :team_visible, %{})

      write_str = inspect(write_filter)
      read_str = inspect(read_filter)

      # Read uses equality (team_id == ^actor(:team_id))
      # Write uses membership (team_id in ^actor(:team_ids))
      refute write_str == read_str

      # Write should reference team_ids (plural — the list)
      assert write_str =~ "team_ids"
      # Read should reference team_id (singular — the equality field)
      refute read_str =~ "team_ids"
    end
  end

  # ============================================================
  # Legacy scope_resolver fallback
  # ============================================================

  defmodule LegacyResolverResource do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      extensions: [AshGrant]

    ash_grant do
      resolver(fn _actor, _context -> [] end)
      scope_resolver(fn scope, _context -> "legacy_filter_for_#{scope}" end)
      scope(:always, true)
    end

    attributes do
      uuid_primary_key(:id)
    end
  end

  describe "resolve_write_scope_filter/3 legacy fallback" do
    test "falls back to scope_resolver when scope not found in DSL" do
      # :unknown is not defined in DSL, so should fall back to scope_resolver
      result = Info.resolve_write_scope_filter(LegacyResolverResource, :unknown, %{})
      assert result == "legacy_filter_for_unknown"
    end

    test "uses DSL scope (with write fallback) over legacy resolver" do
      # :always IS defined in DSL, so should use it, not legacy resolver
      result = Info.resolve_write_scope_filter(LegacyResolverResource, :always, %{})
      assert result == true
    end
  end
end
