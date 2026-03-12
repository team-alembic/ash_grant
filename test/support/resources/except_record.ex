defmodule AshGrant.Test.ExceptRecord do
  @moduledoc """
  Test resource for field_group `except` (blacklist) option.

  Uses ETS data layer and defines field groups using the `[:*]` wildcard
  with `except` to test the blacklist mode.

  ## Field Groups

  | Group | Definition | Resolved Fields |
  |-------|-----------|-----------------|
  | :public | `[:*], except: [:salary, :ssn]` | id, name, department, position, email, phone, address |
  | :full | inherits :public, adds [:salary, :ssn] | all fields |
  """
  use Ash.Resource,
    domain: AshGrant.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGrant]

  ash_grant do
    resolver(fn actor, _context ->
      case actor do
        %{permissions: perms} -> perms
        _ -> []
      end
    end)

    default_policies(true)
    default_field_policies(true)
    resource_name("exceptrecord")

    scope(:all, true)

    field_group(:public, [], [:*], except: [:salary, :ssn])
    field_group(:full, [:public], [:salary, :ssn])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true)
    attribute(:department, :string, public?: true)
    attribute(:position, :string, public?: true)
    attribute(:email, :string, public?: true)
    attribute(:phone, :string, public?: true)
    attribute(:address, :string, public?: true)
    attribute(:salary, :integer, public?: true)
    attribute(:ssn, :string, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
