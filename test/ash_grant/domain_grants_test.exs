defmodule AshGrant.DomainGrantsTest do
  @moduledoc """
  Covers the declarative `grants` DSL when declared on an `Ash.Domain`
  instead of (or in addition to) a resource.

  Domain-level grants apply to **every** resource in the domain by
  default — `permission :name, :action, :scope` is a *broadcast*. The
  resolver substitutes `context.resource` at runtime so the same
  permission lights up every resource in the domain. Use the `on:`
  keyword to scope a single permission to one resource (Ash's
  `policy resource_is/1` analog).
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias AshGrant.Info

  alias AshGrant.Test.{
    GrantsDomainMixedPost,
    GrantsDomainOther,
    GrantsDomainOverridePost,
    GrantsDomainPost,
    GrantsDomainResolverPost,
    GrantsOnlyDomain
  }

  defp admin, do: %{id: Ash.UUID.generate(), role: :admin}
  defp super_admin, do: %{id: Ash.UUID.generate(), role: :super_admin}
  defp editor, do: %{id: Ash.UUID.generate(), role: :editor}
  defp viewer, do: %{id: Ash.UUID.generate(), role: :viewer}
  defp auditor, do: %{id: Ash.UUID.generate(), role: :auditor}

  defp clear_ets!(resource) do
    resource
    |> Ash.Query.for_read(:read, %{}, authorize?: false)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))
  end

  setup do
    clear_ets!(GrantsDomainPost)
    clear_ets!(GrantsDomainMixedPost)
    clear_ets!(GrantsDomainOverridePost)
    clear_ets!(GrantsDomainOther)
    :ok
  end

  describe "domain-level introspection" do
    test "AshGrant.Domain.Info.grants/1 returns the domain's grants" do
      grants = AshGrant.Domain.Info.grants(GrantsOnlyDomain)
      assert Enum.map(grants, & &1.name) |> Enum.sort() == [:admin, :auditor, :viewer]
    end

    test "AshGrant.Domain.Info.permissions/1 flattens permissions across grants" do
      perms = AshGrant.Domain.Info.permissions(GrantsOnlyDomain)
      names = Enum.map(perms, & &1.name) |> Enum.sort()
      assert names == [:audit_post, :manage_all, :read_published]
    end

    test "broadcast permissions parse with on: nil" do
      [%{permissions: [perm | _]}] =
        AshGrant.Domain.Info.grants(GrantsOnlyDomain)
        |> Enum.filter(&(&1.name == :admin))

      assert perm.on == nil
      assert perm.action == :*
      assert perm.scope == :always
    end

    test "scoped (`on:`) permissions parse with the target set" do
      [%{permissions: [perm]}] =
        AshGrant.Domain.Info.grants(GrantsOnlyDomain)
        |> Enum.filter(&(&1.name == :auditor))

      assert perm.on == GrantsDomainPost
    end

    test "resources in a grants-only domain route through GrantsResolver" do
      # `AshGrant.Domain.Info.resolver/1` returns the **user-declared**
      # resolver (nil here — the domain only declares grants). Synthesis
      # happens in `AshGrant.Info.resolver/1` at read time: any resource in
      # the domain returns `GrantsResolver` because the domain's grants
      # merge into the resource's grant list.
      assert AshGrant.Domain.Info.resolver(GrantsOnlyDomain) == nil
      assert Info.resolver(GrantsDomainPost) == AshGrant.GrantsResolver
    end
  end

  describe "broadcast permissions apply to every resource in the domain" do
    test "admin gets the broadcast permission on the main resource" do
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainPost})
      assert "grants_domain_post:*:*:always" in perms
    end

    test "the same broadcast permission lights up sibling resources" do
      # Same domain-level :admin grant — but checked from a different
      # resource. The resolver substitutes the resource being authorized.
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainOther})
      assert "grants_domain_other:*:*:always" in perms
    end

    test "viewer's broadcast :read :published applies to every resource" do
      post_perms = AshGrant.GrantsResolver.resolve(viewer(), %{resource: GrantsDomainPost})
      assert "grants_domain_post:*:read:published" in post_perms

      other_perms = AshGrant.GrantsResolver.resolve(viewer(), %{resource: GrantsDomainOther})
      assert "grants_domain_other:*:read:published" in other_perms
    end

    test "unknown actor role yields no permissions" do
      assert [] =
               AshGrant.GrantsResolver.resolve(%{role: :stranger}, %{resource: GrantsDomainPost})
    end
  end

  describe "scoped (`on:`) domain permissions apply only to their target" do
    test "auditor's :audit_post permission fires on GrantsDomainPost" do
      perms = AshGrant.GrantsResolver.resolve(auditor(), %{resource: GrantsDomainPost})
      assert "grants_domain_post:*:read:always" in perms
    end

    test "auditor gets nothing on a sibling resource (different `on:`)" do
      perms = AshGrant.GrantsResolver.resolve(auditor(), %{resource: GrantsDomainOther})
      # The :auditor grant has only one permission (`on: GrantsDomainPost`);
      # for any other resource the emitted string targets Post, not Other,
      # so nothing matches a check on Other.
      refute Enum.any?(perms, &String.starts_with?(&1, "grants_domain_other:"))
    end
  end

  describe "domain grants flow through the full Ash.Policy pipeline" do
    test "admin can read a resource that declares no grants of its own" do
      {:ok, _} =
        GrantsDomainPost
        |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()},
          authorize?: false
        )
        |> Ash.create(authorize?: false)

      assert [_] =
               GrantsDomainPost
               |> Ash.Query.for_read(:read)
               |> Ash.read!(actor: admin())
    end

    test "admin can read a sibling resource via the same broadcast" do
      {:ok, _} =
        GrantsDomainOther
        |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()},
          authorize?: false
        )
        |> Ash.create(authorize?: false)

      assert [_] =
               GrantsDomainOther
               |> Ash.Query.for_read(:read)
               |> Ash.read!(actor: admin())
    end

    test "stranger is denied by the policy (default-deny)" do
      {:ok, _} =
        GrantsDomainPost
        |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()},
          authorize?: false
        )
        |> Ash.create(authorize?: false)

      assert_raise Ash.Error.Forbidden, fn ->
        GrantsDomainPost
        |> Ash.Query.for_read(:read)
        |> Ash.read!(actor: %{id: Ash.UUID.generate(), role: :stranger})
      end
    end
  end

  describe "resource grants merge with the domain's broadcast grants" do
    test "Info.grants/1 returns both resource and domain grants" do
      names = Info.grants(GrantsDomainMixedPost) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == [:admin, :auditor, :editor, :viewer]
    end

    test "resource-only :editor grant contributes its permissions" do
      perms = AshGrant.GrantsResolver.resolve(editor(), %{resource: GrantsDomainMixedPost})
      assert "grants_domain_mixed_post:*:read:always" in perms
      assert "grants_domain_mixed_post:*:update:own" in perms
    end

    test "domain-only :admin broadcast still fires for the merged resource" do
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainMixedPost})
      assert "grants_domain_mixed_post:*:*:always" in perms
    end
  end

  describe "resource grant with the same name overrides the domain grant" do
    test "resource's :admin predicate (super_admin) wins — :admin actor gets nothing" do
      perms =
        AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainOverridePost})

      refute Enum.any?(perms, &String.starts_with?(&1, "grants_domain_override_post"))
    end

    test "super_admin actor matches the resource's overridden :admin predicate" do
      perms =
        AshGrant.GrantsResolver.resolve(super_admin(), %{
          resource: GrantsDomainOverridePost
        })

      assert "grants_domain_override_post:*:*:always" in perms
    end

    test "only one grant with the :admin name ends up in the merged list" do
      admin_grants =
        Info.grants(GrantsDomainOverridePost)
        |> Enum.filter(&(&1.name == :admin))

      assert length(admin_grants) == 1
    end
  end

  describe "resource with a custom resolver AND a grants-bearing domain" do
    test "Info.resolver/1 routes through GrantsResolver because the domain has grants" do
      assert Info.resolver(GrantsDomainResolverPost) == AshGrant.GrantsResolver
    end

    test "admin actor: domain :admin broadcast fires through to this resource too" do
      # The domain's broadcast `:admin` grant covers every resource — that
      # includes the one with a custom resolver. The custom resolver also
      # runs on top (and contributes nothing for this actor).
      perms =
        AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainResolverPost})

      assert "grants_domain_resolver_post:*:*:always" in perms
    end

    test "custom-resolver actor: no grant matches, user resolver still fires" do
      perms =
        AshGrant.GrantsResolver.resolve(%{role: :custom_resolver_actor}, %{
          resource: GrantsDomainResolverPost
        })

      assert "grants_domain_resolver_post:*:*:always" in perms
    end
  end

  describe "compile-time verification" do
    test "accepts both grants and an explicit resolver on the same domain — outputs merge" do
      # No longer a compile error. The merge runs at
      # `AshGrant.GrantsResolver.resolve/2`.
      defmodule DualDomain do
        use Ash.Domain,
          extensions: [AshGrant.Domain],
          validate_config_inclusion?: false

        ash_grant do
          resolver(fn _actor, _context -> ["grants_domain_post:*:read:"] end)

          grants do
            grant :admin, expr(^actor(:role) == :admin) do
              permission(:admin_all, :*, :always)
            end
          end
        end

        resources do
        end
      end

      assert AshGrant.Domain.Info.resolver(DualDomain) != nil
      grants = AshGrant.Domain.Info.grants(DualDomain)
      assert length(grants) == 1
    end

    test "broadcast permission compiles even when no resource is named" do
      # `permission :name, :action, :scope` with no `on:` is the new
      # default at the domain level. The verifier skips the action/scope
      # reference checks because the target isn't known until runtime.
      defmodule BroadcastDomain do
        use Ash.Domain,
          extensions: [AshGrant.Domain],
          validate_config_inclusion?: false

        ash_grant do
          grants do
            grant :universal, expr(^actor(:role) == :universal) do
              permission(:read_anywhere, :read)
              permission(:manage_anywhere, :*, :always)
            end
          end
        end

        resources do
        end
      end

      [grant] = AshGrant.Domain.Info.grants(BroadcastDomain)
      assert length(grant.permissions) == 2
      assert Enum.all?(grant.permissions, &(&1.on == nil))
    end

    test "warns on unknown action when a domain permission names its target" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule BogusActionDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, :bogus, :always, on: AshGrant.Test.GrantsDomainPost)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "`action: :bogus` is not defined"
    end

    test "warns on unknown scope when a domain permission names its target" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule BogusScopeDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, :read, :undefined, on: AshGrant.Test.GrantsDomainPost)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "`scope: :undefined` is not defined"
    end

    test "warns when `on:` is given but isn't an Ash.Resource" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule NonResourceDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, :read, :always, on: String)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "is not an `Ash.Resource`"
    end
  end
end
