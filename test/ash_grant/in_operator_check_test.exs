defmodule AshGrant.InOperatorCheckTest do
  @moduledoc """
  Tests for the `in` operator handling in AshGrant.Check fallback evaluation.

  When `Ash.Expr.eval` returns `:unknown` for filter expressions containing
  the `in` operator, the Check module uses fallback evaluation to parse
  and evaluate these expressions.

  This tests two patterns:
  1. `field in [list]` - from scope_resolver returning pre-computed lists
  2. `field in ^actor(:list_field)` - from inline scope DSL with actor-derived lists
  """
  use AshGrant.DataCase, async: true

  alias AshGrant.Test.Employee

  # === Test Actors ===

  defp custom_actor(opts) do
    id = Keyword.get(opts, :id, Ash.UUID.generate())
    permissions = Keyword.get(opts, :permissions, [])
    org_unit_id = Keyword.get(opts, :org_unit_id)
    subtree_org_ids = Keyword.get(opts, :subtree_org_ids, [])

    %{
      id: id,
      permissions: permissions,
      org_unit_id: org_unit_id,
      subtree_org_ids: subtree_org_ids
    }
  end

  # === Helper Functions ===

  defp create_employee!(attrs) do
    Employee
    |> Ash.Changeset.for_create(:create, attrs, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  # ============================================
  # Tests for `field in ^actor(:list_field)` pattern
  # (inline scope DSL with actor-derived lists)
  # ============================================

  describe "inline scope with `in ^actor(:list_field)` pattern - create action" do
    test "actor with org_subtree create permission can create in their subtree" do
      parent_org = Ash.UUID.generate()
      child_org = Ash.UUID.generate()

      # Use custom actor with explicit create permission using org_subtree scope
      actor =
        custom_actor(
          permissions: ["employee:*:create:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org, child_org]
        )

      # Create in parent org (in subtree)
      result =
        Employee
        |> Ash.Changeset.for_create(:create, %{
          name: "New Employee",
          organization_unit_id: parent_org
        })
        |> Ash.create(actor: actor)

      assert {:ok, employee} = result
      assert employee.name == "New Employee"
      assert employee.organization_unit_id == parent_org
    end

    test "actor with org_subtree create permission can create in child org" do
      parent_org = Ash.UUID.generate()
      child_org = Ash.UUID.generate()

      actor =
        custom_actor(
          permissions: ["employee:*:create:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org, child_org]
        )

      # Create in child org (in subtree)
      result =
        Employee
        |> Ash.Changeset.for_create(:create, %{
          name: "Child Org Employee",
          organization_unit_id: child_org
        })
        |> Ash.create(actor: actor)

      assert {:ok, employee} = result
      assert employee.organization_unit_id == child_org
    end

    test "actor with org_subtree create permission cannot create outside subtree" do
      parent_org = Ash.UUID.generate()
      other_org = Ash.UUID.generate()

      actor =
        custom_actor(
          permissions: ["employee:*:create:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org]
        )

      # Try to create in another org (not in subtree)
      result =
        Employee
        |> Ash.Changeset.for_create(:create, %{
          name: "Forbidden Employee",
          organization_unit_id: other_org
        })
        |> Ash.create(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end

  describe "inline scope with `in ^actor(:list_field)` pattern - update action" do
    test "actor with org_subtree update permission can update in subtree" do
      parent_org = Ash.UUID.generate()
      child_org = Ash.UUID.generate()

      # Create employee in child org
      employee = create_employee!(%{name: "Original", organization_unit_id: child_org})

      actor =
        custom_actor(
          permissions: ["employee:*:update:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org, child_org]
        )

      # Update should succeed (child_org is in subtree)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:ok, updated} = result
      assert updated.name == "Updated"
    end

    test "actor with org_subtree update permission cannot update outside subtree" do
      parent_org = Ash.UUID.generate()
      other_org = Ash.UUID.generate()

      # Create employee in another org
      employee = create_employee!(%{name: "Other Org Employee", organization_unit_id: other_org})

      actor =
        custom_actor(
          permissions: ["employee:*:update:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org]
        )

      # Update should fail (other_org is not in subtree)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Hacked"})
        |> Ash.update(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end

  describe "inline scope with `in ^actor(:list_field)` pattern - destroy action" do
    test "actor with org_subtree destroy permission can destroy in subtree" do
      parent_org = Ash.UUID.generate()
      child_org = Ash.UUID.generate()

      # Create employee in child org
      employee = create_employee!(%{name: "To Delete", organization_unit_id: child_org})

      actor =
        custom_actor(
          permissions: ["employee:*:destroy:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org, child_org]
        )

      # Destroy should succeed
      result =
        employee
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(actor: actor)

      assert :ok = result
    end

    test "actor with org_subtree destroy permission cannot destroy outside subtree" do
      parent_org = Ash.UUID.generate()
      other_org = Ash.UUID.generate()

      # Create employee in another org
      employee = create_employee!(%{name: "Other Employee", organization_unit_id: other_org})

      actor =
        custom_actor(
          permissions: ["employee:*:destroy:org_subtree"],
          org_unit_id: parent_org,
          subtree_org_ids: [parent_org]
        )

      # Destroy should fail
      result =
        employee
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end

  # ============================================
  # Tests for org_self scope (equality check)
  # vs org_subtree scope (in operator)
  # ============================================

  describe "org_self scope (equality) vs org_subtree scope (in operator)" do
    test "actor with org_self cannot update employee in child org" do
      parent_org = Ash.UUID.generate()
      child_org = Ash.UUID.generate()

      # Create employee in child org
      employee = create_employee!(%{name: "Child Employee", organization_unit_id: child_org})

      # Actor only has org_self scope (equality check)
      actor =
        custom_actor(
          permissions: ["employee:*:update:org_self"],
          org_unit_id: parent_org
        )

      # Update should fail (org_self only matches same org, not children)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "actor with org_self can update employee in same org" do
      org_unit_id = Ash.UUID.generate()

      # Create employee in same org
      employee = create_employee!(%{name: "Same Org", organization_unit_id: org_unit_id})

      actor =
        custom_actor(
          permissions: ["employee:*:update:org_self"],
          org_unit_id: org_unit_id
        )

      # Update should succeed (same org)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:ok, updated} = result
      assert updated.name == "Updated"
    end
  end

  # ============================================
  # Edge cases
  # ============================================

  describe "edge cases for in operator evaluation" do
    test "empty subtree_org_ids list denies access" do
      some_org = Ash.UUID.generate()

      # Create employee
      employee = create_employee!(%{name: "Test", organization_unit_id: some_org})

      # Actor with empty subtree list
      actor =
        custom_actor(
          permissions: ["employee:*:update:org_subtree"],
          subtree_org_ids: []
        )

      # Should fail (empty list means nothing matches)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "nil subtree_org_ids denies access" do
      some_org = Ash.UUID.generate()

      # Create employee
      employee = create_employee!(%{name: "Test", organization_unit_id: some_org})

      # Actor with nil subtree list
      actor = %{
        id: Ash.UUID.generate(),
        permissions: ["employee:*:update:org_subtree"],
        subtree_org_ids: nil
      }

      # Should fail (nil list means nothing matches)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end

    test "large subtree list works correctly" do
      # Generate many org IDs
      target_org = Ash.UUID.generate()
      other_orgs = for _ <- 1..100, do: Ash.UUID.generate()
      all_orgs = [target_org | other_orgs]

      # Create employee in target org
      employee = create_employee!(%{name: "Test", organization_unit_id: target_org})

      actor =
        custom_actor(
          permissions: ["employee:*:update:org_subtree"],
          org_unit_id: target_org,
          subtree_org_ids: all_orgs
        )

      # Should succeed (target_org is in the large list)
      result =
        employee
        |> Ash.Changeset.for_update(:update, %{name: "Updated"})
        |> Ash.update(actor: actor)

      assert {:ok, updated} = result
      assert updated.name == "Updated"
    end
  end
end
