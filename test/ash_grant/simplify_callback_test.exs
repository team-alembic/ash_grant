defmodule AshGrant.SimplifyCallbackTest do
  @moduledoc """
  Tests for Ash.Policy.Check.simplify/2 and related callbacks.

  These callbacks help Ash's SAT solver make smarter authorization decisions
  by understanding relationships between checks.
  """

  use ExUnit.Case, async: true

  alias AshGrant.Check
  alias AshGrant.FilterCheck

  # Test resource for context
  defmodule TestResource do
    use Ash.Resource, domain: nil, data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:author_id, :uuid, public?: true)
    end

    actions do
      defaults([:read, :create, :update, :destroy])
    end
  end

  describe "AshGrant.Check.simplify/2" do
    test "returns a valid expression" do
      ref = {Check, []}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      # Should return a Crux expression (at minimum, the ref itself)
      assert result != nil
    end

    test "returns ref unchanged for basic check" do
      ref = {Check, []}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      # Default behavior: return ref unchanged
      assert result == ref
    end

    test "returns ref unchanged with action option" do
      ref = {Check, [action: "update"]}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      assert result == ref
    end

    test "returns ref unchanged with resource option" do
      ref = {Check, [resource: "post"]}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      assert result == ref
    end

    test "returns ref unchanged with multiple options" do
      ref = {Check, [action: "publish", resource: "article"]}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      assert result == ref
    end
  end

  describe "AshGrant.FilterCheck.simplify/2" do
    test "returns a valid expression" do
      ref = {FilterCheck, []}
      context = %{resource: TestResource}

      result = FilterCheck.simplify(ref, context)

      assert result != nil
    end

    test "returns ref unchanged for basic check" do
      ref = {FilterCheck, []}
      context = %{resource: TestResource}

      result = FilterCheck.simplify(ref, context)

      assert result == ref
    end

    test "returns ref unchanged with action option" do
      ref = {FilterCheck, [action: "read"]}
      context = %{resource: TestResource}

      result = FilterCheck.simplify(ref, context)

      assert result == ref
    end
  end

  describe "AshGrant.Check.implies?/3" do
    test "same check implies itself" do
      ref1 = {Check, []}
      ref2 = {Check, []}
      context = %{resource: TestResource}

      # Same check with same options implies itself
      assert Check.implies?(ref1, ref2, context) == true
    end

    test "same check with same options implies itself" do
      ref1 = {Check, [action: "update"]}
      ref2 = {Check, [action: "update"]}
      context = %{resource: TestResource}

      assert Check.implies?(ref1, ref2, context) == true
    end

    test "check with different action does not imply" do
      ref1 = {Check, [action: "update"]}
      ref2 = {Check, [action: "destroy"]}
      context = %{resource: TestResource}

      # Different actions don't imply each other
      assert Check.implies?(ref1, ref2, context) == false
    end

    test "check with different resource does not imply" do
      ref1 = {Check, [resource: "post"]}
      ref2 = {Check, [resource: "comment"]}
      context = %{resource: TestResource}

      assert Check.implies?(ref1, ref2, context) == false
    end

    test "check without options does not imply check with options" do
      ref1 = {Check, []}
      ref2 = {Check, [action: "update"]}
      context = %{resource: TestResource}

      # Generic check doesn't imply specific check
      assert Check.implies?(ref1, ref2, context) == false
    end

    test "check with options does not imply check without options" do
      ref1 = {Check, [action: "update"]}
      ref2 = {Check, []}
      context = %{resource: TestResource}

      # Specific check doesn't imply generic check
      assert Check.implies?(ref1, ref2, context) == false
    end

    test "different check modules don't imply each other" do
      ref1 = {Check, []}
      ref2 = {FilterCheck, []}
      context = %{resource: TestResource}

      assert Check.implies?(ref1, ref2, context) == false
    end
  end

  describe "AshGrant.FilterCheck.implies?/3" do
    test "same filter check implies itself" do
      ref1 = {FilterCheck, []}
      ref2 = {FilterCheck, []}
      context = %{resource: TestResource}

      assert FilterCheck.implies?(ref1, ref2, context) == true
    end

    test "same filter check with same options implies itself" do
      ref1 = {FilterCheck, [action: "read"]}
      ref2 = {FilterCheck, [action: "read"]}
      context = %{resource: TestResource}

      assert FilterCheck.implies?(ref1, ref2, context) == true
    end

    test "filter check with different action does not imply" do
      ref1 = {FilterCheck, [action: "read"]}
      ref2 = {FilterCheck, [action: "list"]}
      context = %{resource: TestResource}

      assert FilterCheck.implies?(ref1, ref2, context) == false
    end
  end

  describe "AshGrant.Check.conflicts?/3" do
    test "same check does not conflict with itself" do
      ref1 = {Check, []}
      ref2 = {Check, []}
      context = %{resource: TestResource}

      # Same check can't conflict with itself
      assert Check.conflicts?(ref1, ref2, context) == false
    end

    test "checks with different actions don't conflict" do
      ref1 = {Check, [action: "update"]}
      ref2 = {Check, [action: "destroy"]}
      context = %{resource: TestResource}

      # Different actions don't inherently conflict
      assert Check.conflicts?(ref1, ref2, context) == false
    end

    test "checks with different resources don't conflict" do
      ref1 = {Check, [resource: "post"]}
      ref2 = {Check, [resource: "comment"]}
      context = %{resource: TestResource}

      assert Check.conflicts?(ref1, ref2, context) == false
    end

    test "check and filter_check don't conflict" do
      ref1 = {Check, []}
      ref2 = {FilterCheck, []}
      context = %{resource: TestResource}

      # Different check types don't conflict
      assert Check.conflicts?(ref1, ref2, context) == false
    end
  end

  describe "AshGrant.FilterCheck.conflicts?/3" do
    test "same filter check does not conflict with itself" do
      ref1 = {FilterCheck, []}
      ref2 = {FilterCheck, []}
      context = %{resource: TestResource}

      assert FilterCheck.conflicts?(ref1, ref2, context) == false
    end

    test "filter checks with different actions don't conflict" do
      ref1 = {FilterCheck, [action: "read"]}
      ref2 = {FilterCheck, [action: "list"]}
      context = %{resource: TestResource}

      assert FilterCheck.conflicts?(ref1, ref2, context) == false
    end
  end

  describe "callback behavior contract" do
    test "simplify returns something the SAT solver can use" do
      ref = {Check, [action: "update"]}
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)

      # The result should be usable as a SAT expression
      # At minimum it should be the ref itself or a Crux expression
      assert is_tuple(result) or is_atom(result) or is_struct(result)
    end

    test "implies? is reflexive for identical refs" do
      ref = {Check, [action: "update", resource: "post"]}
      context = %{resource: TestResource}

      # Reflexivity: a check always implies itself
      assert Check.implies?(ref, ref, context) == true
    end

    test "conflicts? is symmetric" do
      ref1 = {Check, [action: "update"]}
      ref2 = {Check, [action: "destroy"]}
      context = %{resource: TestResource}

      # Symmetry: if A conflicts with B, then B conflicts with A
      result1 = Check.conflicts?(ref1, ref2, context)
      result2 = Check.conflicts?(ref2, ref1, context)

      assert result1 == result2
    end

    test "implies? handles module-only refs" do
      # Sometimes refs can be just the module without options
      ref1 = Check
      ref2 = Check
      context = %{resource: TestResource}

      # Should handle gracefully
      result = Check.implies?(ref1, ref2, context)
      assert is_boolean(result)
    end

    test "conflicts? handles module-only refs" do
      ref1 = Check
      ref2 = FilterCheck
      context = %{resource: TestResource}

      result = Check.conflicts?(ref1, ref2, context)
      assert is_boolean(result)
    end

    test "simplify handles module-only ref" do
      ref = Check
      context = %{resource: TestResource}

      result = Check.simplify(ref, context)
      assert result != nil
    end
  end
end
