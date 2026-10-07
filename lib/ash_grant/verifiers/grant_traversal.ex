defmodule AshGrant.Verifiers.GrantTraversal do
  @moduledoc false
  # Shared traversal for grant verifiers. Walks `grants → permissions`,
  # invokes the validator on each permission, and short-circuits on the
  # first error.
  #
  # Used by both `AshGrant.Verifiers.GrantReferences` (resource-level)
  # and `AshGrant.Domain.Verifiers.ValidateGrantReferences` (domain-level).

  @type validator :: (AshGrant.Dsl.Permission.t(), AshGrant.Dsl.Grant.t() ->
                        :ok | {:error, Exception.t()})

  @spec each_permission([AshGrant.Dsl.Grant.t()], validator) :: :ok | {:error, Exception.t()}
  def each_permission(grants, validator) do
    Enum.reduce_while(grants, :ok, fn grant, :ok ->
      case validate_permissions(grant, validator) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_permissions(grant, validator) do
    Enum.reduce_while(grant.permissions || [], :ok, fn permission, :ok ->
      case validator.(permission, grant) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end
end
