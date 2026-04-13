defmodule AshGrant.JasonEncoderTest do
  @moduledoc """
  Tests for JSON encoding of AshGrant public structs.

  JSON-safe output is a hard requirement for the planned `ash_grant_ai`
  package (LLM tool responses) and `ash_grant_phoenix` dashboard (JSON
  export, API endpoints). Core contract: every public struct must encode
  to valid JSON without raising, and must not leak module atoms or raw
  Ash.Expr terms in the output.
  """
  use ExUnit.Case, async: true

  alias AshGrant.{Permission, PermissionInput}

  describe "Jason.encode!/1 — Permission" do
    test "encodes a basic RBAC permission" do
      perm = Permission.parse!("post:*:read:own")
      json = Jason.encode!(perm)
      decoded = Jason.decode!(json)

      assert decoded["resource"] == "post"
      assert decoded["instance_id"] == "*"
      assert decoded["action"] == "read"
      assert decoded["scope"] == "own"
      assert decoded["deny"] == false
    end

    test "encodes a deny permission" do
      perm = Permission.parse!("!post:*:delete:always")
      decoded = perm |> Jason.encode!() |> Jason.decode!()

      assert decoded["deny"] == true
      assert decoded["action"] == "delete"
    end

    test "encodes a 5-part permission with field_group" do
      perm = Permission.parse!("employee:*:read:always:sensitive")
      decoded = perm |> Jason.encode!() |> Jason.decode!()

      assert decoded["field_group"] == "sensitive"
    end

    test "encodes an instance permission" do
      perm = Permission.parse!("doc:doc_123:update:")
      decoded = perm |> Jason.encode!() |> Jason.decode!()

      assert decoded["instance_id"] == "doc_123"
      assert decoded["action"] == "update"
    end
  end

  describe "Jason.encode!/1 — PermissionInput" do
    test "encodes with all metadata fields" do
      input = %PermissionInput{
        string: "post:*:update:own",
        description: "Edit own posts",
        source: "editor_role",
        metadata: %{granted_at: "2024-01-15"}
      }

      decoded = input |> Jason.encode!() |> Jason.decode!()

      assert decoded["string"] == "post:*:update:own"
      assert decoded["description"] == "Edit own posts"
      assert decoded["source"] == "editor_role"
      assert decoded["metadata"] == %{"granted_at" => "2024-01-15"}
    end

    test "encodes with nil metadata fields" do
      input = %PermissionInput{string: "post:*:read:always"}
      decoded = input |> Jason.encode!() |> Jason.decode!()

      assert decoded["string"] == "post:*:read:always"
      assert decoded["description"] == nil
      assert decoded["source"] == nil
      assert decoded["metadata"] == nil
    end
  end

  describe "Jason.encode!/1 — Explanation" do
    setup do
      # A minimal actor + resource combination that produces a non-trivial
      # Explanation with a scope_filter we can assert on.
      actor = %{id: 42, role: :editor}
      explanation = AshGrant.explain(AshGrant.Test.Post, :update, actor)
      {:ok, explanation: explanation}
    end

    test "encodes without raising", %{explanation: explanation} do
      assert is_binary(Jason.encode!(explanation))
    end

    test "renders resource as a readable module name", %{explanation: explanation} do
      decoded = explanation |> Jason.encode!() |> Jason.decode!()

      assert is_binary(decoded["resource"])
      assert decoded["resource"] =~ "Post"
      refute decoded["resource"] == "Elixir.AshGrant.Test.Post"
    end

    test "renders decision and action as strings", %{explanation: explanation} do
      decoded = explanation |> Jason.encode!() |> Jason.decode!()

      assert decoded["decision"] in ["allow", "deny"]
      assert decoded["action"] == "update"
    end

    test "stringifies scope_filter into scope_filter_string", %{explanation: explanation} do
      decoded = explanation |> Jason.encode!() |> Jason.decode!()

      # When the action is allowed by scope `:own`, filter should mention actor
      if decoded["decision"] == "allow" do
        assert is_binary(decoded["scope_filter_string"])
        assert decoded["scope_filter_string"] =~ "^actor(:id)"
      end
    end

    test "does not leak raw Ash.Expr structs into JSON", %{explanation: explanation} do
      json = Jason.encode!(explanation)

      # Raw Ash.Expr internals like :_actor / :_tenant / Ash.Query.* should
      # never appear in the JSON surface — they're the signal of a leak.
      refute json =~ ":_actor"
      refute json =~ ":_tenant"
      refute json =~ "Ash.Query.Call"
      refute json =~ "Ash.Query.Ref"
    end

    test "renders actor as a readable string", %{explanation: explanation} do
      decoded = explanation |> Jason.encode!() |> Jason.decode!()

      # Actor is user-supplied and may contain arbitrary terms; we render it
      # as an inspect-style string for debug traceability, not the raw map.
      assert is_binary(decoded["actor"])
    end

    test "preserves matching_permissions as list of maps", %{explanation: explanation} do
      decoded = explanation |> Jason.encode!() |> Jason.decode!()

      assert is_list(decoded["matching_permissions"])
    end
  end
end
