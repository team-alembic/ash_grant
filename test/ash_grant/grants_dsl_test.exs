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

      scope(:always, true)
      scope(:own, expr(author_id == ^actor(:id)))
      scope(:published, expr(status == :published))

      grants do
        grant :admin, expr(^actor(:role) == :admin) do
          description("Full administrative access")
          permission(:manage_all, :*, :always, description: "Any action on any post")
        end

        grant :editor, expr(^actor(:role) == :editor) do
          description("Editors manage content")
          permission(:read_all, :read, :always)
          permission(:update_own, :update, :own)
        end

        grant :viewer, expr(^actor(:role) == :viewer) do
          permission(:read_published, :read, :published, description: "Read published posts")
        end

        grant :archived_guard, expr(^actor(:role) == :editor) do
          permission(:no_destroy_archived, :destroy, :published, deny: true)
        end

        grant :specific_admin, expr(^actor(:role) == :specific) do
          permission(:manage_root_post, :update, :always, instance: "root-post-id")
        end

        grant :paid_user, expr(^actor(:plan) == :pro and ^actor(:trial_expired) == false) do
          permission(:create_pro, :create, :always)
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
      assert length(grants) == 6

      names = Enum.map(grants, & &1.name)
      assert :admin in names
      assert :editor in names
      assert :viewer in names
      assert :archived_guard in names
      assert :specific_admin in names
      assert :paid_user in names
    end

    test "grants carry predicate and metadata" do
      editor = Info.get_grant(Post, :editor)

      assert editor.name == :editor
      refute is_nil(editor.predicate)
      assert editor.description == "Editors manage content"
      assert Enum.empty?(editor.permissions) == false
    end

    test "flattens to permissions list" do
      permissions = Info.permissions(Post)
      assert length(permissions) == 7

      names = Enum.map(permissions, & &1.name)
      assert :manage_all in names
      assert :read_all in names
      assert :update_own in names
      assert :read_published in names
      assert :no_destroy_archived in names
      assert :manage_root_post in names
      assert :create_pro in names
    end

    test "permission `on:` defaults to current resource" do
      read_all = Info.permissions(Post) |> Enum.find(&(&1.name == :read_all))
      assert read_all.on == Post
      assert read_all.instance == :*
      assert read_all.action == :read
      assert read_all.scope == :always
    end

    test "instance defaults to :* when omitted" do
      read_all = Info.permissions(Post) |> Enum.find(&(&1.name == :read_all))
      assert read_all.instance == :*
    end

    test "instance keyword overrides default" do
      specific = Info.permissions(Post) |> Enum.find(&(&1.name == :manage_root_post))
      assert specific.instance == "root-post-id"
    end

    test "deny flag is preserved" do
      deny_perm =
        Info.permissions(Post) |> Enum.find(&(&1.name == :no_destroy_archived))

      assert deny_perm.deny == true
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

    test "compound predicates combine actor fields", %{context: context} do
      pro_active = %{plan: :pro, trial_expired: false}
      pro_expired = %{plan: :pro, trial_expired: true}
      free = %{plan: :free, trial_expired: false}

      assert "post:*:create:always" in AshGrant.GrantsResolver.resolve(pro_active, context)
      refute "post:*:create:always" in AshGrant.GrantsResolver.resolve(pro_expired, context)
      refute "post:*:create:always" in AshGrant.GrantsResolver.resolve(free, context)
    end

    test "actor missing predicate fields yields no permissions", %{context: context} do
      # Actor has no :role or :plan keys at all
      assert AshGrant.GrantsResolver.resolve(%{}, context) == []
    end

    test "context from caller is threaded into predicate evaluation" do
      # Sanity check the plumbing — the resolver reads context.context and
      # passes it to Ash.Expr.fill_template so predicates can reference
      # ^context(:key) values. This test uses the existing :admin grant
      # (whose predicate doesn't touch context) to confirm the call path
      # does not crash when a caller-provided context map is present.
      caller_ctx = %{resource: Post, context: %{request_id: "abc"}}
      assert "post:*:*:always" in AshGrant.GrantsResolver.resolve(%{role: :admin}, caller_ctx)
    end
  end

  describe "compile-time verification" do
    test "rejects unknown purpose — removed" do
      # purpose/purposes was removed from the DSL; this test asserts the
      # schema no longer accepts it.
      assert_raise Spark.Error.DslError, ~r/unknown options \[:purpose\]/, fn ->
        defmodule BadPurposePost do
          use Ash.Resource,
            domain: nil,
            validate_domain_inclusion?: false,
            extensions: [AshGrant]

          actions do
            defaults([:read])
          end

          ash_grant do
            scope(:always, true)

            grants do
              grant :bad, expr(^actor(:role) == :admin) do
                permission(:audit_read, :read, :always, purpose: :whatever)
              end
            end
          end

          attributes do
            uuid_primary_key(:id)
          end
        end
      end
    end

    test "accepts both grants and an explicit resolver — outputs merge" do
      # Both compile cleanly; `GrantsResolver` runs grants *and* calls the
      # user resolver, concatenating their permission lists. Deny-wins in
      # the evaluator continues to hold because both contributions flow
      # through the same `Evaluator.has_access?/3` path.
      defmodule DualPost do
        use Ash.Resource,
          domain: nil,
          validate_domain_inclusion?: false,
          extensions: [AshGrant]

        ash_grant do
          resource_name("dualpost")

          resolver(fn actor, _context ->
            case actor do
              %{role: :dynamic} -> ["dualpost:*:read:"]
              _ -> []
            end
          end)

          scope(:always, true)

          grants do
            grant :admin, expr(^actor(:role) == :admin) do
              permission(:manage_all, :*, :always)
            end
          end
        end

        actions do
          defaults([:read])
        end

        attributes do
          uuid_primary_key(:id)
        end
      end

      assert AshGrant.Info.resolver(DualPost) == AshGrant.GrantsResolver

      # Admin actor: grants match, user resolver returns []. Only the grant's
      # permission shows up.
      admin_perms = AshGrant.GrantsResolver.resolve(%{role: :admin}, %{resource: DualPost})
      assert "dualpost:*:*:always" in admin_perms
      refute "dualpost:*:read:" in admin_perms

      # Dynamic actor: no grant matches, user resolver contributes.
      dynamic_perms =
        AshGrant.GrantsResolver.resolve(%{role: :dynamic}, %{resource: DualPost})

      assert "dualpost:*:read:" in dynamic_perms
      refute Enum.any?(dynamic_perms, &String.contains?(&1, ":*:always"))

      # Actor matching neither: empty.
      assert [] = AshGrant.GrantsResolver.resolve(%{role: :nobody}, %{resource: DualPost})
    end
  end
end
