defmodule AshGrant.ScopeDslTest do
  use ExUnit.Case, async: true

  alias AshGrant.Info

  # Test resource with scope DSL
  # Note: expr macro is auto-imported by the ash_grant DSL section
  defmodule TestPost do
    use Ash.Resource,
      domain: nil,
      validate_domain_inclusion?: false,
      extensions: [AshGrant]

    ash_grant do
      resolver(fn _actor, _context -> [] end)

      scope(:always, true, description: "All records without restriction")

      scope(:published, expr(status == :published),
        description: "Published posts visible to everyone"
      )

      scope(:draft, expr(status == :draft))
    end

    attributes do
      uuid_primary_key(:id)
      attribute(:title, :string, public?: true)
      attribute(:status, :atom, constraints: [one_of: [:draft, :published]])
      attribute(:author_id, :uuid)
    end
  end

  describe "scope DSL definition" do
    test "defines scopes on resource" do
      scopes = Info.scopes(TestPost)
      assert length(scopes) == 3

      scope_names = Enum.map(scopes, & &1.name)
      assert :always in scope_names
      assert :published in scope_names
      assert :draft in scope_names
    end

    test "scope has name and filter" do
      scopes = Info.scopes(TestPost)
      all_scope = Enum.find(scopes, &(&1.name == :always))

      assert all_scope.name == :always
      assert all_scope.filter == true
    end

    test "scope can have expression filter" do
      scopes = Info.scopes(TestPost)
      published_scope = Enum.find(scopes, &(&1.name == :published))

      assert published_scope.name == :published
      assert published_scope.filter != nil
      refute published_scope.filter == true
    end
  end

  describe "Info.get_scope/2" do
    test "returns scope by name" do
      scope = Info.get_scope(TestPost, :published)
      assert scope.name == :published
    end

    test "returns nil for unknown scope" do
      assert Info.get_scope(TestPost, :unknown) == nil
    end
  end

  describe "Info.resolve_scope_filter/3" do
    test "returns true for :always scope" do
      filter = Info.resolve_scope_filter(TestPost, :always, %{})
      assert filter == true
    end

    test "returns expression for :published scope" do
      filter = Info.resolve_scope_filter(TestPost, :published, %{})
      # Should return an Ash expression
      assert filter != nil
      refute filter == true
    end

    test "returns false for unknown scope" do
      filter = Info.resolve_scope_filter(TestPost, :unknown, %{})
      assert filter == false
    end
  end

  describe "scope description" do
    test "scope can have description" do
      scope = Info.get_scope(TestPost, :always)
      assert scope.description == "All records without restriction"
    end

    test "scope description is optional" do
      scope = Info.get_scope(TestPost, :draft)
      assert scope.description == nil
    end

    test "Info.scope_description/2 returns description for existing scope" do
      assert Info.scope_description(TestPost, :always) == "All records without restriction"
      assert Info.scope_description(TestPost, :published) == "Published posts visible to everyone"
    end

    test "Info.scope_description/2 returns nil for scope without description" do
      assert Info.scope_description(TestPost, :draft) == nil
    end

    test "Info.scope_description/2 returns nil for unknown scope" do
      assert Info.scope_description(TestPost, :unknown) == nil
    end
  end

  describe "scope do-block form" do
    defmodule DoBlockPost do
      use Ash.Resource,
        domain: nil,
        validate_domain_inclusion?: false,
        extensions: [AshGrant]

      ash_grant do
        resolver(fn _actor, _context -> [] end)

        scope :always, true do
          description("All records without restriction")
        end

        scope :own, expr(author_id == ^actor(:id)) do
          description("Records owned by the current user")
        end

        scope(:no_description, expr(status == :published))
      end

      attributes do
        uuid_primary_key(:id)
        attribute(:status, :atom, constraints: [one_of: [:draft, :published]])
        attribute(:author_id, :uuid)
      end
    end

    test "description set via do-block is preserved" do
      assert Info.get_scope(DoBlockPost, :always).description ==
               "All records without restriction"

      assert Info.get_scope(DoBlockPost, :own).description ==
               "Records owned by the current user"
    end

    test "do-block description is optional" do
      assert Info.get_scope(DoBlockPost, :no_description).description == nil
    end

    test "Info.scope_description/2 returns do-block description" do
      assert Info.scope_description(DoBlockPost, :own) ==
               "Records owned by the current user"
    end
  end
end
