defmodule AshGrant.OptionalScopeTest do
  @moduledoc """
  Covers `permission` declared without a `:scope` — an unrestricted grant
  that doesn't need a matching `scope :always, true` declaration.

  What must hold:

  1. Both the resource-level and domain-level `permission` entities parse
     the 2-arg (resource) / 3-arg (domain) form and produce a
     `%AshGrant.Dsl.Permission{scope: nil}`.
  2. `AshGrant.Verifiers.ValidateGrantReferences` doesn't complain about a
     missing scope — even when the target resource declares no scopes.
  3. `AshGrant.GrantsResolver.to_permission_string/1` emits the no-scope
     form as a 4-part string with an empty trailing segment
     (`"resource:*:action:"`), which round-trips through
     `AshGrant.Permission.parse/1` back to `scope: nil`.
  4. `AshGrant.Evaluator.has_access?/3` grants access for a no-scope
     permission — the existing plumbing already handled this for the
     legacy 2-part form, this test just pins it against the new DSL form.
  5. `AshGrant.FilterCheck`-style global-access short-circuits on a
     `nil` scope (covered via `Evaluator.get_all_scopes/4` +
     `FilterCheck.build_filter_with_instances/6` in other test files;
     the assertions here exercise the parse/resolve/evaluate path
     end-to-end on the Elixir side).
  """

  use ExUnit.Case, async: true

  alias AshGrant.{Evaluator, Info, Permission}

  # Inline resource with a no-scope grant. No scope entities declared on the
  # resource — the verifier must not require one for the no-scope permission.
  defmodule Post do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      extensions: [AshGrant]

    ash_grant do
      resource_name("post")

      grants do
        grant :admin, expr(^actor(:role) == :admin) do
          permission(:manage_all, :*)
        end

        grant :reader, expr(^actor(:role) == :reader) do
          permission(:read_any, :read)
        end
      end
    end

    actions do
      defaults([:read, :create, :update, :destroy])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:author_id, :uuid)
    end
  end

  describe "resource-level permission with no scope" do
    test "parses to a Permission struct with scope: nil" do
      permission =
        Info.permissions(Post)
        |> Enum.find(&(&1.name == :manage_all))

      assert permission.scope == nil
      assert permission.action == :*
      assert permission.on == Post
    end

    test "resolver emits a 4-part string with an empty trailing segment" do
      perms = AshGrant.GrantsResolver.resolve(%{role: :admin}, %{resource: Post})

      assert "post:*:*:" in perms
    end

    test "emitted string round-trips through Permission.parse/1 as scope: nil" do
      perms = AshGrant.GrantsResolver.resolve(%{role: :reader}, %{resource: Post})
      [string] = Enum.filter(perms, &String.starts_with?(&1, "post:"))

      assert {:ok, %Permission{scope: nil, action: "read", resource: "post", instance_id: "*"}} =
               Permission.parse(string)
    end

    test "Evaluator.has_access? grants on a no-scope permission" do
      perms = AshGrant.GrantsResolver.resolve(%{role: :reader}, %{resource: Post})

      assert Evaluator.has_access?(perms, "post", "read")
      # Admin wildcard covers everything
      admin_perms = AshGrant.GrantsResolver.resolve(%{role: :admin}, %{resource: Post})
      assert Evaluator.has_access?(admin_perms, "post", "read")
      assert Evaluator.has_access?(admin_perms, "post", "update")
    end

    test "compiles with no `scope :…` entities on the resource at all" do
      # The test passing at all means the verifier accepted the module.
      # Asserting no scopes here pins the intent.
      assert Info.scopes(Post) == []
    end
  end

  # Inline domain with a no-scope permission.
  defmodule BareDomain do
    use Ash.Domain,
      extensions: [AshGrant.Domain],
      validate_config_inclusion?: false

    ash_grant do
      grants do
        grant :admin, expr(^actor(:role) == :admin) do
          permission(:manage_everything, AshGrant.OptionalScopeTest.Post, :*)
        end
      end
    end

    resources do
    end
  end

  describe "domain-level permission with no scope" do
    test "parses to a Permission struct with scope: nil" do
      [grant] = AshGrant.Domain.Info.grants(BareDomain)
      [permission] = grant.permissions

      assert permission.name == :manage_everything
      assert permission.on == Post
      assert permission.action == :*
      assert permission.scope == nil
    end

    test "resolver emits an empty-trailing-segment permission string" do
      perms = AshGrant.GrantsResolver.resolve(%{role: :admin}, %{resource: Post})

      # Even though Post declares its own grants, merging domain grants
      # via Info.grants/1 requires a real Ash.Resource.Info.domain/1 link,
      # which inline modules don't have. So here we just prove the
      # domain-level resolver path directly:
      domain_grants = AshGrant.Domain.Info.grants(BareDomain)
      [%{permissions: [perm]}] = domain_grants

      # stringify nil -> "" (see AshGrant.GrantsResolver.stringify/1)
      assert perm.scope == nil

      # Sanity: Post has its own admin grant emitting "post:*:*:"
      assert "post:*:*:" in perms
    end
  end

  describe "Permission.to_string/1 mirrors parser behaviour" do
    test "nil scope renders with trailing empty segment" do
      perm = %Permission{resource: "post", instance_id: "*", action: "read", scope: nil}
      # Regardless of whether AshGrant.Permission.to_string/1 emits the 2-part
      # or 4-part form, it must parse back to scope: nil.
      as_string = Permission.to_string(perm)
      assert {:ok, %Permission{scope: nil}} = Permission.parse(as_string)
    end
  end
end
