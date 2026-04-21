defmodule AshGrant.GrantsIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the declarative `grants` DSL.

  Exercises the full pipeline with real DB reads/writes through
  `Ash.Policy.Authorizer`:

      grants DSL → SynthesizeGrantsResolver → GrantsResolver →
      Check/FilterCheck → Ash.Policy.Authorizer → AshPostgres SQL

  Verifies that every behavior guaranteed by the legacy imperative resolver
  (scope filtering on reads, check enforcement on writes, deny-wins,
  compound predicates) is preserved when the resolver is synthesized from
  declarative grants.
  """

  use AshGrant.DataCase, async: false

  alias AshGrant.Test.GrantsPost

  # === Actors ===

  defp admin, do: %{id: Ash.UUID.generate(), role: :admin}
  defp editor(id \\ Ash.UUID.generate()), do: %{id: id, role: :editor, plan: :free}
  defp paid_editor(id \\ Ash.UUID.generate()), do: %{id: id, role: :editor, plan: :pro}
  defp viewer, do: %{id: Ash.UUID.generate(), role: :viewer}
  defp stranger, do: %{id: Ash.UUID.generate(), role: :stranger}

  # === Helpers ===

  defp create_post!(attrs) do
    GrantsPost
    |> Ash.Changeset.for_create(:create, attrs, authorize?: false)
    |> Ash.create!(authorize?: false)
  end

  defp read_posts(actor) do
    GrantsPost
    |> Ash.Query.for_read(:read)
    |> Ash.read!(actor: actor)
  end

  # === Read policies driven by scope filters ===

  describe "read — synthesized resolver + FilterCheck" do
    test "admin sees all posts" do
      author = Ash.UUID.generate()
      p1 = create_post!(%{title: "a", status: :draft, author_id: author})
      p2 = create_post!(%{title: "b", status: :published, author_id: author})

      ids = read_posts(admin()) |> Enum.map(& &1.id)
      assert p1.id in ids
      assert p2.id in ids
    end

    test "editor sees all posts via :always scope" do
      author = Ash.UUID.generate()
      _p1 = create_post!(%{title: "a", status: :draft, author_id: author})
      _p2 = create_post!(%{title: "b", status: :published, author_id: author})

      assert length(read_posts(editor())) == 2
    end

    test "viewer only sees published posts (scope :published applied)" do
      author = Ash.UUID.generate()
      _draft = create_post!(%{title: "draft", status: :draft, author_id: author})
      pub = create_post!(%{title: "pub", status: :published, author_id: author})

      posts = read_posts(viewer())
      assert length(posts) == 1
      assert hd(posts).id == pub.id
    end

    test "actor matching no grant is denied (no permissions = default deny)" do
      _p1 = create_post!(%{title: "a", status: :published, author_id: Ash.UUID.generate()})
      assert_raise Ash.Error.Forbidden, fn -> read_posts(stranger()) end
    end

    test "nil actor is denied by policy" do
      _p1 = create_post!(%{title: "a", status: :published, author_id: Ash.UUID.generate()})
      assert_raise Ash.Error.Forbidden, fn -> read_posts(nil) end
    end
  end

  # === Write policies driven by Check ===

  describe "create — synthesized resolver + Check" do
    test "admin can create" do
      assert {:ok, _} =
               GrantsPost
               |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()})
               |> Ash.create(actor: admin())
    end

    test "editor can create" do
      assert {:ok, _} =
               GrantsPost
               |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()})
               |> Ash.create(actor: editor())
    end

    test "viewer cannot create" do
      assert {:error, %Ash.Error.Forbidden{}} =
               GrantsPost
               |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()})
               |> Ash.create(actor: viewer())
    end

    test "stranger cannot create" do
      assert {:error, %Ash.Error.Forbidden{}} =
               GrantsPost
               |> Ash.Changeset.for_create(:create, %{title: "a", author_id: Ash.UUID.generate()})
               |> Ash.create(actor: stranger())
    end
  end

  describe "update — :own scope narrows editor writes" do
    test "editor can update own post" do
      editor_id = Ash.UUID.generate()
      post = create_post!(%{title: "mine", author_id: editor_id})

      assert {:ok, updated} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "edited"})
               |> Ash.update(actor: editor(editor_id))

      assert updated.title == "edited"
    end

    test "editor cannot update another user's post" do
      mine = Ash.UUID.generate()
      other = Ash.UUID.generate()
      post = create_post!(%{title: "theirs", author_id: other})

      assert {:error, %Ash.Error.Forbidden{}} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "edited"})
               |> Ash.update(actor: editor(mine))
    end

    test "admin can update anyone's post" do
      post = create_post!(%{title: "theirs", author_id: Ash.UUID.generate()})

      assert {:ok, _} =
               post
               |> Ash.Changeset.for_update(:update, %{title: "edited"})
               |> Ash.update(actor: admin())
    end
  end

  describe "compound predicate — paid_editor grant" do
    test "free editor cannot destroy own post (no :destroy permission)" do
      editor_id = Ash.UUID.generate()
      post = create_post!(%{title: "mine", author_id: editor_id})

      assert {:error, %Ash.Error.Forbidden{}} =
               post
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: editor(editor_id))
    end

    test "pro editor can destroy own draft post" do
      editor_id = Ash.UUID.generate()
      post = create_post!(%{title: "mine", status: :draft, author_id: editor_id})

      assert :ok =
               post
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: paid_editor(editor_id))
    end

    test "pro editor cannot destroy another user's post (:own scope)" do
      mine = Ash.UUID.generate()
      other = Ash.UUID.generate()
      post = create_post!(%{title: "theirs", status: :draft, author_id: other})

      assert {:error, %Ash.Error.Forbidden{}} =
               post
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: paid_editor(mine))
    end
  end

  describe "resolver identity" do
    test "resource is wired to GrantsResolver, not a user function" do
      assert AshGrant.Info.resolver(GrantsPost) == AshGrant.GrantsResolver
    end

    test "resolver emits expected permission strings for each role" do
      context = %{resource: GrantsPost}

      admin_perms = AshGrant.GrantsResolver.resolve(admin(), context)
      assert "grants_post:*:*:always" in admin_perms

      editor_perms = AshGrant.GrantsResolver.resolve(editor(), context)
      assert "grants_post:*:read:always" in editor_perms
      assert "grants_post:*:create:always" in editor_perms
      assert "grants_post:*:update:own" in editor_perms
      refute "grants_post:*:destroy:own" in editor_perms

      pro_editor_perms = AshGrant.GrantsResolver.resolve(paid_editor(), context)
      assert "grants_post:*:destroy:own" in pro_editor_perms

      viewer_perms = AshGrant.GrantsResolver.resolve(viewer(), context)
      assert "grants_post:*:read:published" in viewer_perms
      refute "grants_post:*:create:always" in viewer_perms
    end
  end
end
