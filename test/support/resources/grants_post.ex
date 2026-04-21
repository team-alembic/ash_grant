defmodule AshGrant.Test.GrantsPost do
  @moduledoc """
  Test resource driven by the declarative `grants` DSL instead of an
  explicit resolver function.

  Exercises the full AshGrant pipeline: `grants` → `SynthesizeGrantsResolver`
  → `GrantsResolver` → `Ash.Policy.Authorizer` → AshPostgres SQL.
  """

  use Ash.Resource,
    domain: AshGrant.Test.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  postgres do
    table("grants_posts")
    repo(AshGrant.TestRepo)
  end

  ash_grant do
    resource_name("grants_post")

    scope(:always, true)
    scope(:own, expr(author_id == ^actor(:id)))
    scope(:published, expr(status == :published))

    grants do
      grant :admin, expr(^actor(:role) == :admin) do
        description("Full administrative access")
        permission(:manage_all, :*, :always)
      end

      grant :editor, expr(^actor(:role) == :editor) do
        description("Editors read all, update own, create any")
        permission(:read_all, :read, :always)
        permission(:create_any, :create, :always)
        permission(:update_own, :update, :own)
      end

      grant :viewer, expr(^actor(:role) == :viewer) do
        description("Viewers see published only")
        permission(:read_published, :read, :published)
      end

      # Compound predicate — editor on a paid plan gets destroy rights
      grant :paid_editor, expr(^actor(:role) == :editor and ^actor(:plan) == :pro) do
        permission(:destroy_own, :destroy, :own)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(AshGrant.filter_check())
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if(AshGrant.check())
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true, allow_nil?: false)

    attribute :status, :atom do
      constraints(one_of: [:draft, :published])
      default(:draft)
      public?(true)
    end

    attribute(:author_id, :uuid, public?: true)
    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:title, :status, :author_id])
    end

    update :update do
      accept([:title, :status])
    end
  end
end
