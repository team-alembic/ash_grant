defmodule AshGrant.TestRepo.Migrations.CreateGrantsPostsTable do
  use Ecto.Migration

  def change do
    create table(:grants_posts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :status, :string, default: "draft"
      add :author_id, :uuid

      timestamps(type: :utc_datetime_usec)
    end

    create index(:grants_posts, [:author_id])
    create index(:grants_posts, [:status])
  end
end
