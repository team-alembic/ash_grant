defmodule AshGrant.TestRepo.Migrations.CreateServiceRequestsTable do
  use Ecto.Migration

  def change do
    create table(:service_requests, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :text, null: false
      add :requester_id, :uuid
      add :tenant_id, :uuid
      add :status, :text, default: "open"
      timestamps()
    end
  end
end
