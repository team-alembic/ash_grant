defmodule AshGrant.DomainGrantsTest do
  @moduledoc """
  Covers the declarative `grants` DSL when declared on an `Ash.Domain`
  instead of (or in addition to) a resource.

  The permission pipeline is the same as for resource-level grants
  (`SynthesizeGrantsResolver` → `GrantsResolver` → `Check`/`FilterCheck`);
  only the merge point in `AshGrant.Info.grants/1` and the domain-level
  transformer/verifier are new.
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
      assert Enum.map(grants, & &1.name) |> Enum.sort() == [:admin, :viewer]
    end

    test "AshGrant.Domain.Info.permissions/1 flattens permissions across grants" do
      perms = AshGrant.Domain.Info.permissions(GrantsOnlyDomain)
      names = Enum.map(perms, & &1.name) |> Enum.sort()
      assert names == [:manage_main, :manage_other, :read_published]
    end

    test "domain synthesizes the GrantsResolver when it declares grants" do
      assert AshGrant.Domain.Info.resolver(GrantsOnlyDomain) == AshGrant.GrantsResolver
    end
  end

  describe "resource with no grants inherits from the domain" do
    test "Info.grants/1 returns the two domain grants" do
      grants = Info.grants(GrantsDomainPost)
      assert Enum.map(grants, & &1.name) |> Enum.sort() == [:admin, :viewer]
    end

    test "resource inherits the GrantsResolver through Info.resolver/1 fallback" do
      assert Info.resolver(GrantsDomainPost) == AshGrant.GrantsResolver
    end

    test "admin actor gets permissions on the enclosing resource" do
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainPost})
      assert "grants_domain_post:*:*:always" in perms
    end

    test "admin actor also gets permissions on a sibling resource" do
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainPost})
      # The :admin grant declares permissions for two resources; both should
      # be emitted regardless of which resource the check is running against.
      assert "grants_domain_other:*:*:always" in perms
    end

    test "viewer sees only the :read :published permission" do
      perms = AshGrant.GrantsResolver.resolve(viewer(), %{resource: GrantsDomainPost})
      assert "grants_domain_post:*:read:published" in perms
      refute Enum.any?(perms, &String.starts_with?(&1, "grants_domain_post:*:*"))
    end

    test "unknown actor role yields no permissions" do
      assert [] =
               AshGrant.GrantsResolver.resolve(%{role: :stranger}, %{resource: GrantsDomainPost})
    end

    test "admin can read through the full policy pipeline" do
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

  describe "a domain grant pointing at a sibling resource covers that resource" do
    test "admin can read the :other resource even though it declares no grants" do
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
  end

  describe "resource with its own grants (different names) merges with domain grants" do
    test "Info.grants/1 returns both resource and domain grants" do
      names = Info.grants(GrantsDomainMixedPost) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == [:admin, :editor, :viewer]
    end

    test "editor grant (resource-only) contributes its permissions" do
      perms = AshGrant.GrantsResolver.resolve(editor(), %{resource: GrantsDomainMixedPost})
      assert "grants_domain_mixed_post:*:read:always" in perms
      assert "grants_domain_mixed_post:*:update:own" in perms
    end

    test "admin grant (domain-only) still appears in the merged grant list" do
      names = Info.grants(GrantsDomainMixedPost) |> Enum.map(& &1.name)
      assert :admin in names
    end

    test "admin grant's `on:` is respected — no permissions leak onto mixed resource" do
      # The domain's :admin grant declares permissions with
      # `on: GrantsDomainPost` and `on: GrantsDomainOther` — neither targets
      # the mixed resource. The permission strings the resolver emits reflect
      # that: admin gets coverage on the named resources, not on
      # GrantsDomainMixedPost. The check machinery filters by prefix, so a
      # downstream policy call for mixed would never see those strings match.
      perms = AshGrant.GrantsResolver.resolve(admin(), %{resource: GrantsDomainMixedPost})
      refute "grants_domain_mixed_post:*:*:always" in perms
      assert "grants_domain_post:*:*:always" in perms
      assert "grants_domain_other:*:*:always" in perms
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

  describe "resource with a custom resolver shadows domain grants" do
    test "resource's explicit resolver is used, not GrantsResolver" do
      resolver = Info.resolver(GrantsDomainResolverPost)
      refute resolver == AshGrant.GrantsResolver
      assert is_function(resolver, 2)
    end

    test "domain :admin grant does NOT apply (resource resolver returns [] for admin actor)" do
      resolver = Info.resolver(GrantsDomainResolverPost)
      assert resolver.(admin(), %{resource: GrantsDomainResolverPost}) == []
    end

    test "resource's custom resolver still runs for its own recognised actor" do
      resolver = Info.resolver(GrantsDomainResolverPost)

      assert resolver.(%{role: :custom_resolver_actor}, %{resource: GrantsDomainResolverPost}) ==
               [
                 "grants_domain_resolver_post:*:*:always"
               ]
    end
  end

  describe "compile-time verification" do
    test "rejects declaring both grants and explicit resolver on the same domain" do
      assert_raise Spark.Error.DslError, ~r/both `grants` and `resolver`/s, fn ->
        defmodule DualDomain do
          use Ash.Domain,
            extensions: [AshGrant.Domain],
            validate_config_inclusion?: false

          ash_grant do
            resolver(fn _actor, _context -> [] end)

            grants do
              grant :noop, expr(^actor(:role) == :admin) do
                permission(:noop, AshGrant.Test.GrantsDomainPost, :read, :always)
              end
            end
          end

          resources do
          end
        end
      end
    end

    # The four cases below are handled by the domain-level
    # `ValidateGrantReferences` verifier. Spark converts verifier errors into
    # compile warnings rather than raising, so `assert_raise` wouldn't catch
    # them — `capture_io(:stderr, ...)` observes the warning message instead.

    test "warns when the target resource is omitted and arity shifts to non-module `:on`" do
      # With optional `:scope`, a 3-arg call `permission(:name, :read, :always)`
      # is accepted by the macro — `on` silently binds to the plain atom
      # `:read`. The verifier catches that case by rejecting non-module
      # atoms with a pointed "did you forget the target?" message.
      warnings =
        capture_io(:stderr, fn ->
          defmodule MissingOnDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:no_target, :read, :always)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "is not a module"
      assert warnings =~ "forget the target"
    end

    test "warns on unknown action on the target resource" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule BogusActionDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, AshGrant.Test.GrantsDomainPost, :bogus, :always)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "`action: :bogus` is not defined"
    end

    test "warns on unknown scope on the target resource" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule BogusScopeDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, AshGrant.Test.GrantsDomainPost, :read, :undefined)
                end
              end
            end

            resources do
            end
          end
        end)

      assert warnings =~ "`scope: :undefined` is not defined"
    end

    test "warns when target is not an Ash.Resource" do
      warnings =
        capture_io(:stderr, fn ->
          defmodule NonResourceDomain do
            use Ash.Domain,
              extensions: [AshGrant.Domain],
              validate_config_inclusion?: false

            ash_grant do
              grants do
                grant :bad, expr(^actor(:role) == :admin) do
                  permission(:bad, String, :read, :always)
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
