defmodule AshGrant.GrantsDslTest do
  use ExUnit.Case, async: true

  alias AshGrant.Info

  defmodule Post do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      extensions: [AshGrant]

    ash_grant do
      resource_name("post")

      purposes([:content_management, :fraud_investigation, :audit, :compliance])

      scope(:always, true)
      scope(:own, expr(author_id == ^actor(:id)))
      scope(:published, expr(status == :published))

      grants do
        grant :admin, fn actor -> actor && Map.get(actor, :role) == :admin end do
          description("Full administrative access")
          purpose(:compliance)

          permission(:manage_all, :*, :always,
            description: "Any action on any post"
          )
        end

        grant :editor, fn actor -> actor && Map.get(actor, :role) == :editor end do
          description("Editors manage content")
          purpose(:content_management)

          permission(:read_all, :read, :always)
          permission(:update_own, :update, :own)
        end

        grant :viewer, fn actor -> actor && Map.get(actor, :role) == :viewer end do
          permission(:read_published, :read, :published,
            purposes: [:audit],
            description: "Read published posts"
          )
        end

        grant :archived_guard, fn actor -> actor && Map.get(actor, :role) == :editor end do
          permission(:no_destroy_archived, :destroy, :published, deny: true)
        end

        grant :specific_admin, fn actor -> actor && Map.get(actor, :role) == :specific end do
          permission(:manage_root_post, :update, :always, instance: "root-post-id")
        end
      end
    end

    actions do
      defaults([:read, :create, :update, :destroy])
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:status, :atom, constraints: [one_of: [:draft, :published]])
      attribute(:author_id, :uuid)
    end
  end

  describe "grants DSL parsing" do
    test "returns all declared grants" do
      grants = Info.grants(Post)
      assert length(grants) == 5

      names = Enum.map(grants, & &1.name)
      assert :admin in names
      assert :editor in names
      assert :viewer in names
      assert :archived_guard in names
      assert :specific_admin in names
    end

    test "grants carry predicates and metadata" do
      editor = Info.get_grant(Post, :editor)

      assert editor.name == :editor
      assert is_function(editor.predicate, 1)
      assert editor.description == "Editors manage content"
      assert editor.purpose == :content_management
    end

    test "flattens to permissions list" do
      permissions = Info.permissions(Post)
      assert length(permissions) == 6

      names = Enum.map(permissions, & &1.name)
      assert :manage_all in names
      assert :read_all in names
      assert :update_own in names
      assert :read_published in names
      assert :no_destroy_archived in names
      assert :manage_root_post in names
    end

    test "instance defaults to :* when omitted" do
      read_all = Info.permissions(Post) |> Enum.find(&(&1.name == :read_all))
      assert read_all.instance == :*
    end

    test "instance keyword overrides default" do
      specific = Info.permissions(Post) |> Enum.find(&(&1.name == :manage_root_post))
      assert specific.instance == "root-post-id"
    end

    test "permission `on:` defaults to current resource" do
      read_all = Info.permissions(Post) |> Enum.find(&(&1.name == :read_all))
      assert read_all.on == Post
      assert read_all.instance == :*
      assert read_all.action == :read
      assert read_all.scope == :always
    end

    test "deny flag is preserved" do
      deny_perm =
        Info.permissions(Post) |> Enum.find(&(&1.name == :no_destroy_archived))

      assert deny_perm.deny == true
    end
  end

  describe "purposes" do
    test "declared vocabulary is introspectable" do
      assert Info.declared_purposes(Post) ==
               [:content_management, :fraud_investigation, :audit, :compliance]
    end

    test "effective purposes merge grant + permission purposes" do
      viewer = Info.get_grant(Post, :viewer)
      read_published = Enum.find(viewer.permissions, &(&1.name == :read_published))

      assert Info.effective_purposes(viewer, read_published) == [:audit]
    end

    test "permissions_for_purpose returns matching pairs" do
      pairs = Info.permissions_for_purpose(Post, :content_management)
      assert length(pairs) == 2

      perm_names = Enum.map(pairs, fn {_grant, perm} -> perm.name end)
      assert :read_all in perm_names
      assert :update_own in perm_names
    end

    test "permissions_for_purpose finds purpose via permission-level override" do
      pairs = Info.permissions_for_purpose(Post, :audit)
      assert [{grant, perm}] = pairs
      assert grant.name == :viewer
      assert perm.name == :read_published
    end
  end

  describe "synthesized resolver" do
    setup do
      %{context: %{resource: Post}}
    end

    test "assigns the GrantsResolver module" do
      assert Info.resolver(Post) == AshGrant.GrantsResolver
    end

    test "emits permissions for matching actor", %{context: context} do
      admin_perms = AshGrant.GrantsResolver.resolve(%{role: :admin}, context)
      assert "post:*:*:always" in admin_perms
    end

    test "emits permissions for editor", %{context: context} do
      editor_perms = AshGrant.GrantsResolver.resolve(%{role: :editor}, context)

      assert "post:*:read:always" in editor_perms
      assert "post:*:update:own" in editor_perms
      # :editor role is also matched by :archived_guard grant
      assert "!post:*:destroy:published" in editor_perms
    end

    test "instance keyword is emitted in permission string", %{context: context} do
      perms = AshGrant.GrantsResolver.resolve(%{role: :specific}, context)
      assert "post:root-post-id:update:always" in perms
    end

    test "nil actor yields no permissions", %{context: context} do
      assert AshGrant.GrantsResolver.resolve(nil, context) == []
    end

    test "unknown actor role yields no permissions", %{context: context} do
      assert AshGrant.GrantsResolver.resolve(%{role: :random}, context) == []
    end

    test "deny prefix is emitted for deny permissions", %{context: context} do
      perms = AshGrant.GrantsResolver.resolve(%{role: :editor}, context)
      assert Enum.any?(perms, &String.starts_with?(&1, "!"))
    end

    test "missing resource in context yields no permissions" do
      assert AshGrant.GrantsResolver.resolve(%{role: :admin}, %{}) == []
    end
  end

  describe "compile-time verification" do
    test "rejects unknown purpose when vocabulary is declared" do
      assert_raise Spark.Error.DslError, ~r/Unknown purpose/s, fn ->
        defmodule BadPurposePost do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            extensions: [AshGrant]

          actions do
            defaults([:read])
          end

          ash_grant do
            purposes([:audit])
            scope(:always, true)

            grants do
              grant :bad, fn _ -> true end do
                permission(:audit_read, :read, :always, purpose: :typo_purpose)
              end
            end
          end

          attributes do
            uuid_primary_key(:id)
          end
        end
      end
    end

    test "rejects declaring both grants and explicit resolver" do
      assert_raise Spark.Error.DslError, ~r/both `grants` and `resolver`/s, fn ->
        defmodule DuelResolverPost do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            extensions: [AshGrant]

          actions do
            defaults([:read])
          end

          ash_grant do
            resolver(fn _actor, _context -> [] end)
            scope(:always, true)

            grants do
              grant :noop, fn _ -> true end do
                permission(:read_all, :read, :always)
              end
            end
          end

          attributes do
            uuid_primary_key(:id)
          end
        end
      end
    end
  end
end
