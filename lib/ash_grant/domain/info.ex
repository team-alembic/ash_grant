defmodule AshGrant.Domain.Info do
  @moduledoc """
  Introspection helpers for AshGrant domain-level DSL configuration.

  Used internally by `AshGrant.Transformers.MergeDomainConfig` to read
  domain-level settings and merge them into resources.
  """

  @doc """
  Gets the permission resolver configured on the domain.
  """
  @spec resolver(Ash.Domain.t()) :: module() | function() | nil
  def resolver(domain) do
    Spark.Dsl.Extension.get_opt(domain, [:ash_grant], :resolver)
  end

  @doc """
  Gets all scope definitions from the domain.
  """
  @spec scopes(Ash.Domain.t()) :: [AshGrant.Dsl.Scope.t()]
  def scopes(domain) do
    Spark.Dsl.Extension.get_entities(domain, [:ash_grant])
    |> Enum.filter(&match?(%AshGrant.Dsl.Scope{}, &1))
  end

  @doc """
  Gets a specific scope by name from the domain.
  """
  @spec get_scope(Ash.Domain.t(), atom()) :: AshGrant.Dsl.Scope.t() | nil
  def get_scope(domain, name) do
    scopes(domain)
    |> Enum.find(&(&1.name == name))
  end

  @doc """
  Returns true if the domain has the `AshGrant.Domain` extension configured.
  """
  @spec configured?(Ash.Domain.t()) :: boolean()
  def configured?(domain) do
    extensions = Spark.extensions(domain)
    AshGrant.Domain in extensions
  rescue
    _ -> false
  end
end
