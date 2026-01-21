defmodule AshGrant.SimplifyPropertyTest do
  @moduledoc """
  Property-based tests for simplify/2, implies?/3, and conflicts?/3 callbacks.

  These tests verify that the callbacks behave correctly across a wide range
  of random inputs, catching edge cases that unit tests might miss.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshGrant.Check
  alias AshGrant.FilterCheck

  # Generators

  defp action_gen do
    one_of([
      constant("read"),
      constant("create"),
      constant("update"),
      constant("destroy"),
      string(:alphanumeric, min_length: 1, max_length: 10) |> map(&String.downcase/1)
    ])
  end

  defp resource_gen do
    one_of([
      constant("post"),
      constant("comment"),
      constant("user"),
      string(:alphanumeric, min_length: 1, max_length: 10) |> map(&String.downcase/1)
    ])
  end

  defp opts_gen do
    one_of([
      constant([]),
      map(action_gen(), fn action -> [action: action] end),
      map(resource_gen(), fn resource -> [resource: resource] end),
      map({action_gen(), resource_gen()}, fn {action, resource} ->
        [action: action, resource: resource]
      end)
    ])
  end

  defp check_ref_gen do
    one_of([
      constant(Check),
      map(opts_gen(), fn opts -> {Check, opts} end)
    ])
  end

  defp filter_check_ref_gen do
    one_of([
      constant(FilterCheck),
      map(opts_gen(), fn opts -> {FilterCheck, opts} end)
    ])
  end

  defp context_gen do
    one_of([
      constant(%{}),
      constant(%{resource: SomeResource}),
      map(string(:alphanumeric, min_length: 1, max_length: 5), fn extra ->
        %{resource: SomeResource, extra: extra}
      end)
    ])
  end

  # Property Tests for simplify/2

  describe "simplify/2 properties" do
    property "simplify always returns the same ref unchanged" do
      check all(
              ref <- check_ref_gen(),
              context <- context_gen()
            ) do
        assert Check.simplify(ref, context) == ref
      end
    end

    property "FilterCheck simplify always returns the same ref unchanged" do
      check all(
              ref <- filter_check_ref_gen(),
              context <- context_gen()
            ) do
        assert FilterCheck.simplify(ref, context) == ref
      end
    end

    property "simplify is idempotent" do
      check all(
              ref <- check_ref_gen(),
              context <- context_gen()
            ) do
        result1 = Check.simplify(ref, context)
        result2 = Check.simplify(result1, context)
        assert result1 == result2
      end
    end
  end

  # Property Tests for implies?/3

  describe "implies?/3 properties" do
    property "implies? is reflexive (a ref implies itself)" do
      check all(
              ref <- check_ref_gen(),
              context <- context_gen()
            ) do
        assert Check.implies?(ref, ref, context) == true
      end
    end

    property "FilterCheck implies? is reflexive" do
      check all(
              ref <- filter_check_ref_gen(),
              context <- context_gen()
            ) do
        assert FilterCheck.implies?(ref, ref, context) == true
      end
    end

    property "identical refs always imply each other" do
      check all(
              opts <- opts_gen(),
              context <- context_gen()
            ) do
        ref1 = {Check, opts}
        ref2 = {Check, opts}
        assert Check.implies?(ref1, ref2, context) == true
      end
    end

    property "refs with different modules never imply each other" do
      check all(
              opts <- opts_gen(),
              context <- context_gen()
            ) do
        ref1 = {Check, opts}
        ref2 = {FilterCheck, opts}
        assert Check.implies?(ref1, ref2, context) == false
      end
    end

    property "option order does not affect implies?" do
      check all(
              action <- action_gen(),
              resource <- resource_gen(),
              context <- context_gen()
            ) do
        ref1 = {Check, [action: action, resource: resource]}
        ref2 = {Check, [resource: resource, action: action]}
        assert Check.implies?(ref1, ref2, context) == true
      end
    end

    property "different options never imply each other" do
      check all(
              action1 <- action_gen(),
              action2 <- action_gen(),
              context <- context_gen()
            ) do
        if action1 != action2 do
          ref1 = {Check, [action: action1]}
          ref2 = {Check, [action: action2]}
          assert Check.implies?(ref1, ref2, context) == false
        end
      end
    end
  end

  # Property Tests for conflicts?/3

  describe "conflicts?/3 properties" do
    property "conflicts? always returns false for AshGrant checks" do
      check all(
              ref1 <- check_ref_gen(),
              ref2 <- check_ref_gen(),
              context <- context_gen()
            ) do
        assert Check.conflicts?(ref1, ref2, context) == false
      end
    end

    property "FilterCheck conflicts? always returns false" do
      check all(
              ref1 <- filter_check_ref_gen(),
              ref2 <- filter_check_ref_gen(),
              context <- context_gen()
            ) do
        assert FilterCheck.conflicts?(ref1, ref2, context) == false
      end
    end

    property "conflicts? is symmetric" do
      check all(
              ref1 <- check_ref_gen(),
              ref2 <- check_ref_gen(),
              context <- context_gen()
            ) do
        assert Check.conflicts?(ref1, ref2, context) == Check.conflicts?(ref2, ref1, context)
      end
    end

    property "cross-module conflicts? is symmetric" do
      check all(
              check_ref <- check_ref_gen(),
              filter_ref <- filter_check_ref_gen(),
              context <- context_gen()
            ) do
        assert Check.conflicts?(check_ref, filter_ref, context) ==
                 Check.conflicts?(filter_ref, check_ref, context)
      end
    end
  end

  # Property Tests for callback consistency

  describe "callback consistency properties" do
    property "implies? returns boolean for any valid input" do
      check all(
              ref1 <- check_ref_gen(),
              ref2 <- check_ref_gen(),
              context <- context_gen()
            ) do
        result = Check.implies?(ref1, ref2, context)
        assert is_boolean(result)
      end
    end

    property "conflicts? returns boolean for any valid input" do
      check all(
              ref1 <- check_ref_gen(),
              ref2 <- check_ref_gen(),
              context <- context_gen()
            ) do
        result = Check.conflicts?(ref1, ref2, context)
        assert is_boolean(result)
      end
    end

    property "simplify never crashes for valid refs" do
      check all(
              ref <- check_ref_gen(),
              context <- context_gen()
            ) do
        # Should not raise
        _result = Check.simplify(ref, context)
        assert true
      end
    end

    property "a ref that implies another with context A also implies with context B" do
      check all(
              opts <- opts_gen(),
              context1 <- context_gen(),
              context2 <- context_gen()
            ) do
        ref = {Check, opts}
        # Since we don't use context, this should always be consistent
        assert Check.implies?(ref, ref, context1) == Check.implies?(ref, ref, context2)
      end
    end
  end

  # Property Tests for robustness

  describe "robustness properties" do
    property "empty opts are handled consistently" do
      check all(context <- context_gen()) do
        ref1 = {Check, []}
        ref2 = Check
        # Module-only should be equivalent to tuple with empty opts
        assert Check.implies?(ref1, ref2, context) == true
        assert Check.implies?(ref2, ref1, context) == true
      end
    end

    property "FilterCheck empty opts are handled consistently" do
      check all(context <- context_gen()) do
        ref1 = {FilterCheck, []}
        ref2 = FilterCheck
        assert FilterCheck.implies?(ref1, ref2, context) == true
        assert FilterCheck.implies?(ref2, ref1, context) == true
      end
    end
  end
end
