defmodule AshGrant.TestRepo.Migrations.CreateFeedsTable do
  use Ecto.Migration

  def change do
    create table(:feeds, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :feed_id, :string, null: false
      add :title, :string, null: false
      add :status, :string, default: "draft"

      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:feeds, [:feed_id])
    create index(:feeds, [:status])
  end
end
